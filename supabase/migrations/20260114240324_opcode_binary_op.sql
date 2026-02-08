-- ============================================================================
-- Migration: Opcode BINARY_OP (122) — CPython 3.11
-- 20260114240324_opcode_binary_op.sql
--
-- BINARY_OP(oparg): oparg is sub-opcode (NB_* in Include/opcode.h).
-- Stack: ..., left, right → ..., result.
-- Elytra implements NB_ADD(0), NB_SUBTRACT(10), NB_MULTIPLY(5) via existing
-- py_object_add / py_object_subtract / py_object_multiply. Other sub-ops
-- set TypeError (CPython: slot not implemented).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_BINARY_OP(frame_id uuid, oparg integer)
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

    CASE oparg
        WHEN 0 THEN
            -- NB_ADD
            result_id := public.py_object_add(left_id, right_id);
        WHEN 10 THEN
            -- NB_SUBTRACT
            result_id := public.py_object_subtract(left_id, right_id);
        WHEN 5 THEN
            -- NB_MULTIPLY
            result_id := public.py_object_multiply(left_id, right_id);
        ELSE
            -- NB_AND(1), NB_FLOOR_DIVIDE(2), NB_LSHIFT(3), NB_MATRIX_MULTIPLY(4),
            -- NB_REMAINDER(6), NB_OR(7), NB_POWER(8), NB_RSHIFT(9), NB_TRUE_DIVIDE(11),
            -- NB_XOR(12), NB_INPLACE_*(13..25): not implemented → TypeError
            PERFORM public.py_err_set_type_error('unsupported operand type(s) for binary op: sub-op ' || oparg);
            RETURN;
    END CASE;

    IF result_id IS NULL AND public.py_err_occurred() THEN
        RETURN;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
