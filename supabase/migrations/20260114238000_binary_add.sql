-- ============================================================================
-- Migration: BINARY_ADD (nb_add, sq_concat, PyNumber_Add, opcode 23)
-- Created: 2026-01-14 23:80:00
--
-- Purpose:
--   BINARY_ADD: type-specific nb_add/sq_concat, dispatch (py_object_add_via_nb, py_sequence_concat),
--   py_object_add (PyNumber_Add), slot registration, py_opcode_BINARY_ADD (opcode 23).
--   nb_add, sq_concat columns are in 20260114220000_python_object_schema.sql.
--
-- CPython: PyNumber_Add → nb_add (binaryfunc), fallback left's tp_as_sequence->sq_concat.
-- Design: docs/BINARY_ADD_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- Singleton (bootstrap 20260114223000)
-- NotImplemented: 00000000-0000-4000-b000-000000000012

-- nb_add, sq_concat columns are defined in 20260114220000_python_object_schema.sql.

-- ============================================================================
-- C: py_long_nb_add(left_id, right_id) — int + int
--    binaryfunc (PyObject *a, PyObject *b) -> PyObject*
--    left/right 모두 py_long_object일 때만 덧셈, 새 int 객체 id 반환. 그 외 NotImplemented.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_add(left_id uuid, right_id uuid)
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
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, lv + rv);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- D: py_unicode_nb_add(left_id, right_id) — str + str (연결)
--    left/right 모두 py_unicode_object일 때만 연결, 새 str 객체 id 반환. 그 외 NotImplemented.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_unicode_nb_add(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv text;
    rv text;
    id_str_type uuid := '00000000-0000-4000-a000-000000000003';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = left_id) THEN
        RETURN id_not_implemented;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = right_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT COALESCE(str_value, '') INTO lv FROM public.py_unicode_object WHERE ob_base = left_id;
    SELECT COALESCE(str_value, '') INTO rv FROM public.py_unicode_object WHERE ob_base = right_id;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_str_type);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (result_id, lv || rv);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- E: py_unicode_sq_concat(left_id, right_id) — left의 sq_concat (CPython: left만 사용)
--    left가 str일 때만 호출된다고 가정. (str, str) → 새 str id. (str, non-str) → TypeError.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_unicode_sq_concat(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv text;
    rv text;
    id_str_type uuid := '00000000-0000-4000-a000-000000000003';
    right_type_id uuid;
    right_tp_name text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = left_id) THEN
        RAISE EXCEPTION 'TypeError: py_unicode_sq_concat left operand is not str';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = right_id) THEN
        SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
        SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
        RAISE EXCEPTION 'TypeError: can only concatenate str (not "%") to str', COALESCE(right_tp_name, 'None');
    END IF;
    SELECT COALESCE(str_value, '') INTO lv FROM public.py_unicode_object WHERE ob_base = left_id;
    SELECT COALESCE(str_value, '') INTO rv FROM public.py_unicode_object WHERE ob_base = right_id;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_str_type);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (result_id, lv || rv);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Dispatch: py_object_add_via_nb, py_sequence_concat; slot registration
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_add_via_nb(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    left_type_id uuid;
    right_type_id uuid;
    num_id uuid;
    nb_add_slot regproc;
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

    SELECT nb_add INTO nb_add_slot FROM public.py_number_methods WHERE id = num_id;
    IF nb_add_slot IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.oid = nb_add_slot::oid;

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

    SELECT nb_add INTO nb_add_slot FROM public.py_number_methods WHERE id = num_id;
    IF nb_add_slot IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.oid = nb_add_slot::oid;

    IF call_nspname IS NULL OR call_proname IS NULL THEN
        RETURN id_not_implemented;
    END IF;

    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_sequence_concat(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    left_type_id uuid;
    seq_id uuid;
    sq_concat_slot regproc;
    call_nspname text;
    call_proname text;
    res uuid;
BEGIN
    SELECT ob_type INTO left_type_id FROM public.py_object WHERE id = left_id;
    IF left_type_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT tp_as_sequence INTO seq_id FROM public.py_type_object WHERE ob_base = left_type_id;
    IF seq_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT sq_concat INTO sq_concat_slot FROM public.py_sequence_methods WHERE id = seq_id;
    IF sq_concat_slot IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.oid = sq_concat_slot::oid;

    IF call_nspname IS NULL OR call_proname IS NULL THEN
        RETURN NULL;
    END IF;

    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING left_id, right_id INTO res;
    RETURN res;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    id_int uuid := '00000000-0000-4000-a000-000000000004';
    id_str uuid := '00000000-0000-4000-a000-000000000003';
    str_num_id uuid;
BEGIN
    UPDATE public.py_number_methods
    SET nb_add = 'py_long_nb_add'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_int);

    str_num_id := gen_random_uuid();
    INSERT INTO public.py_number_methods (id, nb_add)
    VALUES (str_num_id, 'py_unicode_nb_add'::regproc);
    UPDATE public.py_type_object SET tp_as_number = str_num_id WHERE ob_base = id_str;

    UPDATE public.py_sequence_methods
    SET sq_concat = 'py_unicode_sq_concat'::regproc
    WHERE id = (SELECT tp_as_sequence FROM public.py_type_object WHERE ob_base = id_str);
END $$;

-- ============================================================================
-- py_object_add (PyNumber_Add): nb_add then sq_concat, else TypeError
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_add(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    left_type_id uuid;
    right_type_id uuid;
    left_tp_name text;
    right_tp_name text;
BEGIN
    res := public.py_object_add_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN
        RETURN res;
    END IF;

    res := public.py_sequence_concat(left_id, right_id);
    IF res IS NOT NULL THEN
        RETURN res;
    END IF;

    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for +: ''%'' and ''%''',
        COALESCE(left_tp_name, 'None'), COALESCE(right_tp_name, 'None');
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_opcode_BINARY_ADD (opcode 23): pop right, left → py_object_add(left, right) → push
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_BINARY_ADD(frame_id uuid)
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
    result_id := public.py_object_add(left_id, right_id);
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
