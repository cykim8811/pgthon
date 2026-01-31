-- ============================================================================
-- Migration: BINARY_MULTIPLY Phase 1 — 스키마 확장 + 타입별 nb_multiply / sq_repeat
-- Created: 2026-01-14 23:90:00
--
-- Purpose:
--   BINARY_MULTIPLY 구현 Phase 1.
--   - A: py_number_methods에 nb_multiply 컬럼 추가
--   - B: py_sequence_methods에 sq_repeat 컬럼 추가
--   - C: py_long_nb_multiply(left_id, right_id) — int*int
--   - E: py_unicode_sq_repeat(seq_id uuid, n integer) — str*n (CPython sq_repeat: ssizeargfunc)
--
-- CPython: PyNumber_Multiply → nb_multiply, 실패 시 left/right의 sq_repeat(seq, n).
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
