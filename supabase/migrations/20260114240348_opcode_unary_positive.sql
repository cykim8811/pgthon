-- ============================================================================
-- Migration: Opcode UNARY_POSITIVE (10) — CPython 3.11
-- 20260114240348
--
-- Stack: ..., x → ..., +x. Uses tp_as_number->nb_positive (py_object_positive).
-- Depends: ceval_core, 235502 (nb_positive slot).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_UNARY_POSITIVE(frame_id UUID)
RETURNS void AS $$
DECLARE
    tos_id UUID;
    result_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    tos_id := public.py_stack_pop(frame_id);
    result_id := public.py_object_positive(tos_id);
    IF result_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, result_id);
    END IF;
END;
$$ LANGUAGE plpgsql;
