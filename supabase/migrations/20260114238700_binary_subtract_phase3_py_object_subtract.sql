-- ============================================================================
-- Migration: BINARY_SUBTRACT Phase 3 — py_object_subtract (PyNumber_Subtract 대응)
-- Created: 2026-01-14 23:87:00
--
-- Purpose:
--   CPython PyNumber_Subtract(v,w) 동작: nb_subtract 경로만 사용. 실패 시 TypeError.
--   sq_* 폴백 없음.
--
-- CPython (Objects/abstract.c):
--   return binary_op(v, w, NB_SLOT(nb_subtract), "-");
--   → BINARY_OP1 → 실패 시 binop_type_error(v, w, "-")
--
-- Design: docs/BINARY_SUBTRACT_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- ============================================================================
-- H: py_object_subtract(left_id, right_id) — PyNumber_Subtract 대응
--    py_object_subtract_via_nb(left, right) → 성공 시 반환, 실패 시 TypeError
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

    -- 실패: TypeError (에러 메시지용 tp_name)
    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for -: ''%'' and ''%''',
        COALESCE(left_tp_name, 'None'), COALESCE(right_tp_name, 'None');
END;
$$ LANGUAGE plpgsql;
