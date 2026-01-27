-- ============================================================================
-- Migration: tp_hash Slot (CPython Hash Protocol)
-- Created: 2026-01-14 23:50:00
--
-- Purpose:
--   Implements CPython's tp_hash slot system for hashable objects. This allows
--   objects to be hashed using the CPython-faithful mechanism: checking the
--   tp_hash slot pointer rather than type-specific implementations scattered
--   throughout the codebase.
--
-- CPython Structure:
--   typedef struct _typeobject {
--       // ...
--       hashfunc tp_hash;  // Function pointer for object hashing
--       // ...
--   } PyTypeObject;
--
--   In CPython:
--   - If tp_hash is NULL, the type is unhashable (e.g., list, dict)
--   - If tp_hash is not NULL, PyObject_Hash() calls it to compute hash value
--   - Hash values are used for dictionary lookups and set membership
--
-- This migration:
--   1. Implements py_object_hash() function (equivalent to PyObject_Hash)
--   2. Implements type-specific hash functions (str, int)
--   3. Registers tp_hash for hashable builtin types
--   4. Dict lookup hash-based: me_hash backfill/index, py_object_equals_key,
--      py_dict_get_item, py_dict_set_item, LOAD_NAME/STORE_NAME (hash-based).
--      Design: docs/DICT_LOOKUP_DESIGN.md
--   (tp_hash column is defined in 20260114220000_python_object_schema.sql)
--
-- ============================================================================

-- tp_hash column is defined in py_type_object (20260114220000_python_object_schema.sql).
-- This migration only adds functions, dict-entry me_hash/backfill/index, and slot registration.

-- ============================================================================
-- Function: py_object_hash (Equivalent to PyObject_Hash)
-- ============================================================================

-- py_object_hash: Compute hash value of a Python object
--
-- Parameters:
--   obj_id: UUID of the object to hash
--
-- Returns:
--   BIGINT: The hash value of the object
--
-- Behavior:
--   This is equivalent to CPython's PyObject_Hash(). It checks the object's
--   type's tp_hash slot and calls it if available. If tp_hash is NULL, raises
--   TypeError indicating the object is unhashable.
--
--   In CPython:
--   - PyObject_Hash checks Py_TYPE(obj)->tp_hash
--   - If tp_hash is not NULL, calls it: tp_hash(obj)
--   - If tp_hash is NULL, raises TypeError: unhashable type
--
-- Usage:
--   hash_value := py_object_hash(obj_id);
--
-- CPython Reference:
--   This function implements the core logic of PyObject_Hash in Objects/object.c.
--
CREATE OR REPLACE FUNCTION public.py_object_hash(obj_id UUID)
RETURNS BIGINT AS $$
DECLARE
    obj_type_id UUID;
    hash_func regproc;
    hash_value BIGINT;
    type_name TEXT;
BEGIN
    -- Validate object exists
    IF NOT EXISTS (SELECT 1 FROM public.py_object WHERE id = obj_id) THEN
        RAISE EXCEPTION 'py_object_hash: Object with id % does not exist', obj_id;
    END IF;
    
    -- Get object type
    SELECT ob_type INTO obj_type_id
    FROM public.py_object
    WHERE id = obj_id;
    
    IF obj_type_id IS NULL THEN
        RAISE EXCEPTION 'py_object_hash: Object with id % does not have a type', obj_id;
    END IF;
    
    -- Get tp_hash slot from type object
    SELECT tp_hash INTO hash_func
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;
    
    -- Check if object is hashable (tp_hash is not NULL)
    IF hash_func IS NULL THEN
        -- Get type name for error message
        SELECT tp_name INTO type_name
        FROM public.py_type_object
        WHERE ob_base = obj_type_id;
        
        RAISE EXCEPTION 'TypeError: unhashable type: ''%''', COALESCE(type_name, 'unknown');
    END IF;
    
    -- Call the tp_hash function
    -- The function signature is: func(obj_id UUID) RETURNS BIGINT
    EXECUTE format('SELECT %I($1)', hash_func::text) USING obj_id INTO hash_value;
    
    RETURN hash_value;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Type-Specific Hash Functions
-- ============================================================================

-- py_unicode_hash: Compute hash value of a string object
-- Implements CPython's PyUnicode_Hash() behavior
--
-- CPython Implementation:
--   - Uses FNV hash algorithm for strings
--   - PostgreSQL's hashtext() function provides a good hash function for text
--   - CPython's hash for strings is: hash(s) = hash(s[0], s[1], ..., s[n-1])
--
-- Note: CPython's string hash uses a specific algorithm (FNV), but for
-- correctness, we need a deterministic hash function. PostgreSQL's hashtext()
-- provides a good hash function that is deterministic within a session.
--
CREATE OR REPLACE FUNCTION public.py_unicode_hash(obj_id UUID)
RETURNS BIGINT AS $$
DECLARE
    str_val TEXT;
    hash_value BIGINT;
