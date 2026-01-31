-- ============================================================================
-- Migration: Jump Phase 2 — POP_JUMP_FORWARD_IF_FALSE, JUMP_FORWARD, eval_frame
-- Created: 2026-01-14 24:04:00
--
-- Purpose:
--   - py_opcode_POP_JUMP_FORWARD_IF_FALSE(frame_id, current_i, delta_words): pop TOS,
--     if not py_object_istrue(TOS) then return next byte offset (current_i + 2 + delta_words*2).
--   - py_eval_frame: opcode 110 (JUMP_FORWARD), 114 (POP_JUMP_FORWARD_IF_FALSE); next_i 지원.
--
-- CPython 3.11: JUMP_FORWARD 110 (jrel), POP_JUMP_FORWARD_IF_FALSE 114 (jrel). Operand = words to skip (1 word = 2 bytes).
--
-- Design: docs/JUMP_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- POP_JUMP_FORWARD_IF_FALSE: pop TOS; if not PyObject_IsTrue(TOS), return next_i = current_i + 2 + delta_words*2; else NULL.
CREATE OR REPLACE FUNCTION public.py_opcode_POP_JUMP_FORWARD_IF_FALSE(
    frame_id uuid, current_byte_offset integer, delta_words integer)
RETURNS integer AS $$
DECLARE
    tos_id uuid;
    next_i integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;

    tos_id := public.py_stack_pop(frame_id);

    IF public.py_object_istrue(tos_id) THEN
        RETURN NULL;
    END IF;

    next_i := current_byte_offset + 2 + delta_words * 2;
    RETURN next_i;
END;
$$ LANGUAGE plpgsql;

-- py_eval_frame is defined in 20260114232000_vm_eval_frame.sql (includes opcode 110, 114, next_i).
