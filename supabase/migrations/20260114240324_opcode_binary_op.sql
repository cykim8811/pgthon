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
        WHEN 0 THEN   -- NB_ADD
            result_id := public.py_object_add(left_id, right_id);
        WHEN 1 THEN   -- NB_AND
            result_id := public.py_object_and(left_id, right_id);
        WHEN 2 THEN   -- NB_FLOOR_DIVIDE
            result_id := public.py_object_floor_divide(left_id, right_id);
        WHEN 3 THEN   -- NB_LSHIFT
            result_id := public.py_object_lshift(left_id, right_id);
        WHEN 5 THEN   -- NB_MULTIPLY
            result_id := public.py_object_multiply(left_id, right_id);
        WHEN 6 THEN   -- NB_REMAINDER
            result_id := public.py_object_remainder(left_id, right_id);
        WHEN 7 THEN   -- NB_OR
            result_id := public.py_object_or(left_id, right_id);
        WHEN 8 THEN   -- NB_POWER
            result_id := public.py_object_power(left_id, right_id);
        WHEN 9 THEN   -- NB_RSHIFT
            result_id := public.py_object_rshift(left_id, right_id);
        WHEN 10 THEN  -- NB_SUBTRACT
            result_id := public.py_object_subtract(left_id, right_id);
        WHEN 11 THEN  -- NB_TRUE_DIVIDE
            result_id := public.py_object_true_divide(left_id, right_id);
        WHEN 12 THEN  -- NB_XOR
            result_id := public.py_object_xor(left_id, right_id);
        -- Inplace ops: delegate to non-inplace (correct for immutable int/float/str)
        WHEN 13 THEN  -- NB_INPLACE_ADD
            result_id := public.py_object_add(left_id, right_id);
        WHEN 14 THEN  -- NB_INPLACE_AND
            result_id := public.py_object_and(left_id, right_id);
        WHEN 15 THEN  -- NB_INPLACE_FLOOR_DIVIDE
            result_id := public.py_object_floor_divide(left_id, right_id);
        WHEN 16 THEN  -- NB_INPLACE_LSHIFT
            result_id := public.py_object_lshift(left_id, right_id);
        WHEN 18 THEN  -- NB_INPLACE_MULTIPLY
            result_id := public.py_object_multiply(left_id, right_id);
        WHEN 19 THEN  -- NB_INPLACE_REMAINDER
            result_id := public.py_object_remainder(left_id, right_id);
        WHEN 20 THEN  -- NB_INPLACE_OR
            result_id := public.py_object_or(left_id, right_id);
        WHEN 21 THEN  -- NB_INPLACE_POWER
            result_id := public.py_object_power(left_id, right_id);
        WHEN 22 THEN  -- NB_INPLACE_RSHIFT
            result_id := public.py_object_rshift(left_id, right_id);
        WHEN 23 THEN  -- NB_INPLACE_SUBTRACT
            result_id := public.py_object_subtract(left_id, right_id);
        WHEN 24 THEN  -- NB_INPLACE_TRUE_DIVIDE
            result_id := public.py_object_true_divide(left_id, right_id);
        WHEN 25 THEN  -- NB_INPLACE_XOR
            result_id := public.py_object_xor(left_id, right_id);
        ELSE
            -- NB_MATRIX_MULTIPLY(4), NB_INPLACE_MATRIX_MULTIPLY(17): not commonly used
            PERFORM public.py_err_set_type_error('unsupported operand type(s) for binary op: sub-op ' || oparg);
            RETURN;
    END CASE;

    IF result_id IS NULL AND public.py_err_occurred() THEN
        RETURN;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
