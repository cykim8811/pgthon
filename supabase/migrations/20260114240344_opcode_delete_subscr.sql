-- ============================================================================
-- Migration: Opcode DELETE_SUBSCR (61) — CPython 3.11
-- 20260114240344
--
-- Stack: ..., obj, key → .... del obj[key].
-- Dispatches through py_object_delitem (mp_ass_subscript slot with NULL value).
-- Depends: ceval_core, opcode_binary_subscr (240342 — defines py_object_delitem).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_DELETE_SUBSCR(frame_id UUID)
RETURNS void AS $$
DECLARE
    key_id UUID;
    obj_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    key_id := public.py_stack_pop(frame_id);
    obj_id := public.py_stack_pop(frame_id);
    PERFORM public.py_object_delitem(obj_id, key_id);
END;
$$ LANGUAGE plpgsql;
