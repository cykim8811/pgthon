-- ============================================================================
-- Migration: Builtin Functions Bootstrap
-- Created: 2026-01-14 22:50:00
--
-- Purpose:
--   Creates builtin C functions and registers them in the __builtins__ module.
--   This migration runs after the function object schema is defined, so it
--   can use py_cfunction_object table.
--
--   Each builtin function is a PyCFunction object with appropriate metadata:
--   - m_ml_name: Function name (string object)
--   - m_ml_flags: Function flags (METH_O, METH_VARARGS, etc.)
--   - m_ml_doc: Documentation string (string object)
--   - m_self: Self object (NULL for unbound functions)
--   - m_module: Module object (__builtins__ module)
--   - m_ml_meth: PostgreSQL function identifier (regproc) that implements this function
--
-- Builtin Functions Created:
--   - len: Returns the number of items in a container (METH_O)
--   - abs: Returns the absolute value of a number (METH_O)
--
-- Note: Function IDs use fixed UUIDs to ensure they can be referenced reliably
-- across the system. They represent the "global symbols" of CPython.
-- ============================================================================

-- ============================================================================
-- Builtin Function Implementations
-- ============================================================================

-- py_builtin_len: Implements CPython's builtin_len function
-- Returns the number of items in a container (str, list, tuple, dict, etc.)
-- This is equivalent to CPython's builtin_len() in Python/bltinmodule.c
--
-- CPython Implementation:
--   static PyObject *builtin_len(PyObject *module, PyObject *obj) {
--       Py_ssize_t res = PyObject_Size(obj);
--       if (res < 0) return NULL;
--       return PyLong_FromSsize_t(res);
--   }
--
-- This function follows the same pattern: call PyObject_Size() and convert
-- the result to a Python int object.
CREATE OR REPLACE FUNCTION public.py_builtin_len(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    length_value NUMERIC;
    result_id UUID;
    -- Builtin type ID for int (from bootstrap)
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
BEGIN
    -- Call PyObject_Size() to get the length
    -- This function checks method slots (tp_as_sequence->sq_length or
    -- tp_as_mapping->mp_length) and calls the appropriate type-specific function.
    length_value := public.py_object_size(obj_id);
    IF length_value IS NULL AND public.py_err_occurred() THEN
        RETURN NULL;
    END IF;

    -- Create result int object
    -- Generate new UUID for result
    result_id := gen_random_uuid();
    
    -- Create PyObject entry
    INSERT INTO public.py_object (id, ob_type)
    VALUES (result_id, ID_INT_TYPE);
    
    -- Create PyLongObject entry
    INSERT INTO public.py_long_object (ob_base, long_value)
    VALUES (result_id, length_value);
    
    RETURN result_id;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Re-raise with context (PyObject_Size already sets appropriate error messages)
        RAISE;
END;
$$ LANGUAGE plpgsql;

-- py_builtin_abs: CPython builtin_abs → PyNumber_Absolute. Dispatches via py_object_absolute (defined in 235500).
CREATE OR REPLACE FUNCTION public.py_builtin_abs(obj_id UUID)
RETURNS UUID AS $$
BEGIN
    RETURN public.py_object_absolute(obj_id);
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$ LANGUAGE plpgsql;

-- py_builtin_first_kwarg: METH_KEYWORDS builtin for testing keyword argument dispatch.
-- Returns the first value from the kwargs dict (any entry), or None if empty.
-- Signature (func_obj_id UUID, args UUID[], kwargs_id UUID) for tp_call 3-arg convention.
CREATE OR REPLACE FUNCTION public.py_builtin_first_kwarg(
    func_obj_id UUID, args UUID[], kwargs_id UUID)
RETURNS UUID AS $$
DECLARE
    result_id UUID;
    ID_NONE_OBJ UUID := '00000000-0000-4000-b000-000000000001';
BEGIN
    IF kwargs_id IS NULL THEN
        RETURN ID_NONE_OBJ;
    END IF;
    SELECT me_value INTO result_id
    FROM public.py_dict_entry
    WHERE dict_id = kwargs_id
    LIMIT 1;
    RETURN COALESCE(result_id, ID_NONE_OBJ);
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    -- Builtin Function IDs (fixed UUIDs)
    ID_LEN_FUNCTION UUID := '00000000-0000-4000-b000-000000000003';
    ID_ABS_FUNCTION UUID := '00000000-0000-4000-b000-000000000004';
    ID_FIRST_KWARG_FUNCTION UUID := '00000000-0000-4000-b000-000000000005';
    
    -- String objects for function names and docstrings
    ID_STR_LEN_NAME UUID := gen_random_uuid();
    ID_STR_LEN_DOC UUID := gen_random_uuid();
    ID_STR_ABS_NAME UUID := gen_random_uuid();
    ID_STR_ABS_DOC UUID := gen_random_uuid();
    ID_STR_FIRST_KWARG_NAME UUID := gen_random_uuid();
    ID_STR_FIRST_KWARG_DOC UUID := gen_random_uuid();
    
    -- Reference to __builtins__ module (from bootstrap)
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    
    -- Get __builtins__ module dict
    builtins_dict_id UUID;
BEGIN
    -- Get __builtins__ module dict
    SELECT md_dict INTO builtins_dict_id
    FROM public.py_module_object
    WHERE ob_base = ID_BUILTINS_MODULE;
    
    IF builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ module dict not found. Bootstrap migration must run first.';
    END IF;

    -------------------------------------------------------
    -- Phase 1: Create string objects for function metadata
    -------------------------------------------------------
    -- Create PyObject entries for string objects
    INSERT INTO public.py_object (id, ob_type) VALUES
    (ID_STR_LEN_NAME, ID_STR_TYPE),
    (ID_STR_LEN_DOC, ID_STR_TYPE),
    (ID_STR_ABS_NAME, ID_STR_TYPE),
    (ID_STR_ABS_DOC, ID_STR_TYPE),
    (ID_STR_FIRST_KWARG_NAME, ID_STR_TYPE),
    (ID_STR_FIRST_KWARG_DOC, ID_STR_TYPE);
    
    -- Create string objects
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES
    (ID_STR_LEN_NAME, 'len'),
    (ID_STR_LEN_DOC, 'Return the number of items in a container.'),
    (ID_STR_ABS_NAME, 'abs'),
    (ID_STR_ABS_DOC, 'Return the absolute value of a number.'),
    (ID_STR_FIRST_KWARG_NAME, 'first_kwarg'),
    (ID_STR_FIRST_KWARG_DOC, 'Return the first value from kwargs (METH_KEYWORDS test).');

    -------------------------------------------------------
    -- Phase 2: Create len builtin function
    -------------------------------------------------------
    -- Create PyObject entry for len function
    INSERT INTO public.py_object (id, ob_type)
    VALUES (ID_LEN_FUNCTION, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    
    -- Create len builtin function
    -- py_cfunction_object implements CPython's PyCFunction
    -- METH_O = 0x0008 (8) - takes exactly one argument (other than self)
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (
        ID_LEN_FUNCTION,
        ID_STR_LEN_NAME,           -- m_ml_name: "len"
        8,                          -- m_ml_flags: METH_O (takes one argument)
        ID_STR_LEN_DOC,             -- m_ml_doc: "Return the number of items in a container."
        NULL,                       -- m_self: NULL (unbound function)
        ID_BUILTINS_MODULE,         -- m_module: __builtins__ module
        'py_builtin_len'::regproc   -- m_ml_meth: PostgreSQL function identifier (validates function exists)
    );
    
    -------------------------------------------------------
    -- Phase 3: Create abs builtin function
    -------------------------------------------------------
    -- Create PyObject entry for abs function
    INSERT INTO public.py_object (id, ob_type)
    VALUES (ID_ABS_FUNCTION, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    
    -- Create abs builtin function
    -- py_cfunction_object implements CPython's PyCFunction
    -- METH_O = 0x0008 (8) - takes exactly one argument (other than self)
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (
        ID_ABS_FUNCTION,
        ID_STR_ABS_NAME,           -- m_ml_name: "abs"
        8,                          -- m_ml_flags: METH_O (takes one argument)
        ID_STR_ABS_DOC,             -- m_ml_doc: "Return the absolute value of a number."
        NULL,                       -- m_self: NULL (unbound function)
        ID_BUILTINS_MODULE,         -- m_module: __builtins__ module
        'py_builtin_abs'::regproc   -- m_ml_meth: PostgreSQL function identifier (validates function exists)
    );

    -------------------------------------------------------
    -- Phase 3b: Create first_kwarg builtin (METH_KEYWORDS)
    -------------------------------------------------------
    INSERT INTO public.py_object (id, ob_type)
    VALUES (ID_FIRST_KWARG_FUNCTION, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);

    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (
        ID_FIRST_KWARG_FUNCTION,
        ID_STR_FIRST_KWARG_NAME,   -- m_ml_name: "first_kwarg"
        2,                          -- m_ml_flags: METH_KEYWORDS (accepts kwargs)
        ID_STR_FIRST_KWARG_DOC,     -- m_ml_doc
        NULL,
        ID_BUILTINS_MODULE,
        'py_builtin_first_kwarg'::regproc  -- (func_obj_id, args, kwargs_id) RETURNS UUID
    );
    
    -------------------------------------------------------
    -- Phase 4: Register builtin functions in __builtins__ module's __dict__
    -------------------------------------------------------
    -- In CPython, builtin functions are stored in the module's __dict__ with their name as the key.
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value) VALUES
    (builtins_dict_id, ID_STR_LEN_NAME, ID_LEN_FUNCTION),
    (builtins_dict_id, ID_STR_ABS_NAME, ID_ABS_FUNCTION),
    (builtins_dict_id, ID_STR_FIRST_KWARG_NAME, ID_FIRST_KWARG_FUNCTION);

END $$;
