-- ============================================================================
-- Migration: Opcode STORE_SUBSCR (60) — CPython 3.11
-- 20260114240343
--
-- Stack: ..., obj, key, value → ...  (TOS = value). obj[key] = value.
-- Dispatches through py_object_setitem (mp_ass_subscript slot).
-- Depends: ceval_core, opcode_binary_subscr (240342 — defines py_object_setitem).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_STORE_SUBSCR(frame_id UUID)
RETURNS void AS $$
DECLARE
    value_id UUID;
    key_id UUID;
    obj_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    value_id := public.py_stack_pop(frame_id);
    key_id := public.py_stack_pop(frame_id);
    obj_id := public.py_stack_pop(frame_id);
    PERFORM public.py_object_setitem(obj_id, key_id, value_id);
END;
$$ LANGUAGE plpgsql;
