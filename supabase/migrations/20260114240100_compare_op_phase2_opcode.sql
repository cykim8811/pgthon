-- ============================================================================
-- Migration: COMPARE_OP Phase 2 — py_opcode_COMPARE_OP (opcode 107)
-- Created: 2026-01-14 24:01:00
--
-- Purpose:
--   VM opcode 107 (COMPARE_OP) 핸들러. 스택 right, left 순 pop 후
--   py_object_richcompare(left, right, compare_op) 호출. 결과가 NotImplemented면
--   TypeError, 아니면 True/False 푸시.
--
-- CPython (ceval.c): TOS = right, TOS1 = left → RichCompare(left, right, op).
--   반환값이 NotImplemented면 TypeError; 아니면 True/False 푸시.
--
-- Design: docs/COMPARE_OP_IMPLEMENTATION_PLAN.md
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_COMPARE_OP(frame_id uuid, compare_op integer)
RETURNS void AS $$
DECLARE
    right_id uuid;
    left_id  uuid;
    res_id   uuid;
    not_impl uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;

    right_id := public.py_stack_pop(frame_id);
    left_id  := public.py_stack_pop(frame_id);
    res_id   := public.py_object_richcompare(left_id, right_id, compare_op);

    IF res_id = not_impl THEN
        RAISE EXCEPTION 'TypeError: ''%'' not supported between instances of ''%'' and ''%''',
            compare_op, left_id, right_id;
    END IF;

    PERFORM public.py_stack_push(frame_id, res_id);
END;
$$ LANGUAGE plpgsql;
