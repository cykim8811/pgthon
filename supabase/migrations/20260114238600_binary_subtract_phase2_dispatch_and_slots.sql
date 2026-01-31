-- ============================================================================
-- Migration: BINARY_SUBTRACT Phase 2 — 디스패치(F) + 슬롯 등록(I)
-- Created: 2026-01-14 23:86:00
--
-- Purpose:
--   Phase 1(238500) 이후: py_object_subtract_via_nb, int의 nb_subtract 슬롯 등록.
--   - F: py_object_subtract_via_nb(left, right) — left의 nb_subtract(left,right),
--        NotImplemented 시 right의 nb_subtract(right,left)
--   - I: int의 nb_subtract 등록
--
-- Design: docs/BINARY_SUBTRACT_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- NotImplemented singleton (bootstrap)
-- 00000000-0000-4000-b000-000000000012

-- ============================================================================
-- F: py_object_subtract_via_nb(left_id, right_id)
--    left의 tp_as_number->nb_subtract(left, right) 호출.
--    반환값이 NotImplemented면 right의 nb_subtract(right, left) 시도.
--    동적 호출은 pg_proc에서 nspname, proname 조회 후 %I.%I 사용.
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

    -- NotImplemented or no slot: try right's nb_subtract(right, left)
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

-- ============================================================================
-- I: 슬롯 등록 — int의 nb_subtract
-- ============================================================================

DO $$
DECLARE
    id_int uuid := '00000000-0000-4000-a000-000000000004';
BEGIN
    UPDATE public.py_number_methods
    SET nb_subtract = 'py_long_nb_subtract'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_int);
END $$;
