-- ============================================================================
-- Migration: COMPARE_OP (cpython ceval: opcode 107)
-- Created: 2026-01-14 24:00:00
--
-- Purpose:
--   VM opcode 107 (COMPARE_OP) handler. Pops right, left from stack, calls
--   py_object_richcompare(left, right, compare_op). Result NotImplemented →
--   TypeError; else push True/False.
--
--   py_object_richcompare (with reflected op) is defined in 20260114236000_tp_richcompare_slot.sql.
--
-- CPython (ceval.c): TOS = right, TOS1 = left → RichCompare(left, right, op).
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
