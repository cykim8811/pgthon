-- ============================================================================
-- Migration: BINARY_MULTIPLY Phase 4 — py_opcode_BINARY_MULTIPLY (작업 J)
-- Created: 2026-01-14 23:93:00
--
-- Purpose:
--   VM opcode 20 (BINARY_MULTIPLY) 핸들러. 스택 right, left pop → py_object_multiply(left, right) → push.
--
-- Design: docs/BINARY_MULTIPLY_IMPLEMENTATION_PLAN.md
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_BINARY_MULTIPLY(frame_id uuid)
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
    result_id := public.py_object_multiply(left_id, right_id);
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
