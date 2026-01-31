-- ============================================================================
-- Migration: Jump opcodes (ceval: JUMP_FORWARD 110, POP_JUMP_IF_FALSE 114, POP_JUMP_IF_TRUE 115)
-- Created: 2026-01-14 24:04:00
--
-- Purpose:
--   - py_opcode_POP_JUMP_FORWARD_IF_FALSE(frame_id, current_i, delta_words): pop TOS;
--     if not py_object_istrue(TOS) then return next byte offset (current_i + 2 + delta_words*2).
--   - py_opcode_POP_JUMP_FORWARD_IF_TRUE(frame_id, current_i, delta_words): pop TOS;
--     if py_object_istrue(TOS) then return next byte offset; else fall through.
--   - py_eval_frame (232000): opcode 110 (JUMP_FORWARD), 114, 115; next_i support.
--
-- CPython 3.11: JUMP_FORWARD 110 (jrel), POP_JUMP_FORWARD_IF_FALSE 114 (jrel), POP_JUMP_FORWARD_IF_TRUE 115 (jrel).
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
