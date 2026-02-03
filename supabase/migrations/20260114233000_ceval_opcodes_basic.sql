-- ============================================================================
-- Migration: VM Basic Opcode Support (CALL_FUNCTION helper)
-- Created: 2026-01-14 23:30:00
--
-- Purpose:
--   Support functions for CALL_FUNCTION / CALL_FUNCTION_KW. Opcode handlers
--   are in separate migrations (one opcode per file): 233001 LOAD_CONST,
--   233002 CALL_FUNCTION, 233003 CALL_FUNCTION_KW, 233004 BUILD_TUPLE, 233005 BUILD_LIST.
--
-- ============================================================================

-- ============================================================================
-- CALL_FUNCTION Opcode Support Functions
-- ============================================================================

-- py_call_cfunction: Call a C function (builtin function)
--
-- Parameters:
--   func_obj_id: UUID of the PyCFunction object
--   args: Array of argument object IDs (UUID[])
--
-- Returns:
--   UUID: The PyObject ID returned by the function
--
-- Behavior:
--   Calls a builtin C function based on its m_ml_meth and m_ml_flags.
--   Currently supports METH_O (single argument) calling convention.
--   This is equivalent to CPython's PyCFunction_Call().
--
--   In CPython:
--   - PyCFunction_Call checks m_ml_flags to determine calling convention
--   - METH_O (0x0008): Takes exactly one argument (PyObject*)
--   - METH_VARARGS (0x0001): Takes variable arguments (PyObject* args tuple)
--   - METH_NOARGS (0x0004): Takes no arguments
--
-- Usage:
--   result_id := py_call_cfunction(func_obj_id, ARRAY[arg1_id]);
--
-- CPython Reference:
--   This function implements the core logic of PyCFunction_Call in
--   Objects/methodobject.c. It dispatches to the appropriate calling convention
--   based on m_ml_flags.
--
-- py_call_cfunction: (func_obj_id, args, kwargs_id). METH_O/METH_NOARGS: kwargs_id IS NOT NULL => TypeError.
CREATE OR REPLACE FUNCTION public.py_call_cfunction(
    func_obj_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ml_meth regproc;
    ml_flags INTEGER;
    result_id UUID;
    arg_count INTEGER;
    func_name TEXT;
    ml_name_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_cfunction_object WHERE ob_base = func_obj_id) THEN
        RAISE EXCEPTION 'py_call_cfunction: Function object with id % does not exist', func_obj_id;
    END IF;

    SELECT m_ml_meth, m_ml_flags, m_ml_name INTO ml_meth, ml_flags, ml_name_id
    FROM public.py_cfunction_object
    WHERE ob_base = func_obj_id;

    IF ml_meth IS NULL THEN
        RAISE EXCEPTION 'py_call_cfunction: Function implementation (m_ml_meth) not found for function %', func_obj_id;
    END IF;

    SELECT str_value INTO func_name FROM public.py_unicode_object WHERE ob_base = ml_name_id;

    -- Reject kwargs for conventions that do not accept keyword arguments (METH_KEYWORDS = 2 does accept)
    IF kwargs_id IS NOT NULL THEN
        IF (ml_flags & 2) = 0 AND ((ml_flags & 8) != 0 OR (ml_flags & 4) != 0 OR (ml_flags & 1) != 0) THEN
            -- CPython: "len() takes no keyword arguments" — Python 예외로 보고, NULL 반환
            PERFORM public.py_err_set_type_error(COALESCE(func_name, 'builtin') || '() takes no keyword arguments');
            RETURN NULL;
        END IF;
    END IF;

    arg_count := COALESCE(array_length(args, 1), 0);

    IF (ml_flags & 8) != 0 THEN  -- METH_O
        IF arg_count != 1 THEN
            -- CPython: "len() takes 1 positional argument but N were given" — Python 예외로 보고, NULL 반환
            PERFORM public.py_err_set_type_error(COALESCE(func_name, 'builtin') || '() takes 1 positional argument but ' || COALESCE(arg_count, 0)::text || ' were given');
            RETURN NULL;
        END IF;
        EXECUTE format('SELECT %I($1)', ml_meth::text) USING args[1] INTO result_id;

    ELSIF (ml_flags & 4) != 0 THEN  -- METH_NOARGS
        IF arg_count != 0 THEN
            PERFORM public.py_err_set_type_error(COALESCE(func_name, 'builtin') || '() takes 0 positional arguments but ' || arg_count::text || ' were given');
            RETURN NULL;
        END IF;
        EXECUTE format('SELECT %I()', ml_meth::text) INTO result_id;

    ELSIF (ml_flags & 2) != 0 THEN  -- METH_KEYWORDS: (func_obj_id, args, kwargs_id) RETURNS UUID
        EXECUTE format('SELECT %I($1, $2, $3)', ml_meth::text) USING func_obj_id, args, kwargs_id INTO result_id;

    ELSIF (ml_flags & 1) != 0 THEN  -- METH_VARARGS: (func_obj_id, args) → result
        EXECUTE format('SELECT %I($1, $2)', ml_meth::text) USING func_obj_id, args INTO result_id;

    ELSE
        RAISE EXCEPTION 'py_call_cfunction: Unsupported calling convention (m_ml_flags=%)', ml_flags;
    END IF;

    RETURN result_id;
END;
$$ LANGUAGE plpgsql;
