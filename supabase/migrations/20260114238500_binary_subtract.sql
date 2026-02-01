-- ============================================================================
-- Migration: BINARY_SUBTRACT (nb_subtract, PyNumber_Subtract, opcode 24)
-- Created: 2026-01-14 23:85:00
--
-- Purpose:
--   BINARY_SUBTRACT: py_long_nb_subtract, py_object_subtract_via_nb, slot registration,
--   py_object_subtract (PyNumber_Subtract), py_opcode_BINARY_SUBTRACT (opcode 24).
--   nb_subtract column is in 20260114220000_python_object_schema.sql.
--
-- CPython: PyNumber_Subtract → nb_subtract (binaryfunc) only. No sq_* fallback.
-- Design: docs/BINARY_SUBTRACT_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- Singleton (bootstrap 20260114223000)
-- NotImplemented: 00000000-0000-4000-b000-000000000012

-- nb_subtract column is defined in 20260114220000_python_object_schema.sql.

-- ============================================================================
-- C: py_long_nb_subtract(left_id, right_id) — int - int
--    binaryfunc (PyObject *a, PyObject *b) -> PyObject*
--    left/right 모두 py_long_object일 때만 뺄셈, 새 int 객체 id 반환. 그 외 NotImplemented.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_subtract(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv numeric;
    rv numeric;
    id_int_type uuid := '00000000-0000-4000-a000-000000000004';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = left_id) THEN
        RETURN id_not_implemented;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = right_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT long_value INTO lv FROM public.py_long_object WHERE ob_base = left_id;
    SELECT long_value INTO rv FROM public.py_long_object WHERE ob_base = right_id;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, lv - rv);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_float_nb_subtract(left_id, right_id) — float - float, float - int (CPython coercion)
--    left는 py_float_object. right가 float 또는 int(변환 후 뺄셈). 그 외 NotImplemented.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_float_nb_subtract(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv double precision;
    rv double precision;
    rv_long numeric;
    id_float_type uuid := '00000000-0000-4000-a000-000000000009';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = left_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT ob_fval INTO lv FROM public.py_float_object WHERE ob_base = left_id;
    IF EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = right_id) THEN
        SELECT ob_fval INTO rv FROM public.py_float_object WHERE ob_base = right_id;
    ELSIF EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = right_id) THEN
        SELECT long_value INTO rv_long FROM public.py_long_object WHERE ob_base = right_id;
        rv := rv_long::double precision;
    ELSE
        RETURN id_not_implemented;
    END IF;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_float_type);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (result_id, lv - rv);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Dispatch: py_object_subtract_via_nb; slot registration
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_subtract_via_nb(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    left_type_id uuid;
    right_type_id uuid;
    num_id uuid;
    nb_subtract_slot regproc;
    res uuid;
    call_nspname text;
    call_proname text;
BEGIN
    SELECT ob_type INTO left_type_id FROM public.py_object WHERE id = left_id;
    IF left_type_id IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = left_type_id;
    IF num_id IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    SELECT nb_subtract INTO nb_subtract_slot FROM public.py_number_methods WHERE id = num_id;
    IF nb_subtract_slot IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.oid = nb_subtract_slot::oid;

    IF call_nspname IS NOT NULL AND call_proname IS NOT NULL THEN
        EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING left_id, right_id INTO res;
        IF res IS NOT NULL AND res <> id_not_implemented THEN
            RETURN res;
        END IF;
    END IF;

    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    IF right_type_id IS NULL OR right_type_id = left_type_id THEN
        RETURN id_not_implemented;
    END IF;

    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = right_type_id;
    IF num_id IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    SELECT nb_subtract INTO nb_subtract_slot FROM public.py_number_methods WHERE id = num_id;
    IF nb_subtract_slot IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.oid = nb_subtract_slot::oid;

    IF call_nspname IS NULL OR call_proname IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    id_int uuid := '00000000-0000-4000-a000-000000000004';
    id_float uuid := '00000000-0000-4000-a000-000000000009';
BEGIN
    UPDATE public.py_number_methods
    SET nb_subtract = 'py_long_nb_subtract'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_int);

    UPDATE public.py_number_methods
    SET nb_subtract = 'py_float_nb_subtract'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_float);
END $$;

-- ============================================================================
-- py_object_subtract (PyNumber_Subtract): nb_subtract only, else TypeError
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_subtract(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    left_type_id uuid;
    right_type_id uuid;
    left_tp_name text;
    right_tp_name text;
BEGIN
    res := public.py_object_subtract_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN
        RETURN res;
    END IF;

    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    PERFORM public.py_err_set_type_error('unsupported operand type(s) for -: ''' || COALESCE(left_tp_name, 'None') || ''' and ''' || COALESCE(right_tp_name, 'None') || '''');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_opcode_BINARY_SUBTRACT (opcode 24): pop right, left → py_object_subtract(left, right) → push
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_BINARY_SUBTRACT(frame_id uuid)
RETURNS void AS $$
DECLARE
    right_id uuid;
    left_id  uuid;
    result_id uuid;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;

    right_id := public.py_stack_pop(frame_id);
    left_id  := public.py_stack_pop(frame_id);
    result_id := public.py_object_subtract(left_id, right_id);
    IF result_id IS NULL AND public.py_err_occurred() THEN
        RETURN;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
