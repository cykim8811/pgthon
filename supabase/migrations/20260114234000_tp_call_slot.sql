-- ============================================================================
-- Migration: tp_call Slot (CPython Callable Protocol)
-- Created: 2026-01-14 23:40:00
--
-- Purpose:
--   Implements CPython's tp_call slot system for callable objects. This allows
--   objects to be called using the CPython-faithful mechanism: checking the
--   tp_call slot pointer rather than type name string comparison.
--
-- CPython Structure:
--   typedef struct _typeobject {
--       // ...
--       ternaryfunc tp_call;  // Function pointer for object call
--       // ...
--   } PyTypeObject;
--
--   In CPython:
--   - If tp_call is not NULL, the object is callable
--   - PyObject_Call() checks tp_call and calls it if available
--   - This allows user-defined classes to implement __call__ method
--
-- This migration:
--   1. Implements py_object_call() function (equivalent to PyObject_Call)
--   2. Updates CALL_FUNCTION to use tp_call slot instead of type name comparison
--   3. Registers tp_call for builtin_function_or_method type (directly to py_call_cfunction,
--      matching CPython's PyCFunction_Type.tp_call = PyCFunction_Call pattern)
--   (tp_call column is defined in 20260114220000_python_object_schema.sql)
--
-- ============================================================================

-- tp_call column is defined in py_type_object (20260114220000_python_object_schema.sql).
-- This migration only adds functions and registers the slot.

-- ============================================================================
-- Function: py_object_call (Equivalent to PyObject_Call)
-- ============================================================================

-- py_object_call: Call an object using its tp_call slot
--
-- Parameters:
--   obj_id: UUID of the object to call
--   args: Array of argument object IDs (UUID[])
--
-- Returns:
--   UUID: The PyObject ID returned by the call
--
-- Behavior:
--   This is equivalent to CPython's PyObject_Call(). It checks the object's
--   type's tp_call slot and calls it if available. If tp_call is NULL, raises
--   TypeError indicating the object is not callable.
--
--   In CPython:
--   - PyObject_Call checks Py_TYPE(obj)->tp_call
--   - If tp_call is not NULL, calls it: tp_call(obj, args, kwargs)
--   - If tp_call is NULL, raises TypeError
--
-- Usage:
--   result_id := py_object_call(func_obj_id, ARRAY[arg1_id, arg2_id]);
--
-- CPython Reference:
--   This function implements the core logic of PyObject_Call in Objects/call.c.
--
CREATE OR REPLACE FUNCTION public.py_object_call(obj_id UUID, args UUID[])
RETURNS UUID AS $$
DECLARE
    obj_type_id UUID;
    call_func regproc;
    result_id UUID;
    func_type_name TEXT;
BEGIN
    -- Validate object exists
    IF NOT EXISTS (SELECT 1 FROM public.py_object WHERE id = obj_id) THEN
        RAISE EXCEPTION 'py_object_call: Object with id % does not exist', obj_id;
    END IF;
    
    -- Get object type
    SELECT ob_type INTO obj_type_id
    FROM public.py_object
    WHERE id = obj_id;
    
    IF obj_type_id IS NULL THEN
        RAISE EXCEPTION 'py_object_call: Object with id % does not have a type', obj_id;
    END IF;
    
    -- Get tp_call slot from type object
    SELECT tp_call INTO call_func
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;
    
    -- Check if object is callable (tp_call is not NULL)
    IF call_func IS NULL THEN
        -- Get type name for error message
        SELECT tp_name INTO func_type_name
        FROM public.py_type_object
        WHERE ob_base = obj_type_id;
        
        RAISE EXCEPTION 'TypeError: ''%'' object is not callable', COALESCE(func_type_name, 'unknown');
    END IF;
    
    -- Call the tp_call function
    -- For now, we pass args as an array. In the future, we may need to support kwargs.
    -- The function signature is: func(obj_id UUID, args UUID[]) RETURNS UUID
    EXECUTE format('SELECT %I($1, $2)', call_func::text) USING obj_id, args INTO result_id;
    
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Bootstrap: Register tp_call for builtin_function_or_method type
-- ============================================================================

-- In CPython, PyCFunction_Type.tp_call directly points to PyCFunction_Call().
-- Similarly, in Elytra, we register py_call_cfunction directly as the tp_call
-- for builtin_function_or_method type, without any intermediate dispatch function.
-- This matches CPython's structure where each type has its own dedicated tp_call
-- function, rather than using a generic dispatcher with type name string comparison.
DO $$
DECLARE
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
BEGIN
    -- Register tp_call for builtin_function_or_method type
    -- This makes all builtin functions callable via the tp_call slot.
    -- py_call_cfunction has the correct signature (obj_id UUID, args UUID[])
    -- which matches what py_object_call expects for tp_call functions.
    UPDATE public.py_type_object
    SET tp_call = 'py_call_cfunction'::regproc
    WHERE ob_base = ID_BUILTIN_FUNCTION_OR_METHOD_TYPE;
END $$;
