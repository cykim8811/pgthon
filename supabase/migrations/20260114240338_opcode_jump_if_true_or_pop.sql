-- ============================================================================
-- Migration: Opcode JUMP_IF_TRUE_OR_POP (112) — CPython 3.11
-- 20260114240338
--
-- If TOS is true, jump forward (next = current + 2 + oparg*2), leave TOS.
-- Else pop TOS and fall through.
-- Depends: ceval_core (py_stack_pop, py_stack_push), py_object_istrue.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_JUMP_IF_TRUE_OR_POP(
    frame_id UUID, current_byte_offset INTEGER, delta_words INTEGER)
RETURNS INTEGER AS $$
DECLARE
    tos_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    tos_id := public.py_stack_pop(frame_id);
    IF NOT public.py_object_istrue(tos_id) THEN
        RETURN NULL;
    END IF;
    PERFORM public.py_stack_push(frame_id, tos_id);
    RETURN current_byte_offset + 2 + delta_words * 2;
END;
$$ LANGUAGE plpgsql;
