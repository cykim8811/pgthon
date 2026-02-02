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
--   2. Implements type-specific hash functions (str, int, bytes, float, bool, None, tuple)
--   3. Registers tp_hash for all hashable builtin types
--   4. Dict lookup hash-based: me_hash backfill/index,
--      py_dict_get_item, py_dict_set_item (key equality via py_object_richcompare_eq in 236000), LOAD_NAME/STORE_NAME.
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
    
    -- Unhashable: set Python TypeError and return NULL (CPython 고증)
    IF hash_func IS NULL THEN
        SELECT tp_name INTO type_name
        FROM public.py_type_object
        WHERE ob_base = obj_type_id;
        PERFORM public.py_err_set_type_error('unhashable type: ''' || COALESCE(type_name, 'unknown') || '''');
        RETURN NULL;
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
    -- Validate object exists and is a string (CPython 고증: TypeError via py_err_set_*)
    IF NOT EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_unicode_hash called on non-string object');
        RETURN NULL;
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
    -- Validate object exists and is an integer (CPython 고증: TypeError via py_err_set_*)
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_long_hash called on non-integer object');
        RETURN NULL;
    END IF;
    
    -- Get integer value
    SELECT long_value INTO int_val
    FROM public.py_long_object
    WHERE ob_base = obj_id;
    
    IF int_val IS NULL THEN
        PERFORM public.py_err_set_type_error('integer object has no value');
        RETURN NULL;
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
-- Type-Specific Hash: bytes, float, bool, None, tuple (CPython hashable scope)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_bytes_hash(obj_id uuid)
RETURNS bigint AS $$
DECLARE
    bval bytea;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_bytes_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_bytes_hash called on non-bytes object');
        RETURN NULL;
    END IF;
    SELECT bytes_value INTO bval FROM public.py_bytes_object WHERE ob_base = obj_id;
    IF bval IS NULL OR length(bval) = 0 THEN
        RETURN 0;
    END IF;
    RETURN hashtext(encode(bval, 'hex'))::bigint;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_float_hash(obj_id uuid)
RETURNS bigint AS $$
DECLARE
    fval double precision;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_float_hash called on non-float object');
        RETURN NULL;
    END IF;
    SELECT ob_fval INTO fval FROM public.py_float_object WHERE ob_base = obj_id;
    RETURN hashtext(fval::text)::bigint;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_bool_hash(obj_id uuid)
RETURNS bigint AS $$
DECLARE
    bval boolean;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_bool_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_bool_hash called on non-bool object');
        RETURN NULL;
    END IF;
    SELECT bool_value INTO bval FROM public.py_bool_object WHERE ob_base = obj_id;
    RETURN CASE WHEN bval THEN 1 ELSE 0 END;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_none_hash(obj_id uuid)
RETURNS bigint AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_none_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_none_hash called on non-None object');
        RETURN NULL;
    END IF;
    RETURN 0;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_tuple_hash(obj_id uuid)
RETURNS bigint AS $$
DECLARE
    items uuid[];
    n int;
    i int;
    h bigint;
    total numeric := 0;
    mult constant numeric := 1000003;
    lim64 constant numeric := 18446744073709551616;
    mid   constant numeric := 9223372036854775808;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_tuple_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_tuple_hash called on non-tuple object');
        RETURN NULL;
    END IF;
    SELECT ob_item INTO items FROM public.py_tuple_object WHERE ob_base = obj_id;
    n := coalesce(array_length(items, 1), 0);
    IF n = 0 THEN
        RETURN 0;
    END IF;
    FOR i IN 1..n LOOP
        h := public.py_object_hash(items[i]);
        total := (total * mult + h);
    END LOOP;
    total := mod(total + n, lim64);
    IF total >= mid THEN
        total := total - lim64;
    END IF;
    RETURN total::bigint;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    id_bytes  uuid := '00000000-0000-4000-a000-000000000012';
    id_float  uuid := '00000000-0000-4000-a000-000000000009';
    id_bool   uuid := '00000000-0000-4000-a000-000000000013';
    id_none   uuid := '00000000-0000-4000-a000-000000000008';
    id_tuple  uuid := '00000000-0000-4000-a000-000000000007';
BEGIN
    UPDATE public.py_type_object SET tp_hash = 'py_bytes_hash'::regproc  WHERE ob_base = id_bytes;
    UPDATE public.py_type_object SET tp_hash = 'py_float_hash'::regproc  WHERE ob_base = id_float;
    UPDATE public.py_type_object SET tp_hash = 'py_bool_hash'::regproc   WHERE ob_base = id_bool;
    UPDATE public.py_type_object SET tp_hash = 'py_none_hash'::regproc   WHERE ob_base = id_none;
    UPDATE public.py_type_object SET tp_hash = 'py_tuple_hash'::regproc  WHERE ob_base = id_tuple;
END $$;

-- ============================================================================
-- Dict Lookup Hash-Based (CPython PyDictKeyEntry.me_hash)
-- ============================================================================
-- Key hash narrows candidates, key equality confirms. Design: docs/DICT_LOOKUP_DESIGN.md
-- me_hash column is defined on py_dict_entry in 20260114220000_python_object_schema.sql.

UPDATE public.py_dict_entry e
SET me_hash = public.py_object_hash(e.me_key)
WHERE e.me_hash IS NULL;

ALTER TABLE public.py_dict_entry
ALTER COLUMN me_hash SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_py_dict_entry_dict_id_me_hash
ON public.py_dict_entry (dict_id, me_hash);

-- Dict key equality uses py_object_richcompare_eq (defined in 236000).
CREATE OR REPLACE FUNCTION public.py_dict_get_item(dict_id UUID, key_id UUID)
RETURNS UUID AS $$
DECLARE
    h BIGINT;
    val_id UUID;
BEGIN
    h := public.py_object_hash(key_id);
    IF h IS NULL AND public.py_err_occurred() THEN
        RETURN NULL;
    END IF;
    SELECT e.me_value INTO val_id
    FROM public.py_dict_entry e
    WHERE e.dict_id = py_dict_get_item.dict_id
      AND e.me_hash = h
      AND public.py_object_richcompare_eq(e.me_key, key_id)
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
    IF h IS NULL AND public.py_err_occurred() THEN
        RETURN;
    END IF;
    SELECT e.id INTO entry_id
    FROM public.py_dict_entry e
    WHERE e.dict_id = py_dict_set_item.dict_id
      AND e.me_hash = h
      AND public.py_object_richcompare_eq(e.me_key, key_id)
    LIMIT 1;

    IF entry_id IS NOT NULL THEN
        UPDATE public.py_dict_entry SET me_value = value_id WHERE id = entry_id;
    ELSE
        INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
        VALUES (py_dict_set_item.dict_id, key_id, value_id, h);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- lookup_in_type_and_bases: Phase 2 — type + tp_bases DFS (no MRO/C3)
-- Design: docs/LOAD_ATTR_DESIGN.md §7.4. No tp_name comparison.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.lookup_in_type_and_bases(
    type_id UUID,
    obj_id UUID,
    name_str_id UUID
) RETURNS UUID AS $$
DECLARE
    dict_id UUID;
    attr_id UUID;
    attr_type_id UUID;
    get_str_id UUID;
    get_id UUID;
    result_id UUID;
    bases_tuple_id UUID;
    base_items UUID[];
    n_bases INT;
    i INT;
    base_id UUID;
BEGIN
    -- 1. type_id must be a py_type_object row
    IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = type_id) THEN
        RETURN NULL;
    END IF;

    -- 2. tp_dict
    SELECT tp_dict INTO dict_id FROM public.py_type_object WHERE ob_base = type_id;
    IF dict_id IS NOT NULL THEN
        -- 3. Look up name in type's tp_dict
        attr_id := public.py_dict_get_item(dict_id, name_str_id);
        IF attr_id IS NOT NULL THEN
            -- Descriptor: if attr's type has __get__, call __get__(attr, obj, type)
            SELECT ob_type INTO attr_type_id FROM public.py_object WHERE id = attr_id;
            IF attr_type_id IS NOT NULL THEN
                get_str_id := public.py_str_from_text('__get__');
                IF get_str_id IS NULL AND public.py_err_occurred() THEN
                    RETURN NULL;
                END IF;
                SELECT tp_dict INTO dict_id FROM public.py_type_object WHERE ob_base = attr_type_id;
                IF dict_id IS NOT NULL THEN
                    get_id := public.py_dict_get_item(dict_id, get_str_id);
                    IF get_id IS NOT NULL THEN
                        result_id := public.py_object_call(get_id, ARRAY[attr_id, obj_id, type_id], NULL);
                        IF result_id IS NULL AND public.py_err_occurred() THEN
                            RETURN NULL;
                        END IF;
                        RETURN result_id;
                    END IF;
                END IF;
            END IF;
            RETURN attr_id;
        END IF;
    END IF;

    -- 4. tp_bases
    SELECT tp_bases INTO bases_tuple_id FROM public.py_type_object WHERE ob_base = type_id;
    IF bases_tuple_id IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT ob_item INTO base_items FROM public.py_tuple_object WHERE ob_base = bases_tuple_id;
    IF base_items IS NULL THEN
        RETURN NULL;
    END IF;
    n_bases := array_length(base_items, 1);
    IF n_bases IS NULL OR n_bases < 1 THEN
        RETURN NULL;
    END IF;

    -- 5. Recurse over each base in order
    FOR i IN 1..n_bases LOOP
        base_id := base_items[i];
        result_id := public.lookup_in_type_and_bases(base_id, obj_id, name_str_id);
        IF result_id IS NOT NULL THEN
            RETURN result_id;
        END IF;
        -- If recursive call set an exception, propagate
        IF public.py_err_occurred() THEN
            RETURN NULL;
        END IF;
    END LOOP;

    -- 6. Not found
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- lookup_attr_in_type_and_bases: type + tp_bases DFS, return attr_id only (no __get__)
-- For STORE_ATTR: find name in type/bases, return descriptor/attr id; design: docs/STORE_ATTR_DESIGN.md §4.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.lookup_attr_in_type_and_bases(type_id UUID, name_str_id UUID)
RETURNS UUID AS $$
DECLARE
    dict_id UUID;
    attr_id UUID;
    bases_tuple_id UUID;
    base_items UUID[];
    n_bases INT;
    i INT;
    base_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = type_id) THEN
        RETURN NULL;
    END IF;

    SELECT tp_dict INTO dict_id FROM public.py_type_object WHERE ob_base = type_id;
    IF dict_id IS NOT NULL THEN
        attr_id := public.py_dict_get_item(dict_id, name_str_id);
        IF attr_id IS NOT NULL THEN
            RETURN attr_id;
        END IF;
    END IF;

    SELECT tp_bases INTO bases_tuple_id FROM public.py_type_object WHERE ob_base = type_id;
    IF bases_tuple_id IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT ob_item INTO base_items FROM public.py_tuple_object WHERE ob_base = bases_tuple_id;
    IF base_items IS NULL THEN
        RETURN NULL;
    END IF;
    n_bases := array_length(base_items, 1);
    IF n_bases IS NULL OR n_bases < 1 THEN
        RETURN NULL;
    END IF;

    FOR i IN 1..n_bases LOOP
        base_id := base_items[i];
        attr_id := public.lookup_attr_in_type_and_bases(base_id, name_str_id);
        IF attr_id IS NOT NULL THEN
            RETURN attr_id;
        END IF;
        IF public.py_err_occurred() THEN
            RETURN NULL;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_object_getattr: Get attribute by name (Phase 2: instance __dict__ then type+bases)
-- CPython: PyObject_GetAttr; design: docs/LOAD_ATTR_DESIGN.md §7.3.
-- Uses py_instance_object.in_dict, lookup_in_type_and_bases; no tp_name comparison.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_object_getattr(obj_id UUID, name_str_id UUID)
RETURNS UUID AS $$
DECLARE
    type_id UUID;
    search_type_id UUID;
    in_dict_id UUID;
    attr_id UUID;
    result_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_object WHERE id = obj_id) THEN
        PERFORM public.py_err_set_attribute_error('object has no attribute');
        RETURN NULL;
    END IF;

    SELECT ob_type INTO type_id FROM public.py_object WHERE id = obj_id;
    IF type_id IS NULL THEN
        PERFORM public.py_err_set_attribute_error('object has no type');
        RETURN NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = type_id) THEN
        PERFORM public.py_err_set_attribute_error('object type has no tp_dict');
        RETURN NULL;
    END IF;

    -- Search base: if obj is a type (has py_type_object row), search in obj's tp_dict; else in type(obj)'s tp_dict. Design: docs/GETATTR_TYPE_OBJECT_PLAN.md.
    IF EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = obj_id) THEN
        search_type_id := obj_id;
    ELSE
        search_type_id := type_id;
    END IF;

    -- 1. Instance __dict__: if obj is instance and in_dict present, look up there first
    SELECT i.in_dict INTO in_dict_id
    FROM public.py_instance_object i
    WHERE i.ob_base = obj_id;
    IF in_dict_id IS NOT NULL THEN
        attr_id := public.py_dict_get_item(in_dict_id, name_str_id);
        IF attr_id IS NOT NULL THEN
            RETURN attr_id;
        END IF;
    END IF;

    -- 2. Type + bases (lookup_in_type_and_bases)
    result_id := public.lookup_in_type_and_bases(search_type_id, obj_id, name_str_id);
    IF result_id IS NOT NULL THEN
        RETURN result_id;
    END IF;
    IF public.py_err_occurred() THEN
        RETURN NULL;
    END IF;

    -- 3. Not found
    PERFORM public.py_err_set_attribute_error('object has no attribute');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_object_setattr: Set attribute by name (CPython PyObject_SetAttr)
-- Design: docs/STORE_ATTR_DESIGN.md §3.1. Descriptor __set__ then instance __dict__.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_object_setattr(obj_id UUID, name_str_id UUID, value_id UUID)
RETURNS VOID AS $$
DECLARE
    type_id UUID;
    attr_id UUID;
    attr_type_id UUID;
    set_str_id UUID;
    set_id UUID;
    in_dict_id UUID;
    new_dict_id UUID;
    dict_type_id UUID := '00000000-0000-4000-a000-000000000006';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_object WHERE id = obj_id) THEN
        PERFORM public.py_err_set_attribute_error('object has no attribute');
        RETURN;
    END IF;

    SELECT ob_type INTO type_id FROM public.py_object WHERE id = obj_id;
    IF type_id IS NULL THEN
        PERFORM public.py_err_set_attribute_error('object has no type');
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = type_id) THEN
        PERFORM public.py_err_set_attribute_error('object type has no tp_dict');
        RETURN;
    END IF;

    -- 1. Type + bases: lookup name; if descriptor with __set__, call __set__(attr, obj, value)
    attr_id := public.lookup_attr_in_type_and_bases(type_id, name_str_id);
    IF public.py_err_occurred() THEN
        RETURN;
    END IF;
    IF attr_id IS NOT NULL THEN
        SELECT ob_type INTO attr_type_id FROM public.py_object WHERE id = attr_id;
        IF attr_type_id IS NOT NULL THEN
            set_str_id := public.py_str_from_text('__set__');
            IF set_str_id IS NULL AND public.py_err_occurred() THEN
                RETURN;
            END IF;
            SELECT tp_dict INTO type_id FROM public.py_type_object WHERE ob_base = attr_type_id;
            IF type_id IS NOT NULL THEN
                set_id := public.py_dict_get_item(type_id, set_str_id);
                IF set_id IS NOT NULL THEN
                    PERFORM public.py_object_call(set_id, ARRAY[attr_id, obj_id, value_id], NULL);
                    IF public.py_err_occurred() THEN
                        RETURN;
                    END IF;
                    RETURN;
                END IF;
            END IF;
        END IF;
    END IF;

    -- 2. Instance __dict__: py_instance_object row must exist
    SELECT i.in_dict INTO in_dict_id
    FROM public.py_instance_object i
    WHERE i.ob_base = obj_id;
    IF NOT FOUND THEN
        PERFORM public.py_err_set_attribute_error('object has no attribute');
        RETURN;
    END IF;
    IF in_dict_id IS NULL THEN
        new_dict_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (new_dict_id, dict_type_id);
        INSERT INTO public.py_dict_object (ob_base) VALUES (new_dict_id);
        UPDATE public.py_instance_object SET in_dict = new_dict_id WHERE ob_base = obj_id;
        in_dict_id := new_dict_id;
    END IF;
    PERFORM public.py_dict_set_item(in_dict_id, name_str_id, value_id);
    IF public.py_err_occurred() THEN
        RETURN;
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

    PERFORM public.py_err_set_name_error('name ''' || COALESCE(name_str, 'unknown') || ''' is not defined');
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- LOAD_ATTR Opcode (CPython 106). Depends on py_object_getattr (this file).
-- ============================================================================
-- LOAD_ATTR(name_index): TOS = obj; replace TOS with getattr(obj, co_names[name_index]).
-- Design: docs/LOAD_ATTR_DESIGN.md
--
CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_ATTR(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    obj_id UUID;
    result_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'LOAD_ATTR: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_ATTR: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_ATTR: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_ATTR: Index % out of range for co_names tuple', name_index;
    END IF;

    obj_id := public.py_stack_pop(frame_id);
    result_id := public.py_object_getattr(obj_id, name_str_id);
    IF result_id IS NULL AND public.py_err_occurred() THEN
        RETURN;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- STORE_ATTR Opcode (CPython 95). Depends on py_object_setattr (this file).
-- ============================================================================
-- STORE_ATTR(name_index): TOS = owner, SECOND = value; setattr(owner, co_names[name_index], value).
-- Design: docs/STORE_ATTR_DESIGN.md
--
CREATE OR REPLACE FUNCTION public.py_opcode_STORE_ATTR(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    obj_id UUID;
    value_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'STORE_ATTR: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'STORE_ATTR: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'STORE_ATTR: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'STORE_ATTR: Index % out of range for co_names tuple', name_index;
    END IF;

    obj_id := public.py_stack_pop(frame_id);
    value_id := public.py_stack_pop(frame_id);
    PERFORM public.py_object_setattr(obj_id, name_str_id, value_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Descriptor __set__ / __get__ builtins (METH_VARARGS) for data descriptor tests
-- Design: docs/STORE_ATTR_DESIGN.md §1.3. __set__(self, obj, value); __get__(self, obj).
-- Used by type tp_dict["__set__"] / tp_dict["__get__"]; descriptor instance stores value in in_dict["_val"].
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_builtin_descriptor_set(func_obj_id UUID, args UUID[])
RETURNS UUID AS $$
DECLARE
    descriptor_id UUID;
    value_id UUID;
    in_dict_id UUID;
    new_dict_id UUID;
    val_str_id UUID;
    ID_NONE_OBJ UUID := '00000000-0000-4000-b000-000000000001';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
BEGIN
    IF array_length(args, 1) < 3 THEN
        PERFORM public.py_err_set_type_error('descriptor __set__ requires 3 arguments');
        RETURN NULL;
    END IF;
    descriptor_id := args[1];
    value_id := args[3];
    SELECT i.in_dict INTO in_dict_id
    FROM public.py_instance_object i
    WHERE i.ob_base = descriptor_id;
    IF NOT FOUND THEN
        PERFORM public.py_err_set_type_error('descriptor __set__: descriptor must have __dict__');
        RETURN NULL;
    END IF;
    IF in_dict_id IS NULL THEN
        new_dict_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (new_dict_id, ID_DICT_TYPE);
        INSERT INTO public.py_dict_object (ob_base) VALUES (new_dict_id);
        UPDATE public.py_instance_object SET in_dict = new_dict_id WHERE ob_base = descriptor_id;
        in_dict_id := new_dict_id;
    END IF;
    val_str_id := public.py_str_from_text('_val');
    IF val_str_id IS NULL AND public.py_err_occurred() THEN
        RETURN NULL;
    END IF;
    PERFORM public.py_dict_set_item(in_dict_id, val_str_id, value_id);
    RETURN ID_NONE_OBJ;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_builtin_descriptor_get(func_obj_id UUID, args UUID[])
RETURNS UUID AS $$
DECLARE
    descriptor_id UUID;
    in_dict_id UUID;
    val_str_id UUID;
    result_id UUID;
BEGIN
    IF array_length(args, 1) < 2 THEN
        PERFORM public.py_err_set_type_error('descriptor __get__ requires 2 arguments');
        RETURN NULL;
    END IF;
    descriptor_id := args[1];
    SELECT i.in_dict INTO in_dict_id
    FROM public.py_instance_object i
    WHERE i.ob_base = descriptor_id;
    IF NOT FOUND OR in_dict_id IS NULL THEN
        RETURN NULL;
    END IF;
    val_str_id := public.py_str_from_text('_val');
    IF val_str_id IS NULL AND public.py_err_occurred() THEN
        RETURN NULL;
    END IF;
    result_id := public.py_dict_get_item(in_dict_id, val_str_id);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    ID_DESCRIPTOR_SET UUID := '00000000-0000-4000-b000-000000000020';
    ID_DESCRIPTOR_GET UUID := '00000000-0000-4000-b000-000000000021';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    s_set_name_id UUID;
    s_set_doc_id UUID;
    s_get_name_id UUID;
    s_get_doc_id UUID;
BEGIN
    s_set_name_id := gen_random_uuid();
    s_set_doc_id := gen_random_uuid();
    s_get_name_id := gen_random_uuid();
    s_get_doc_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES
    (s_set_name_id, ID_STR_TYPE),
    (s_set_doc_id, ID_STR_TYPE),
    (s_get_name_id, ID_STR_TYPE),
    (s_get_doc_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES
    (s_set_name_id, '__set__'),
    (s_set_doc_id, 'Descriptor __set__(self, obj, value).'),
    (s_get_name_id, '__get__'),
    (s_get_doc_id, 'Descriptor __get__(self, obj).');
    INSERT INTO public.py_object (id, ob_type) VALUES (ID_DESCRIPTOR_SET, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_DESCRIPTOR_SET, s_set_name_id, 1, s_set_doc_id, NULL, NULL, 'py_builtin_descriptor_set'::regproc);
    INSERT INTO public.py_object (id, ob_type) VALUES (ID_DESCRIPTOR_GET, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_DESCRIPTOR_GET, s_get_name_id, 1, s_get_doc_id, NULL, NULL, 'py_builtin_descriptor_get'::regproc);
END $$;

-- ============================================================================
-- Bound Method: method type + tp_call + builtin_function_or_method __get__
-- Design: docs/BOUND_METHOD_DESIGN.md. No tp_name comparison.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_method_tp_call(method_obj_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    im_func_id UUID;
    im_self_id UUID;
    new_args UUID[];
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_method_object WHERE ob_base = method_obj_id) THEN
        PERFORM public.py_err_set_type_error('method object expected');
        RETURN NULL;
    END IF;
    SELECT im_func, im_self INTO im_func_id, im_self_id
    FROM public.py_method_object
    WHERE ob_base = method_obj_id;
    IF im_self_id IS NULL THEN
        PERFORM public.py_err_set_type_error('unbound method called');
        RETURN NULL;
    END IF;
    new_args := array_prepend(im_self_id, COALESCE(args, ARRAY[]::uuid[]));
    RETURN public.py_object_call(im_func_id, new_args, kwargs_id);
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    ID_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000030';
    ID_TYPE_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    bases_tuple_id UUID;
    dict_method_id UUID;
BEGIN
    SELECT tp_bases INTO bases_tuple_id FROM public.py_type_object WHERE ob_base = ID_INT_TYPE LIMIT 1;
    IF bases_tuple_id IS NULL THEN
        RAISE EXCEPTION 'Bound method bootstrap: tp_bases (object,) not found';
    END IF;
    dict_method_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_method_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_method_id);
    INSERT INTO public.py_object (id, ob_type) VALUES (ID_METHOD_TYPE, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (ID_METHOD_TYPE, 'method', bases_tuple_id, dict_method_id);
    UPDATE public.py_type_object SET tp_call = 'py_method_tp_call'::regproc WHERE ob_base = ID_METHOD_TYPE;
END $$;

-- builtin_function_or_method __get__: (func, obj, type) -> func if obj IS NULL else bound method
CREATE OR REPLACE FUNCTION public.py_builtin_function_descriptor_get(func_obj_id UUID, args UUID[])
RETURNS UUID AS $$
DECLARE
    attr_id UUID;
    obj_id UUID;
    type_id UUID;
    method_type_id UUID := '00000000-0000-4000-a000-000000000030';
    new_id UUID;
BEGIN
    IF array_length(args, 1) < 3 THEN
        PERFORM public.py_err_set_type_error('function __get__ requires 3 arguments');
        RETURN NULL;
    END IF;
    attr_id := args[1];
    obj_id := args[2];
    type_id := args[3];
    IF obj_id IS NULL OR obj_id = type_id THEN
        RETURN attr_id;
    END IF;
    new_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (new_id, method_type_id);
    INSERT INTO public.py_method_object (ob_base, im_func, im_self, im_class)
    VALUES (new_id, attr_id, obj_id, type_id);
    RETURN new_id;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    ID_FUNCTION_DESCRIPTOR_GET UUID := '00000000-0000-4000-b000-000000000022';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    tp_dict_id UUID;
    fget_name_id UUID;
    fget_doc_id UUID;
    get_key_id UUID;
    h BIGINT;
BEGIN
    SELECT tp_dict INTO tp_dict_id FROM public.py_type_object WHERE ob_base = ID_BUILTIN_FUNCTION_OR_METHOD_TYPE LIMIT 1;
    IF tp_dict_id IS NULL THEN
        RAISE EXCEPTION 'Bound method: builtin_function_or_method tp_dict not found';
    END IF;
    fget_name_id := gen_random_uuid();
    fget_doc_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (fget_name_id, ID_STR_TYPE), (fget_doc_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES
    (fget_name_id, '__get__'),
    (fget_doc_id, 'Function descriptor __get__(self, obj, type).');
    INSERT INTO public.py_object (id, ob_type) VALUES (ID_FUNCTION_DESCRIPTOR_GET, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_FUNCTION_DESCRIPTOR_GET, fget_name_id, 1, fget_doc_id, NULL, NULL, 'py_builtin_function_descriptor_get'::regproc);
    get_key_id := public.py_str_from_text('__get__');
    h := public.py_object_hash(get_key_id);
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
    VALUES (tp_dict_id, get_key_id, ID_FUNCTION_DESCRIPTOR_GET, h);
END $$;
