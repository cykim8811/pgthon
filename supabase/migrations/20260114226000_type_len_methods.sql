-- ============================================================================
-- Migration: Type __len__ Methods via tp_dict
-- Created: 2026-01-14 22:60:00
--
-- Purpose:
--   Implements len() functionality using tp_dict instead of method slots.
--   This is a minimal implementation that registers __len__ methods in each
--   type's tp_dict, following the same pattern as user-defined types.
--
--   This migration:
--   1. Implements type-specific length calculation functions
--   2. Implements PyObject_Size() helper that looks up __len__ in tp_dict
--   3. Registers __len__ methods in builtin type tp_dicts
--
-- Design Decision:
--   Using tp_dict instead of method slots for minimal implementation.
--   CPython uses method slots for builtin types, but tp_dict works for
--   both builtin and user-defined types, reducing implementation complexity.
--
-- ============================================================================

-- ============================================================================
-- Type-Specific Length Calculation Functions
-- ============================================================================

-- py_unicode_sq_length: Calculate length of a string object
-- Implements CPython's PyUnicode_GET_LENGTH() behavior
CREATE OR REPLACE FUNCTION public.py_unicode_sq_length(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    length_value NUMERIC;
BEGIN
    -- Validate object exists and is a string
    IF NOT EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = obj_id) THEN
        RAISE EXCEPTION 'TypeError: py_unicode_sq_length called on non-string object';
    END IF;
    
    -- Get string length
    SELECT char_length(str_value) INTO length_value
    FROM public.py_unicode_object
    WHERE ob_base = obj_id;
    
    IF length_value IS NULL THEN
        RAISE EXCEPTION 'TypeError: object of type ''str'' has no len()';
    END IF;
    
    RETURN length_value;
END;
$$ LANGUAGE plpgsql;

