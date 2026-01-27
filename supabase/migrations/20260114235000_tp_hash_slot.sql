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
--   1. Adds tp_hash field to py_type_object table
--   2. Implements py_object_hash() function (equivalent to PyObject_Hash)
--   3. Implements type-specific hash functions (str, int)
--   4. Registers tp_hash for hashable builtin types
--
-- ============================================================================

-- ============================================================================
-- Schema Modification: Add tp_hash Slot to PyTypeObject
-- ============================================================================

-- Add tp_hash field to py_type_object table
-- This field stores a PostgreSQL function identifier (regproc) that implements
-- the hash behavior for objects of this type. NULL means the type is unhashable.
--
-- In CPython:
--   hashfunc tp_hash;  // typedef Py_hash_t (*hashfunc)(PyObject *)
--   This is a function pointer that takes a PyObject* and returns Py_hash_t
--
-- In Elytra:
--   regproc tp_hash;  // PostgreSQL function identifier
--   The function signature is: func(obj_id UUID) RETURNS BIGINT
--   BIGINT corresponds to CPython's Py_hash_t (typically long/Py_ssize_t)
ALTER TABLE public.py_type_object
ADD COLUMN tp_hash regproc;

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
