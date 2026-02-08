-- ============================================================================
-- Migration: Opcode POP_JUMP_FORWARD_IF_NONE (128) — CPython 3.11
-- 20260114240334
--
-- Pops TOS. If TOS is None, jump forward: next_byte_offset = current + 2 + oparg*2.
-- CPython 3.11: oparg = delta in instruction words; byte offset += 2 + oparg*2.
-- Depends: ceval_core (py_stack_pop), py_none_object.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_POP_JUMP_FORWARD_IF_NONE(
    frame_id UUID, current_byte_offset INTEGER, delta_words INTEGER)
RETURNS INTEGER AS $$
DECLARE
    tos_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    tos_id := public.py_stack_pop(frame_id);
    IF NOT EXISTS (SELECT 1 FROM public.py_none_object WHERE ob_base = tos_id) THEN
        RETURN NULL;
    END IF;
    RETURN current_byte_offset + 2 + delta_words * 2;
END;
$$ LANGUAGE plpgsql;
