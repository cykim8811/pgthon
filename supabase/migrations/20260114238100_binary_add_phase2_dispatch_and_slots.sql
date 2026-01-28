-- ============================================================================
-- Migration: BINARY_ADD Phase 2 — 디스패치(F,G) + 슬롯 등록(I)
-- Created: 2026-01-14 23:81:00
--
-- Purpose:
--   Phase 1(238000) 이후: py_object_add_via_nb, py_sequence_concat, nb_add/sq_concat 슬롯 등록.
--   - F: py_object_add_via_nb(left, right) — left의 nb_add(left,right), NotImplemented 시 right의 nb_add(right,left)
--   - G: py_sequence_concat(left, right) — left의 tp_as_sequence->sq_concat(left, right). 없으면 NULL 반환.
--   - I: int/str의 nb_add 등록, str의 sq_concat 등록
--
-- Design: docs/BINARY_ADD_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- NotImplemented singleton (bootstrap)
-- 00000000-0000-4000-b000-000000000012

-- ============================================================================
-- F: py_object_add_via_nb(left_id, right_id)
--    left의 tp_as_number->nb_add(left, right) 호출.
--    반환값이 NotImplemented면 right의 nb_add(right, left) 한 번 더 시도.
--    둘 다 없거나 둘 다 NotImplemented면 호출자에게 실패(NotImplemented id 반환).
--    동적 호출은 schema.func 해석을 위해 pg_proc에서 nspname, proname 조회 후 %I.%I 사용.
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

    -- NotImplemented or no slot: try right's nb_add(right, left)
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

-- ============================================================================
-- G: py_sequence_concat(left_id, right_id)
--    left의 tp_as_sequence->sq_concat(left, right) 호출. CPython: 왼쪽의 sq_concat만 사용.
--    tp_as_sequence 또는 sq_concat이 없으면 NULL 반환(호출자가 TypeError 처리).
--    동적 호출은 schema.func 해석을 위해 pg_proc에서 nspname, proname 조회 후 %I.%I 사용.
-- ============================================================================

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

-- ============================================================================
-- I: 슬롯 등록 — int/str의 nb_add, str의 sq_concat
-- ============================================================================

DO $$
DECLARE
    id_int uuid := '00000000-0000-4000-a000-000000000004';
    id_str uuid := '00000000-0000-4000-a000-000000000003';
    str_num_id uuid;
BEGIN
    -- int: 기존 tp_as_number 행에 nb_add 설정 (235500에서 nb_absolute만 넣었음)
    UPDATE public.py_number_methods
    SET nb_add = 'py_long_nb_add'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_int);

    -- str: tp_as_number 없음 → 새 py_number_methods 행 생성 후 연결, nb_add만 등록
    str_num_id := gen_random_uuid();
    INSERT INTO public.py_number_methods (id, nb_add)
    VALUES (str_num_id, 'py_unicode_nb_add'::regproc);
    UPDATE public.py_type_object SET tp_as_number = str_num_id WHERE ob_base = id_str;

    -- str: 기존 tp_as_sequence 행에 sq_concat 설정 (226000에서 sq_length만 넣었음)
    UPDATE public.py_sequence_methods
    SET sq_concat = 'py_unicode_sq_concat'::regproc
    WHERE id = (SELECT tp_as_sequence FROM public.py_type_object WHERE ob_base = id_str);
END $$;
