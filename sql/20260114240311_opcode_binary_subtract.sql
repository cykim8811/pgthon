-- ============================================================================
-- Migration: Opcode BINARY_SUBTRACT (24) — 240311 (opcode block)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_BINARY_SUBTRACT(frame_id uuid)
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
    result_id := public.py_object_subtract(left_id, right_id);
    IF result_id IS NULL AND public.py_err_occurred() THEN
        RETURN;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
