-- ============================================================================
-- Migration: Jump Phase 3 — POP_JUMP_FORWARD_IF_TRUE (opcode 115)
-- Created: 2026-01-14 24:05:00
--
-- Purpose:
--   CPython 3.11 POP_JUMP_FORWARD_IF_TRUE (115, jrel): pop TOS; if PyObject_IsTrue(TOS)
--   then jump to current_i + 2 + delta_words*2; else fall through.
--
-- Design: docs/JUMP_IMPLEMENTATION_PLAN.md (extension)
-- ============================================================================

-- POP_JUMP_FORWARD_IF_TRUE: pop TOS; if PyObject_IsTrue(TOS), return next_i; else NULL.
CREATE OR REPLACE FUNCTION public.py_opcode_POP_JUMP_FORWARD_IF_TRUE(
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

    IF NOT public.py_object_istrue(tos_id) THEN
        RETURN NULL;
    END IF;

    next_i := current_byte_offset + 2 + delta_words * 2;
    RETURN next_i;
END;
$$ LANGUAGE plpgsql;

-- py_eval_frame is defined in 20260114232000_vm_eval_frame.sql (includes opcode 115).
