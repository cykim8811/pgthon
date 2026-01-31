-- ============================================================================
-- Migration: BINARY_MULTIPLY Phase 2 — 디스패치(F,G) + 슬롯 등록(I)
-- Created: 2026-01-14 23:91:00
--
-- Purpose:
--   - F: py_object_multiply_via_nb(left, right) — left nb_multiply, NotImplemented 시 right nb_multiply(right, left)
--   - G: py_sequence_repeat(seq_id uuid, n integer) — left의 tp_as_sequence->sq_repeat(seq_id, n)
--   - I: int의 nb_multiply, str의 sq_repeat 등록
--
-- Design: docs/BINARY_MULTIPLY_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- NotImplemented singleton
-- 00000000-0000-4000-b000-000000000012

-- ============================================================================
-- F: py_object_multiply_via_nb(left_id, right_id)
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

-- ============================================================================
-- G: py_sequence_repeat(seq_id uuid, n integer)
--    left의 tp_as_sequence->sq_repeat(seq_id, n) 호출. 없으면 NULL.
-- ============================================================================

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

-- ============================================================================
-- I: 슬롯 등록 — int의 nb_multiply, str의 sq_repeat
-- ============================================================================

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
