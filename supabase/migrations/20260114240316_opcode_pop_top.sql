-- ============================================================================
-- Migration: Opcode POP_TOP (1) — 240316 (opcode block)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_POP_TOP(frame_id uuid)
RETURNS void AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    PERFORM public.py_stack_pop(frame_id);
END;
$$ LANGUAGE plpgsql;