-- py_list_sq_length: Calculate length of a list object
-- Implements CPython's PyList_GET_SIZE() behavior
CREATE OR REPLACE FUNCTION public.py_list_sq_length(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    length_value NUMERIC;
BEGIN
    -- Validate object exists and is a list
    IF NOT EXISTS (SELECT 1 FROM public.py_list_object WHERE ob_base = obj_id) THEN
        RAISE EXCEPTION 'TypeError: py_list_sq_length called on non-list object';
    END IF;
    
    -- Get list length (array_length returns NULL for empty arrays)
    SELECT array_length(ob_item, 1) INTO length_value
    FROM public.py_list_object
    WHERE ob_base = obj_id;
    
    -- PostgreSQL's array_length returns NULL for empty arrays, but length is 0
    IF length_value IS NULL THEN
        length_value := 0;
    END IF;
    
    RETURN length_value;
END;
$$ LANGUAGE plpgsql;

-- py_tuple_sq_length: Calculate length of a tuple object
-- Implements CPython's PyTuple_GET_SIZE() behavior
CREATE OR REPLACE FUNCTION public.py_tuple_sq_length(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    length_value NUMERIC;
BEGIN
    -- Validate object exists and is a tuple
    IF NOT EXISTS (SELECT 1 FROM public.py_tuple_object WHERE ob_base = obj_id) THEN
        RAISE EXCEPTION 'TypeError: py_tuple_sq_length called on non-tuple object';
    END IF;
    
    -- Get tuple length (array_length returns NULL for empty arrays)
    SELECT array_length(ob_item, 1) INTO length_value
    FROM public.py_tuple_object
    WHERE ob_base = obj_id;
    
    -- PostgreSQL's array_length returns NULL for empty arrays, but length is 0
    IF length_value IS NULL THEN
        length_value := 0;
    END IF;
    
    RETURN length_value;
END;
$$ LANGUAGE plpgsql;

-- py_dict_mp_length: Calculate length of a dict object
-- Implements CPython's PyDict_GET_SIZE() behavior
CREATE OR REPLACE FUNCTION public.py_dict_mp_length(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    length_value NUMERIC;
BEGIN
    -- Validate object exists and is a dict
    IF NOT EXISTS (SELECT 1 FROM public.py_dict_object WHERE ob_base = obj_id) THEN
        RAISE EXCEPTION 'TypeError: py_dict_mp_length called on non-dict object';
    END IF;
    
    -- Count dictionary entries
    SELECT COUNT(*) INTO length_value
    FROM public.py_dict_entry
    WHERE dict_id = obj_id;
    
    RETURN length_value;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PyObject_Size Helper Function
-- ============================================================================

-- py_object_size: Get the size/length of a Python object
-- Implements CPython's PyObject_Size() function
--
-- Behavior:
--   Looks up __len__ method in the object's type's tp_dict and calls it.
--   This works for both builtin types (via registered __len__) and
--   user-defined types (via their own __len__ methods).
--
-- Note: CPython uses method slots for builtin types, but we use tp_dict
-- for minimal implementation that works uniformly for all types.
CREATE OR REPLACE FUNCTION public.py_object_size(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    obj_type_id UUID;
    tp_dict_id UUID;
    len_name_str_id UUID;
    len_method_id UUID;
    len_method_func regproc;
    length_value NUMERIC;
    type_name TEXT;
BEGIN
    -- Get object type
    SELECT ob_type INTO obj_type_id
    FROM public.py_object
    WHERE id = obj_id;
    
    IF obj_type_id IS NULL THEN
        RAISE EXCEPTION 'TypeError: object of type ''NoneType'' has no len()';
    END IF;
    
    -- Get tp_dict from type object
    SELECT tp_dict INTO tp_dict_id
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;
    
    IF tp_dict_id IS NULL THEN
        -- Get type name for error message
        SELECT tp_name INTO type_name
        FROM public.py_type_object
        WHERE ob_base = obj_type_id;
        
        IF type_name IS NULL THEN
            type_name := 'unknown';
        END IF;
        
        RAISE EXCEPTION 'TypeError: object of type ''%'' has no len()', type_name;
    END IF;
    
    -- Find "__len__" string object
    -- Note: This string is created during bootstrap, so it should exist
    SELECT ob_base INTO len_name_str_id
    FROM public.py_unicode_object
    WHERE str_value = '__len__'
    LIMIT 1;
    
    IF len_name_str_id IS NULL THEN
        -- __len__ string doesn't exist - this shouldn't happen if bootstrap ran correctly
        RAISE EXCEPTION 'Internal error: "__len__" string object not found. Bootstrap may not have completed.';
    END IF;
    
    -- Find __len__ method in tp_dict
    SELECT me_value INTO len_method_id
    FROM public.py_dict_entry
    WHERE dict_id = tp_dict_id
    AND me_key = len_name_str_id;
    
    IF len_method_id IS NULL THEN
        -- __len__ not found in tp_dict
        -- Get type name for error message
        SELECT tp_name INTO type_name
        FROM public.py_type_object
        WHERE ob_base = obj_type_id;
        
        IF type_name IS NULL THEN
            type_name := 'unknown';
        END IF;
        
        RAISE EXCEPTION 'TypeError: object of type ''%'' has no len()', type_name;
    END IF;
    
    -- Check if it's a PyCFunction (builtin method)
    SELECT m_ml_meth INTO len_method_func
    FROM public.py_cfunction_object
    WHERE ob_base = len_method_id;
    
    IF len_method_func IS NOT NULL THEN
        -- Call the function dynamically
        EXECUTE format('SELECT %I($1)', len_method_func) USING obj_id INTO length_value;
        RETURN length_value;
    END IF;
    
    -- TODO: Handle PyFunctionObject (user-defined __len__ methods)
    -- For now, if it's not a PyCFunction, raise error
    RAISE EXCEPTION 'TypeError: __len__ method is not a builtin function (user-defined methods not yet supported)';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register __len__ Methods in Builtin Type tp_dicts
-- ============================================================================

DO $$
DECLARE
    -- Builtin type IDs (from bootstrap)
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    
    -- Type dict IDs (from bootstrap)
    ID_DICT_STR_TYPE UUID;
    ID_DICT_LIST_TYPE UUID;
    ID_DICT_DICT_TYPE UUID;
    ID_DICT_TUPLE_TYPE UUID;
    
    -- __len__ method function IDs
    ID_LEN_STR UUID := gen_random_uuid();
    ID_LEN_LIST UUID := gen_random_uuid();
    ID_LEN_TUPLE UUID := gen_random_uuid();
    ID_LEN_DICT UUID := gen_random_uuid();
    
    -- String objects
    ID_STR_LEN_NAME UUID := gen_random_uuid();
    ID_STR_LEN_DOC UUID := gen_random_uuid();
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
BEGIN
    -- Get type dict IDs
    SELECT tp_dict INTO ID_DICT_STR_TYPE FROM public.py_type_object WHERE ob_base = ID_STR_TYPE;
    SELECT tp_dict INTO ID_DICT_LIST_TYPE FROM public.py_type_object WHERE ob_base = ID_LIST_TYPE;
    SELECT tp_dict INTO ID_DICT_DICT_TYPE FROM public.py_type_object WHERE ob_base = ID_DICT_TYPE;
    SELECT tp_dict INTO ID_DICT_TUPLE_TYPE FROM public.py_type_object WHERE ob_base = ID_TUPLE_TYPE;
    
    -- Create "__len__" string object (shared by all types)
    INSERT INTO public.py_object (id, ob_type) VALUES (ID_STR_LEN_NAME, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (ID_STR_LEN_NAME, '__len__');
    
    -- Create docstring string object
    INSERT INTO public.py_object (id, ob_type) VALUES (ID_STR_LEN_DOC, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (ID_STR_LEN_DOC, 'Return the number of items.');
    
    -------------------------------------------------------
    -- Create __len__ methods for each type
    -------------------------------------------------------
    
    -- str.__len__
    INSERT INTO public.py_object (id, ob_type) VALUES (ID_LEN_STR, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_LEN_STR, ID_STR_LEN_NAME, 8, ID_STR_LEN_DOC, NULL, NULL, 'py_unicode_sq_length'::regproc);
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value)
    VALUES (ID_DICT_STR_TYPE, ID_STR_LEN_NAME, ID_LEN_STR);
    
    -- list.__len__
    INSERT INTO public.py_object (id, ob_type) VALUES (ID_LEN_LIST, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_LEN_LIST, ID_STR_LEN_NAME, 8, ID_STR_LEN_DOC, NULL, NULL, 'py_list_sq_length'::regproc);
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value)
    VALUES (ID_DICT_LIST_TYPE, ID_STR_LEN_NAME, ID_LEN_LIST);
    
    -- tuple.__len__
    INSERT INTO public.py_object (id, ob_type) VALUES (ID_LEN_TUPLE, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_LEN_TUPLE, ID_STR_LEN_NAME, 8, ID_STR_LEN_DOC, NULL, NULL, 'py_tuple_sq_length'::regproc);
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value)
    VALUES (ID_DICT_TUPLE_TYPE, ID_STR_LEN_NAME, ID_LEN_TUPLE);
    
    -- dict.__len__
    INSERT INTO public.py_object (id, ob_type) VALUES (ID_LEN_DICT, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_LEN_DICT, ID_STR_LEN_NAME, 8, ID_STR_LEN_DOC, NULL, NULL, 'py_dict_mp_length'::regproc);
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value)
    VALUES (ID_DICT_DICT_TYPE, ID_STR_LEN_NAME, ID_LEN_DICT);

END $$;