BEGIN
    -- Validate object exists and is a string
    IF NOT EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = obj_id) THEN
        RAISE EXCEPTION 'TypeError: py_unicode_hash called on non-string object';
    END IF;
    
    -- Get string value
    SELECT str_value INTO str_val
    FROM public.py_unicode_object
    WHERE ob_base = obj_id;
    
    IF str_val IS NULL THEN
        -- Empty string or NULL - hash to 0 (CPython behavior)
        RETURN 0;
    END IF;
    
    -- Compute hash using PostgreSQL's hashtext() function
    -- This provides a deterministic hash value for the string
    -- Note: CPython uses FNV hash, but hashtext() is sufficient for correctness
    hash_value := hashtext(str_val);
    
    RETURN hash_value;
END;
$$ LANGUAGE plpgsql;

-- py_long_hash: Compute hash value of an integer object
-- Implements CPython's PyLong_Hash() behavior
--
-- CPython Implementation:
--   - For small integers: hash(n) = n (identity function)
--   - For large integers: hash(n) = n % (2^31 - 1) or similar
--   - In CPython, hash(-1) = -2 (special case to avoid collision with -1 error return)
--
-- Note: CPython has special handling for -1, but for simplicity, we'll use
-- the value itself for small integers, and modulo for large integers.
--
CREATE OR REPLACE FUNCTION public.py_long_hash(obj_id UUID)
RETURNS BIGINT AS $$
DECLARE
    int_val NUMERIC;
    hash_value BIGINT;
BEGIN
    -- Validate object exists and is an integer
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = obj_id) THEN
        RAISE EXCEPTION 'TypeError: py_long_hash called on non-integer object';
    END IF;
    
    -- Get integer value
    SELECT long_value INTO int_val
    FROM public.py_long_object
    WHERE ob_base = obj_id;
    
    IF int_val IS NULL THEN
        RAISE EXCEPTION 'TypeError: integer object has no value';
    END IF;
    
    -- CPython's hash for integers:
    -- - For values in range: hash(n) = n (except -1 -> -2)
    -- - For large integers: hash(n) = n % (2^31 - 1)
    --
    -- PostgreSQL's BIGINT can hold values up to 2^63 - 1, so we can use
    -- the value directly for most cases. For very large values, we'll use
    -- modulo to keep the hash in a reasonable range.
    --
    -- Special case: CPython's hash(-1) = -2 to avoid collision with error return
    IF int_val = -1 THEN
        hash_value := -2;
    ELSE
        -- For values that fit in BIGINT, use the value directly
        -- For very large values, use modulo (2^31 - 1) like CPython
        IF int_val >= -9223372036854775808 AND int_val <= 9223372036854775807 THEN
            hash_value := int_val::BIGINT;
        ELSE
            -- Large integer: use modulo like CPython
            hash_value := (int_val % 2147483647)::BIGINT;
        END IF;
    END IF;
    
    RETURN hash_value;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Bootstrap: Register tp_hash for Hashable Builtin Types
-- ============================================================================

-- In CPython:
--   - PyUnicode_Type.tp_hash = PyUnicode_Hash
--   - PyLong_Type.tp_hash = PyLong_Hash
--   - PyList_Type.tp_hash = NULL (unhashable)
--   - PyDict_Type.tp_hash = NULL (unhashable)
--
-- Similarly, in Elytra, we register tp_hash for hashable types and leave
-- it NULL for unhashable types (list, dict, etc.).
DO $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
BEGIN
    -- Register tp_hash for str type
    -- This makes all string objects hashable
    UPDATE public.py_type_object
    SET tp_hash = 'py_unicode_hash'::regproc
    WHERE ob_base = ID_STR_TYPE;
    
    -- Register tp_hash for int type
    -- This makes all integer objects hashable
    UPDATE public.py_type_object
    SET tp_hash = 'py_long_hash'::regproc
    WHERE ob_base = ID_INT_TYPE;
    
    -- Note: list, dict, and other mutable types have tp_hash = NULL (unhashable)
    -- This is already the default (NULL), so no explicit UPDATE needed.
    -- CPython behavior: mutable types are unhashable to prevent issues with
    -- hash-based collections (dicts, sets) when the object's value changes.
END $$;

-- ============================================================================
-- Dict Lookup Hash-Based (CPython PyDictKeyEntry.me_hash)
-- ============================================================================
-- Key hash narrows candidates, key equality confirms. Design: docs/DICT_LOOKUP_DESIGN.md

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'py_dict_entry' AND column_name = 'me_hash'
    ) THEN
        ALTER TABLE public.py_dict_entry ADD COLUMN me_hash bigint;
    END IF;
END $$;

