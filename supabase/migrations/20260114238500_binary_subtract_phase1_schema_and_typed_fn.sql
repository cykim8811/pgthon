-- ============================================================================
-- Migration: BINARY_SUBTRACT Phase 1 — 스키마 확장 + 타입별 nb_subtract (의존성 없음)
-- Created: 2026-01-14 23:85:00
--
-- Purpose:
--   BINARY_SUBTRACT 구현의 Phase 1. nb_subtract 컬럼 추가 및 int - int 전용 함수.
--   - A: py_number_methods에 nb_subtract 컬럼 추가
--   - C: py_long_nb_subtract(left_id, right_id) — int - int만, 그 외 NotImplemented
--
-- CPython: PyNumber_Subtract → nb_subtract (binaryfunc) 만 사용. sq_* 폴백 없음.
-- 타입 판별은 py_long_object 존재 여부만 사용. tp_name 분기 없음.
--
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
