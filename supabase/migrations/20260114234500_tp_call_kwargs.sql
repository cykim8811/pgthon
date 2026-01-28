-- ============================================================================
-- Migration: tp_call kwargs (CPython ternaryfunc tp_call(obj, args, kwargs))
-- Created: 2026-01-14 23:45:00
--
-- Purpose:
--   Aligns tp_call with CPython: ternaryfunc receives (obj, args, kwargs).
--   All tp_call targets use (obj_id UUID, args UUID[], kwargs_id UUID).
--   kwargs_id NULL = no keyword arguments.
--
-- This migration (design: docs/TP_CALL_KWARGS_DESIGN.md, plan: docs/CHANGE_3_TP_CALL_KWARGS_PLAN.md):
--   1. py_call_cfunction: add kwargs_id, reject kwargs for METH_O/METH_NOARGS
--   2. py_object_call: add kwargs_id, invoke tp_call with 3 args
--   3. py_opcode_CALL_FUNCTION: call py_object_call(..., NULL)
-- ============================================================================

-- ============================================================================
-- 1. py_call_cfunction: (func_obj_id, args, kwargs_id DEFAULT NULL)
--    METH_O / METH_NOARGS: kwargs_id IS NOT NULL => TypeError "name() takes no keyword arguments"
-- ============================================================================

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

    -- CPython: pass keyword args only to METH_KEYWORDS; else TypeError
    IF kwargs_id IS NOT NULL THEN
        IF (ml_flags & 8) != 0 OR (ml_flags & 4) != 0 OR (ml_flags & 1) != 0 THEN
            -- METH_O, METH_NOARGS, or METH_VARARGS: no keyword args
            SELECT str_value INTO func_name
            FROM public.py_unicode_object
            WHERE ob_base = ml_name_id;
            RAISE EXCEPTION 'TypeError: ''%''() takes no keyword arguments', COALESCE(func_name, 'builtin');
        END IF;
    END IF;

    arg_count := COALESCE(array_length(args, 1), 0);

    IF (ml_flags & 8) != 0 THEN  -- METH_O
        IF arg_count != 1 THEN
            RAISE EXCEPTION 'py_call_cfunction: METH_O function expects 1 argument, got %', COALESCE(arg_count, 0);
        END IF;
        EXECUTE format('SELECT %I($1)', ml_meth::text) USING args[1] INTO result_id;

    ELSIF (ml_flags & 4) != 0 THEN  -- METH_NOARGS
        IF arg_count != 0 THEN
            RAISE EXCEPTION 'py_call_cfunction: METH_NOARGS function expects 0 arguments, got %', arg_count;
        END IF;
        EXECUTE format('SELECT %I()', ml_meth::text) INTO result_id;

    ELSIF (ml_flags & 1) != 0 THEN  -- METH_VARARGS
        RAISE EXCEPTION 'py_call_cfunction: METH_VARARGS calling convention not yet implemented';

    ELSE
        RAISE EXCEPTION 'py_call_cfunction: Unsupported calling convention (m_ml_flags=%)', ml_flags;
    END IF;

    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2. py_object_call: (obj_id, args, kwargs_id DEFAULT NULL), tp_call with 3 args
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_call(
    obj_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    obj_type_id UUID;
    call_func regproc;
    result_id UUID;
    func_type_name TEXT;
    call_nspname TEXT;
    call_proname TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_object WHERE id = obj_id) THEN
        RAISE EXCEPTION 'py_object_call: Object with id % does not exist', obj_id;
    END IF;

    SELECT ob_type INTO obj_type_id
    FROM public.py_object
    WHERE id = obj_id;

    IF obj_type_id IS NULL THEN
        RAISE EXCEPTION 'py_object_call: Object with id % does not have a type', obj_id;
    END IF;

    SELECT tp_call INTO call_func
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;

    IF call_func IS NULL THEN
        SELECT tp_name INTO func_type_name
        FROM public.py_type_object
        WHERE ob_base = obj_type_id;
        RAISE EXCEPTION 'TypeError: ''%'' object is not callable', COALESCE(func_type_name, 'unknown');
    END IF;

    -- Resolve regproc to schema+name so the dynamic call is "schema.func(...)", not "\"schema.func\"(...)".
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.oid = call_func::oid;

    IF call_nspname IS NULL OR call_proname IS NULL THEN
        RAISE EXCEPTION 'py_object_call: tp_call regproc % does not resolve to a function', call_func;
    END IF;

    -- tp_call convention: (obj_id UUID, args UUID[], kwargs_id UUID) RETURNS UUID
    EXECUTE format('SELECT %I.%I($1, $2, $3)', call_nspname, call_proname)
    USING obj_id, args, COALESCE(kwargs_id, NULL) INTO result_id;

    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. py_opcode_CALL_FUNCTION: pass NULL for kwargs
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_CALL_FUNCTION(frame_id UUID, arg_count INTEGER)
RETURNS VOID AS $$
DECLARE
    func_obj_id UUID;
    args UUID[];
    i INTEGER;
    result_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF arg_count < 0 THEN
        RAISE EXCEPTION 'CALL_FUNCTION: arg_count must be non-negative, got %', arg_count;
    END IF;

    args := array[]::UUID[];
    FOR i IN 1..arg_count LOOP
        args := array_prepend(public.py_stack_pop(frame_id), args);
    END LOOP;
    func_obj_id := public.py_stack_pop(frame_id);

    result_id := public.py_object_call(func_obj_id, args, NULL);

    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