UPDATE public.py_dict_entry e
SET me_hash = public.py_object_hash(e.me_key)
WHERE e.me_hash IS NULL;

ALTER TABLE public.py_dict_entry
ALTER COLUMN me_hash SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_py_dict_entry_dict_id_me_hash
ON public.py_dict_entry (dict_id, me_hash);

CREATE OR REPLACE FUNCTION public.py_object_equals_key(a_id UUID, b_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    type_a_id UUID;
    type_b_id UUID;
    tp_name_a TEXT;
    tp_name_b TEXT;
    str_a TEXT;
    str_b TEXT;
    long_a NUMERIC;
    long_b NUMERIC;
BEGIN
    IF a_id IS NULL OR b_id IS NULL THEN
        RETURN FALSE;
    END IF;
    IF a_id = b_id THEN
        RETURN TRUE;
    END IF;

    SELECT ob_type INTO type_a_id FROM public.py_object WHERE id = a_id;
    SELECT ob_type INTO type_b_id FROM public.py_object WHERE id = b_id;
    IF type_a_id IS NULL OR type_b_id IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT tp_name INTO tp_name_a FROM public.py_type_object WHERE ob_base = type_a_id;
    SELECT tp_name INTO tp_name_b FROM public.py_type_object WHERE ob_base = type_b_id;

    IF tp_name_a = 'str' AND tp_name_b = 'str' THEN
        SELECT str_value INTO str_a FROM public.py_unicode_object WHERE ob_base = a_id;
        SELECT str_value INTO str_b FROM public.py_unicode_object WHERE ob_base = b_id;
        RETURN (str_a IS NOT DISTINCT FROM str_b);
    END IF;

    IF tp_name_a = 'int' AND tp_name_b = 'int' THEN
        SELECT long_value INTO long_a FROM public.py_long_object WHERE ob_base = a_id;
        SELECT long_value INTO long_b FROM public.py_long_object WHERE ob_base = b_id;
        RETURN (long_a IS NOT DISTINCT FROM long_b);
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_dict_get_item(dict_id UUID, key_id UUID)
RETURNS UUID AS $$
DECLARE
    h BIGINT;
    val_id UUID;
BEGIN
    h := public.py_object_hash(key_id);
    SELECT e.me_value INTO val_id
    FROM public.py_dict_entry e
    WHERE e.dict_id = py_dict_get_item.dict_id
      AND e.me_hash = h
      AND public.py_object_equals_key(e.me_key, key_id)
    LIMIT 1;
    RETURN val_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_dict_set_item(dict_id UUID, key_id UUID, value_id UUID)
RETURNS VOID AS $$
DECLARE
    h BIGINT;
    entry_id UUID;
BEGIN
    h := public.py_object_hash(key_id);
    SELECT e.id INTO entry_id
    FROM public.py_dict_entry e
    WHERE e.dict_id = py_dict_set_item.dict_id
      AND e.me_hash = h
      AND public.py_object_equals_key(e.me_key, key_id)
    LIMIT 1;

    IF entry_id IS NOT NULL THEN
        UPDATE public.py_dict_entry SET me_value = value_id WHERE id = entry_id;
    ELSE
        INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
        VALUES (py_dict_set_item.dict_id, key_id, value_id, h);
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_opcode_STORE_NAME(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    f_locals_id UUID;
    value_obj_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'STORE_NAME: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Index % out of range for co_names tuple', name_index;
    END IF;
    SELECT f_locals INTO f_locals_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF f_locals_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Frame with id % does not have f_locals', frame_id;
    END IF;

    value_obj_id := public.py_stack_pop(frame_id);
    PERFORM public.py_dict_set_item(f_locals_id, name_str_id, value_obj_id);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_NAME(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    name_str TEXT;
    obj_id UUID;
    f_locals_id UUID;
    f_globals_id UUID;
    f_builtins_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'LOAD_NAME: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Index % out of range for co_names tuple', name_index;
    END IF;
    SELECT str_value INTO name_str FROM public.py_unicode_object WHERE ob_base = name_str_id;

    SELECT f_locals, f_globals, f_builtins INTO f_locals_id, f_globals_id, f_builtins_id
    FROM public.py_frame_object WHERE ob_base = frame_id;
    IF f_locals_id IS NULL OR f_globals_id IS NULL OR f_builtins_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Frame with id % does not have all required namespaces (locals, globals, builtins)', frame_id;
    END IF;

    obj_id := public.py_dict_get_item(f_locals_id, name_str_id);
    IF obj_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;
    obj_id := public.py_dict_get_item(f_globals_id, name_str_id);
    IF obj_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;
    obj_id := public.py_dict_get_item(f_builtins_id, name_str_id);
    IF obj_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;

    RAISE EXCEPTION 'NameError: name ''%'' is not defined', COALESCE(name_str, 'unknown');
END;
$$ LANGUAGE plpgsql;
