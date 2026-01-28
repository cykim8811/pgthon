-- ============================================================================
-- Migration: BINARY_ADD Phase 4 — py_opcode_BINARY_ADD (작업 J)
-- Created: 2026-01-14 23:83:00
--
-- Purpose:
--   VM opcode 23 (BINARY_ADD) 핸들러. 스택에서 right, left 순으로 pop 후
--   py_object_add(left_id, right_id) 호출해 결과를 스택에 push.
--   예외는 그대로 전파.
--
-- CPython (ceval.c):
--   TOS = right, TOS1 = left → left + right 결과를 TOS1 자리에 두고 TOS 제거
--   즉 pop right, pop left, result = add(left, right), push result.
--
-- Design: docs/BINARY_ADD_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- ============================================================================
-- J: py_opcode_BINARY_ADD(frame_id) — opcode 23 핸들러
--    스택 pop(right), pop(left) → py_object_add(left, right) → push(result)
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
