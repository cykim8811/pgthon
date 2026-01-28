-- ============================================================================
-- Migration: BINARY_ADD Phase 3 — py_object_add (PyNumber_Add 대응)
-- Created: 2026-01-14 23:82:00
--
-- Purpose:
--   CPython PyNumber_Add(v,w) 동작: (1) nb_add 경로 (2) 실패 시 left의 sq_concat
--   (3) 둘 다 실패 시 TypeError. tp_name 분기는 에러 메시지용으로만 사용.
--
-- CPython (Objects/abstract.c):
--   result = BINARY_OP1(v, w, nb_add);
--   if (result != NotImplemented) return result;
--   m = Py_TYPE(v)->tp_as_sequence; if (m && m->sq_concat) return m->sq_concat(v,w);
--   return binop_type_error(v, w, "+");
--
-- Design: docs/BINARY_ADD_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- NotImplemented singleton (bootstrap)
-- 00000000-0000-4000-b000-000000000012

-- ============================================================================
-- H: py_object_add(left_id, right_id) — PyNumber_Add 대응
--    (1) py_object_add_via_nb(left, right) → 성공 시 반환
--    (2) py_sequence_concat(left, right) → 성공 시 반환
--    (3) 둘 다 실패 시 TypeError. 타입명은 에러 메시지용으로만 tp_name 조회.
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

    -- 둘 다 실패: TypeError (에러 메시지용으로만 tp_name 사용)
    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for +: ''%'' and ''%''',
        COALESCE(left_tp_name, 'None'), COALESCE(right_tp_name, 'None');
END;
$$ LANGUAGE plpgsql;
