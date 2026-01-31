-- ============================================================================
-- Migration: COMPARE_OP Phase 3 — py_eval_frame에 opcode 107 분기
-- Created: 2026-01-14 24:02:00
--
-- Purpose:
--   opcode 107 (COMPARE_OP) 실행 시 public.py_opcode_COMPARE_OP(frame_id, arg) 호출.
--
-- Design: docs/COMPARE_OP_IMPLEMENTATION_PLAN.md
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_eval_frame(frame_id UUID)
RETURNS UUID AS $$
DECLARE
    code_obj_id UUID;
    co_code_id UUID;
    bytecode bytea;
    opcode INTEGER;
    arg INTEGER;
    i INTEGER := 0;
    instruction_size INTEGER;
    return_value UUID := NULL;
    should_return BOOLEAN := FALSE;
    bytecode_length INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'Frame with id % does not have a code object', frame_id;
    END IF;

    SELECT co_code INTO co_code_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_code_id IS NULL THEN
        RAISE EXCEPTION 'Code object with id % does not have co_code', code_obj_id;
    END IF;

    SELECT bytes_value INTO bytecode FROM public.py_bytes_object WHERE ob_base = co_code_id;
    IF bytecode IS NULL THEN
        RAISE EXCEPTION 'Bytes object with id % does not have bytes_value', co_code_id;
    END IF;

    bytecode_length := length(bytecode);

    WHILE i < bytecode_length LOOP
        opcode := get_byte(bytecode, i);
        arg := get_byte(bytecode, i + 1);

        CASE opcode
            WHEN 100 THEN
                PERFORM public.py_opcode_LOAD_CONST(frame_id, arg);
            WHEN 101 THEN
                PERFORM public.py_opcode_LOAD_NAME(frame_id, arg);
            WHEN 141 THEN
                PERFORM public.py_opcode_CALL_FUNCTION(frame_id, arg);
            WHEN 90 THEN
                PERFORM public.py_opcode_STORE_NAME(frame_id, arg);
            WHEN 23 THEN   -- BINARY_ADD
                PERFORM public.py_opcode_BINARY_ADD(frame_id);
            WHEN 24 THEN   -- BINARY_SUBTRACT
                PERFORM public.py_opcode_BINARY_SUBTRACT(frame_id);
            WHEN 20 THEN   -- BINARY_MULTIPLY
                PERFORM public.py_opcode_BINARY_MULTIPLY(frame_id);
            WHEN 107 THEN  -- COMPARE_OP
                PERFORM public.py_opcode_COMPARE_OP(frame_id, arg);
            WHEN 83 THEN
                return_value := public.py_stack_pop(frame_id);
                should_return := TRUE;
                UPDATE public.py_frame_object SET f_lasti = i WHERE ob_base = frame_id;
                EXIT;
            ELSE
                RAISE EXCEPTION 'Unknown opcode: % at byte offset %', opcode, i;
        END CASE;

        IF opcode != 83 THEN
            UPDATE public.py_frame_object SET f_lasti = i WHERE ob_base = frame_id;
        END IF;

        instruction_size := public.py_get_opcode_size(opcode);
        i := i + instruction_size;
    END LOOP;

    IF should_return THEN
        RETURN return_value;
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;
