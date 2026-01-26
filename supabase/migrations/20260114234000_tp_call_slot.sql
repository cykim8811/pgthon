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
--   1. Adds tp_call field to py_type_object table
--   2. Implements py_object_call() function (equivalent to PyObject_Call)
--   3. Updates CALL_FUNCTION to use tp_call slot instead of type name comparison
--   4. Registers tp_call for builtin_function_or_method type
--
-- ============================================================================

-- ============================================================================
-- Schema Modification: Add tp_call Slot to PyTypeObject
-- ============================================================================

-- Add tp_call field to py_type_object table
-- This field stores a PostgreSQL function identifier (regproc) that implements
-- the call behavior for objects of this type. NULL means the type is not callable.
--
-- In CPython:
--   ternaryfunc tp_call;  // typedef PyObject *(*ternaryfunc)(PyObject *, PyObject *, PyObject *)
--   This is a function pointer that takes (self, args, kwargs) and returns PyObject*
--
-- In Elytra:
--   regproc tp_call;  // PostgreSQL function identifier
--   The function signature is: func(obj_id UUID, args UUID[], kwargs UUID) RETURNS UUID
--   For now, we only support positional arguments (args array), kwargs can be added later
ALTER TABLE public.py_type_object
ADD COLUMN tp_call regproc;

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
-- Function: py_callable_tp_call (Generic tp_call implementation for builtin functions)
-- ============================================================================

-- py_callable_tp_call: Generic tp_call implementation for callable types
--
-- Parameters:
--   obj_id: UUID of the object being called (the function object)
--   args: Array of argument object IDs (UUID[])
--
-- Returns:
--   UUID: The PyObject ID returned by the function call
--
-- Behavior:
--   This is a generic tp_call implementation that dispatches to the appropriate
--   calling mechanism based on the object's type. For builtin_function_or_method,
--   it calls py_call_cfunction. For other types, it can be extended.
--
--   In CPython:
--   - PyCFunction_Type.tp_call calls PyCFunction_Call()
--   - PyFunction_Type.tp_call creates a new frame and executes it
--
-- Usage:
--   This function is registered as tp_call for builtin_function_or_method type.
--
CREATE OR REPLACE FUNCTION public.py_callable_tp_call(obj_id UUID, args UUID[])
RETURNS UUID AS $$
DECLARE
    obj_type_id UUID;
    func_type_name TEXT;
    result_id UUID;
BEGIN
    -- Get object type
    SELECT ob_type INTO obj_type_id
    FROM public.py_object
    WHERE id = obj_id;
    
    SELECT tp_name INTO func_type_name
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;
    
    -- Dispatch based on function type
    IF func_type_name = 'builtin_function_or_method' THEN
        -- C function (builtin) call
        result_id := public.py_call_cfunction(obj_id, args);
        
    ELSIF func_type_name = 'function' THEN
        -- Python function call (not yet implemented)
        RAISE EXCEPTION 'py_callable_tp_call: Python function calls not yet implemented';
        
    ELSE
        -- This should not happen if tp_call is correctly registered
        RAISE EXCEPTION 'py_callable_tp_call: Unsupported callable type: %', func_type_name;
    END IF;
    
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Bootstrap: Register tp_call for builtin_function_or_method type
-- ============================================================================

DO $$
DECLARE
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
BEGIN
    -- Register tp_call for builtin_function_or_method type
    -- This makes all builtin functions callable via the tp_call slot
    UPDATE public.py_type_object
    SET tp_call = 'py_callable_tp_call'::regproc
    WHERE ob_base = ID_BUILTIN_FUNCTION_OR_METHOD_TYPE;
END $$;
