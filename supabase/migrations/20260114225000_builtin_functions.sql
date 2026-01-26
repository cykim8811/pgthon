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

-- py_builtin_abs: Implements CPython's builtin_abs function
-- Returns the absolute value of a number (int or float)
-- This is equivalent to CPython's builtin_abs() in Python/bltinmodule.c
--
-- CPython Implementation:
--   static PyObject *builtin_abs(PyObject *module, PyObject *obj) {
--       return PyNumber_Absolute(obj);
--   }
--
-- This function follows the same pattern: check type and compute absolute value.
CREATE OR REPLACE FUNCTION public.py_builtin_abs(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    obj_type_id UUID;
    obj_type_name TEXT;
    result_id UUID;
    int_value NUMERIC;
    float_value DOUBLE PRECISION;
    abs_value NUMERIC;
    -- Builtin type IDs (from bootstrap)
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_FLOAT_TYPE UUID := '00000000-0000-4000-a000-000000000009';
BEGIN
    -- Get object type
    SELECT ob_type INTO obj_type_id
    FROM public.py_object
    WHERE id = obj_id;
    
    IF obj_type_id IS NULL THEN
        RAISE EXCEPTION 'TypeError: abs() argument must be a number, not NoneType';
    END IF;
    
    SELECT tp_name INTO obj_type_name
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;
    
    IF obj_type_name IS NULL THEN
        RAISE EXCEPTION 'TypeError: abs() argument must be a number';
    END IF;
    
    -- Dispatch based on type
    IF obj_type_name = 'int' THEN
        -- Get int value
        SELECT long_value INTO int_value
        FROM public.py_long_object
        WHERE ob_base = obj_id;
        
        IF int_value IS NULL THEN
            RAISE EXCEPTION 'TypeError: abs() argument must be a number';
        END IF;
        
        -- Compute absolute value
        abs_value := ABS(int_value);
        
        -- Create result int object
        result_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type)
        VALUES (result_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value)
        VALUES (result_id, abs_value);
        
    ELSIF obj_type_name = 'float' THEN
        -- Get float value
        SELECT ob_fval INTO float_value
        FROM public.py_float_object
        WHERE ob_base = obj_id;
        
        IF float_value IS NULL THEN
            RAISE EXCEPTION 'TypeError: abs() argument must be a number';
        END IF;
        
        -- Compute absolute value
        abs_value := ABS(float_value);
        
        -- Create result float object
        result_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type)
        VALUES (result_id, ID_FLOAT_TYPE);
        INSERT INTO public.py_float_object (ob_base, ob_fval)
        VALUES (result_id, abs_value);
        
    ELSE
        RAISE EXCEPTION 'TypeError: bad operand type for abs(): ''%''', obj_type_name;
    END IF;
    
    RETURN result_id;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Re-raise with context
        RAISE;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    -- Builtin Function IDs (fixed UUIDs)
    ID_LEN_FUNCTION UUID := '00000000-0000-4000-b000-000000000003';
    ID_ABS_FUNCTION UUID := '00000000-0000-4000-b000-000000000004';
    
    -- String objects for function names and docstrings
    ID_STR_LEN_NAME UUID := gen_random_uuid();
    ID_STR_LEN_DOC UUID := gen_random_uuid();
    ID_STR_ABS_NAME UUID := gen_random_uuid();
    ID_STR_ABS_DOC UUID := gen_random_uuid();
    
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
    (ID_STR_ABS_DOC, ID_STR_TYPE);
    
    -- Create string objects
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES
    (ID_STR_LEN_NAME, 'len'),
    (ID_STR_LEN_DOC, 'Return the number of items in a container.'),
    (ID_STR_ABS_NAME, 'abs'),
    (ID_STR_ABS_DOC, 'Return the absolute value of a number.');

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
    -- Phase 4: Register builtin functions in __builtins__ module's __dict__
    -------------------------------------------------------
    -- In CPython, builtin functions are stored in the module's __dict__ with their name as the key.
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value) VALUES
    (builtins_dict_id, ID_STR_LEN_NAME, ID_LEN_FUNCTION),
    (builtins_dict_id, ID_STR_ABS_NAME, ID_ABS_FUNCTION);

END $$;
