-- ============================================================================
-- Migration: BINARY_ADD Phase 1 — 스키마 확장 + 타입별 nb_add / sq_concat (의존성 없음)
-- Created: 2026-01-14 23:80:00
--
-- Purpose:
--   BINARY_ADD 구현의 Phase 1. 다른 BINARY_ADD 관련 작업에 의존하지 않는 작업만 수행.
--   - A: py_number_methods에 nb_add 컬럼 추가
--   - B: py_sequence_methods에 sq_concat 컬럼 추가
--   - C: py_long_nb_add(left_id, right_id)
--   - D: py_unicode_nb_add(left_id, right_id)
--   - E: py_unicode_sq_concat(left_id, right_id)
--
-- CPython: PyNumber_Add → nb_add (binaryfunc), 실패 시 left의 tp_as_sequence->sq_concat.
-- 타입 판별은 구체 테이블(py_long_object, py_unicode_object) 존재 여부만 사용. tp_name 분기 없음.
--
-- Design: docs/BINARY_ADD_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- Singleton (bootstrap 20260114223000)
-- NotImplemented: 00000000-0000-4000-b000-000000000012

-- ============================================================================
-- A: py_number_methods에 nb_add 컬럼 추가
-- ============================================================================

ALTER TABLE public.py_number_methods
  ADD COLUMN IF NOT EXISTS nb_add regproc;

-- ============================================================================
-- B: py_sequence_methods에 sq_concat 컬럼 추가
-- ============================================================================

ALTER TABLE public.py_sequence_methods
  ADD COLUMN IF NOT EXISTS sq_concat regproc;

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
