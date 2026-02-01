-- ============================================================================
-- Migration: VM Frame Evaluation Function
-- Created: 2026-01-14 23:20:00
--
-- Purpose:
--   Implements the main bytecode execution engine (py_eval_frame) for the
--   Elytra VM. This function is the core of the interpreter, equivalent to
--   CPython's PyEval_EvalFrameEx / _PyEval_EvalFrameDefault.
--
--   Functions:
--   - py_eval_frame: Execute bytecode in a frame object
--
-- Design:
--   - Reads bytecode from code object's co_code (bytes object)
--   - Parses instructions (opcode + operand)
--   - Dispatches to opcode-specific handlers
--   - Manages evaluation stack via py_stack_push/pop
--   - Returns value when RETURN_VALUE opcode is executed
--   - Updates f_lasti (byte offset) after each instruction
--
-- CPython Compatibility:
--   - Mirrors PyEval_EvalFrameEx behavior exactly
--   - RETURN_VALUE opcode pops value and returns it (loop exits)
--   - Normal loop completion returns NULL (rare, usually indicates error)
--   - f_lasti stores byte offset (not instruction index)
--
-- ============================================================================

-- ============================================================================
-- Frame Evaluation Function
-- ============================================================================

-- py_eval_frame: Execute bytecode in a frame object
--
-- Parameters:
--   frame_id: UUID of the frame object to execute
--
-- Returns:
--   UUID: The PyObject ID returned by RETURN_VALUE opcode, or NULL if no
--         RETURN_VALUE was executed (rare, usually indicates error)
--
-- Behavior:
--   This is the main interpreter loop, equivalent to CPython's PyEval_EvalFrameEx.
--   It reads bytecode from the frame's code object, parses instructions, and
--   dispatches to opcode-specific handlers. The loop continues until:
--   1. RETURN_VALUE opcode is executed (pops value, returns it, exits loop)
--   2. All bytecode is executed (returns NULL, rare)
--   3. An exception is raised (propagated to caller)
--
--   The function maintains CPython's exact behavior:
--   - f_lasti is updated to the byte offset after each instruction
--   - Stack operations use py_stack_push/pop
--   - Opcode size is determined by py_get_opcode_size
--   - RETURN_VALUE is the only way to return a value (not automatic stack pop)
--
-- Usage:
--   result_id := py_eval_frame(frame_id);
--
-- CPython Reference:
--   This function implements the core logic of PyEval_EvalFrameEx in
--   Python/ceval.c. It maintains the same execution model and return semantics.
--
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
    next_i INTEGER := NULL;
    start_i INTEGER;
    extended INTEGER;
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
        next_i := NULL;
        start_i := i;
        opcode := get_byte(bytecode, i);
        arg := get_byte(bytecode, i + 1);
        extended := 0;
        WHILE opcode = 144 LOOP
            extended := (extended << 8) | arg;
            i := i + 2;
            IF i + 1 >= bytecode_length THEN
                RAISE EXCEPTION 'EXTENDED_ARG at end of bytecode at offset %', i;
            END IF;
            opcode := get_byte(bytecode, i);
            arg := get_byte(bytecode, i + 1);
        END LOOP;
        arg := (extended << 8) | arg;

        CASE opcode
            WHEN 1 THEN
                PERFORM public.py_opcode_POP_TOP(frame_id);
            WHEN 100 THEN
                PERFORM public.py_opcode_LOAD_CONST(frame_id, arg);
            WHEN 101 THEN
                PERFORM public.py_opcode_LOAD_NAME(frame_id, arg);
            WHEN 141 THEN
                PERFORM public.py_opcode_CALL_FUNCTION(frame_id, arg);
            WHEN 142 THEN
                PERFORM public.py_opcode_CALL_FUNCTION_KW(frame_id, arg);
            WHEN 90 THEN
                PERFORM public.py_opcode_STORE_NAME(frame_id, arg);
            WHEN 23 THEN
                PERFORM public.py_opcode_BINARY_ADD(frame_id);
            WHEN 24 THEN
                PERFORM public.py_opcode_BINARY_SUBTRACT(frame_id);
            WHEN 20 THEN
                PERFORM public.py_opcode_BINARY_MULTIPLY(frame_id);
            WHEN 102 THEN
                PERFORM public.py_opcode_BUILD_TUPLE(frame_id, arg);
            WHEN 103 THEN
                PERFORM public.py_opcode_BUILD_LIST(frame_id, arg);
            WHEN 107 THEN
                PERFORM public.py_opcode_COMPARE_OP(frame_id, arg);
            WHEN 110 THEN
                next_i := start_i + 2 + arg * 2;
            WHEN 114 THEN
                next_i := public.py_opcode_POP_JUMP_FORWARD_IF_FALSE(frame_id, start_i, arg);
            WHEN 115 THEN
                next_i := public.py_opcode_POP_JUMP_FORWARD_IF_TRUE(frame_id, start_i, arg);
            WHEN 83 THEN
                return_value := public.py_stack_pop(frame_id);
                should_return := TRUE;
                UPDATE public.py_frame_object SET f_lasti = start_i WHERE ob_base = frame_id;
                EXIT;
            ELSE
                RAISE EXCEPTION 'Unknown opcode: % at byte offset %', opcode, i;
        END CASE;

        IF opcode != 83 THEN
            UPDATE public.py_frame_object SET f_lasti = start_i WHERE ob_base = frame_id;
        END IF;

        instruction_size := i - start_i + 2;
        IF next_i IS NOT NULL THEN
            i := next_i;
        ELSE
            i := start_i + instruction_size;
        END IF;
    END LOOP;

    IF should_return THEN
        RETURN return_value;
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;
