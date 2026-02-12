-- ============================================================================
-- Migration: Opcode POP_JUMP_BACKWARD_IF_FALSE (175) — CPython 3.11
-- 20260114240326
--
-- Pops TOS. If TOS is false, jump backward by oparg instructions.
-- CPython 3.11: relative backward jump; target = start_i + 2 - oparg * 2.
-- Depends: ceval_core (py_stack_pop, py_object_istrue).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_POP_JUMP_BACKWARD_IF_FALSE(
    frame_id UUID, start_i INTEGER, arg INTEGER)
RETURNS INTEGER AS $$
DECLARE
    tos_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    tos_id := public.py_stack_pop(frame_id);
    IF public.py_object_istrue(tos_id) THEN
        RETURN NULL;
    END IF;
    RETURN start_i + 2 - arg * 2;
END;
$$ LANGUAGE plpgsql;
