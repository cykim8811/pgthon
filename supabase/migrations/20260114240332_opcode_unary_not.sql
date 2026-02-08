-- ============================================================================
-- Migration: Opcode UNARY_NOT (12) — CPython 3.11
-- 20260114240332
--
-- Implements "not x": pop TOS, push True if not PyObject_IsTrue(TOS) else False.
-- CPython 3.11: UNARY_NOT has no meaningful oparg (oparg typically 0).
-- Depends: ceval_core (py_stack_pop, py_stack_push), py_object_istrue.
-- Singletons: True 00000000-0000-4000-b000-000000000010, False 00000000-0000-4000-b000-000000000011.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_UNARY_NOT(frame_id UUID)
RETURNS void AS $$
DECLARE
    tos_id UUID;
    result_id UUID;
    ID_TRUE_OBJ  UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000011';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    tos_id := public.py_stack_pop(frame_id);
    IF public.py_object_istrue(tos_id) THEN
        result_id := ID_FALSE_OBJ;
    ELSE
        result_id := ID_TRUE_OBJ;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
