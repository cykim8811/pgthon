-- ============================================================================
-- Migration: Opcode IS_OP (117) — CPython 3.11
-- 20260114240333
--
-- Implements "is" / "is not": pop right, pop left; push True if identity match
-- (oparg 0 = is) or mismatch (oparg 1 = is not). Identity = same object (UUID).
-- CPython 3.11: oparg 0 = IS_OP (is), oparg 1 = IS_OP (is not).
-- Depends: ceval_core (py_stack_pop, py_stack_push).
-- Singletons: True 00000000-0000-4000-b000-000000000010, False 00000000-0000-4000-b000-000000000011.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_IS_OP(frame_id UUID, oparg INTEGER)
RETURNS void AS $$
DECLARE
    right_id UUID;
    left_id UUID;
    result_id UUID;
    ID_TRUE_OBJ  UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000011';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    right_id := public.py_stack_pop(frame_id);
    left_id := public.py_stack_pop(frame_id);
    IF oparg = 0 THEN
        -- "is": push True if left is right (same object)
        IF left_id = right_id THEN
            result_id := ID_TRUE_OBJ;
        ELSE
            result_id := ID_FALSE_OBJ;
        END IF;
    ELSIF oparg = 1 THEN
        -- "is not": push True if left is not right
        IF left_id != right_id THEN
            result_id := ID_TRUE_OBJ;
        ELSE
            result_id := ID_FALSE_OBJ;
        END IF;
    ELSE
        RAISE EXCEPTION 'IS_OP: invalid oparg %', oparg;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
