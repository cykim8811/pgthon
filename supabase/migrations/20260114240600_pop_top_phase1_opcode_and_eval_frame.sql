-- ============================================================================
-- Migration: POP_TOP Phase 1 — opcode 1, py_get_opcode_size, py_eval_frame
-- Created: 2026-01-14 24:06:00
--
-- Purpose:
--   CPython POP_TOP (opcode 1): pop one value from stack and discard.
--   - py_opcode_POP_TOP(frame_id): py_stack_pop(frame_id), result discarded.
--   - py_eval_frame: WHEN 1 THEN PERFORM py_opcode_POP_TOP(frame_id).
--
-- py_get_opcode_size: definition lives in 20260114230000_vm_core.sql (Python 3.11 uniform 2-byte).
--
-- Design: docs/POP_TOP_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- POP_TOP: pop one value from stack and discard (CPython: TOS pop, discard).
CREATE OR REPLACE FUNCTION public.py_opcode_POP_TOP(frame_id uuid)
RETURNS void AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    PERFORM public.py_stack_pop(frame_id);
END;
$$ LANGUAGE plpgsql;

-- py_eval_frame is defined in 20260114232000_vm_eval_frame.sql (includes opcode 1 POP_TOP).
