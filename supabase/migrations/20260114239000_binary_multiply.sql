-- ============================================================================
-- Migration: BINARY_MULTIPLY (nb_multiply, sq_repeat, PyNumber_Multiply, opcode 20)
-- Created: 2026-01-14 23:90:00
--
-- Purpose:
--   BINARY_MULTIPLY: py_long_nb_multiply, py_unicode_sq_repeat, dispatch (py_object_multiply_via_nb,
--   py_sequence_repeat), slot registration, py_object_multiply (PyNumber_Multiply),
--   py_opcode_BINARY_MULTIPLY (opcode 20).
--   nb_multiply, sq_repeat columns are in 20260114220000_python_object_schema.sql.
--
-- CPython: PyNumber_Multiply → nb_multiply, fallback left/right sq_repeat(seq, n).
-- Design: docs/BINARY_MULTIPLY_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- NotImplemented singleton (bootstrap)
-- 00000000-0000-4000-b000-000000000012

-- nb_multiply, sq_repeat columns are defined in 20260114220000_python_object_schema.sql.

-- ============================================================================
-- C: py_long_nb_multiply(left_id, right_id) — int * int
--    binaryfunc. left/right 모두 py_long_object일 때만 곱셈, 그 외 NotImplemented.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_multiply(left_id uuid, right_id uuid)
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
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, lv * rv);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- E: py_unicode_sq_repeat(seq_id uuid, n integer) — str * n (sq_repeat: ssizeargfunc)
--    seq가 str일 때만 반복. n < 0이면 빈 문자열 반환 (CPython str 동작).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_unicode_sq_repeat(seq_id uuid, n integer)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    s text;
    repeated text;
    id_str_type uuid := '00000000-0000-4000-a000-000000000003';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = seq_id) THEN
        RAISE EXCEPTION 'TypeError: py_unicode_sq_repeat operand is not str';
    END IF;
    SELECT COALESCE(str_value, '') INTO s FROM public.py_unicode_object WHERE ob_base = seq_id;
    IF n <= 0 THEN
        repeated := '';
    ELSE
        repeated := repeat(s, n);
    END IF;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_str_type);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (result_id, repeated);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Dispatch: py_object_multiply_via_nb, py_sequence_repeat; slot registration
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_multiply_via_nb(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    left_type_id uuid;
    right_type_id uuid;
    num_id uuid;
    nb_slot regproc;
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

    SELECT nb_multiply INTO nb_slot FROM public.py_number_methods WHERE id = num_id;
    IF nb_slot IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.oid = nb_slot::oid;

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

    SELECT nb_multiply INTO nb_slot FROM public.py_number_methods WHERE id = num_id;
    IF nb_slot IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.oid = nb_slot::oid;

    IF call_nspname IS NULL OR call_proname IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_sequence_repeat(seq_id uuid, n integer)
RETURNS uuid AS $$
DECLARE
    left_type_id uuid;
    seq_methods_id uuid;
    sq_repeat_slot regproc;
    call_nspname text;
    call_proname text;
    res uuid;
BEGIN
    SELECT ob_type INTO left_type_id FROM public.py_object WHERE id = seq_id;
    IF left_type_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT tp_as_sequence INTO seq_methods_id FROM public.py_type_object WHERE ob_base = left_type_id;
    IF seq_methods_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT sq_repeat INTO sq_repeat_slot FROM public.py_sequence_methods WHERE id = seq_methods_id;
    IF sq_repeat_slot IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.oid = sq_repeat_slot::oid;

    IF call_nspname IS NULL OR call_proname IS NULL THEN
        RETURN NULL;
    END IF;

    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING seq_id, n INTO res;
    RETURN res;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    id_int uuid := '00000000-0000-4000-a000-000000000004';
    id_str uuid := '00000000-0000-4000-a000-000000000003';
BEGIN
    UPDATE public.py_number_methods
    SET nb_multiply = 'py_long_nb_multiply'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_int);

    UPDATE public.py_sequence_methods
    SET sq_repeat = 'py_unicode_sq_repeat'::regproc
    WHERE id = (SELECT tp_as_sequence FROM public.py_type_object WHERE ob_base = id_str);
END $$;

-- ============================================================================
-- py_object_multiply (PyNumber_Multiply): nb_multiply then sq_repeat(left/right), else TypeError
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_multiply(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    n_val numeric;
    n_int integer;
    left_type_id uuid;
    right_type_id uuid;
    left_tp_name text;
    right_tp_name text;
BEGIN
    res := public.py_object_multiply_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN
        RETURN res;
    END IF;

    SELECT long_value INTO n_val FROM public.py_long_object WHERE ob_base = right_id;
    IF n_val IS NOT NULL THEN
        n_int := n_val::integer;
        res := public.py_sequence_repeat(left_id, n_int);
        IF res IS NOT NULL THEN
            RETURN res;
        END IF;
    END IF;

    SELECT long_value INTO n_val FROM public.py_long_object WHERE ob_base = left_id;
    IF n_val IS NOT NULL THEN
        n_int := n_val::integer;
        res := public.py_sequence_repeat(right_id, n_int);
        IF res IS NOT NULL THEN
            RETURN res;
        END IF;
    END IF;

    SELECT ob_type INTO left_type_id FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for *: ''%'' and ''%''',
        COALESCE(left_tp_name, 'None'), COALESCE(right_tp_name, 'None');
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_opcode_BINARY_MULTIPLY (opcode 20): pop right, left → py_object_multiply(left, right) → push
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_BINARY_MULTIPLY(frame_id uuid)
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
    result_id := public.py_object_multiply(left_id, right_id);
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
