-- ============================================================================
-- py_eval_frame with exception dispatch (CPython 3.11)
-- 20260114241100_python_exception_setters.sql
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md
-- py_str_from_text, py_err_set_type_error 등 setters는 20260114224300_exception_setters.sql 로 이동 (의존성 순서).
-- 이 파일에는 py_eval_frame 재정의만 유지 (예외 발생 시 py_traceback_here + exception table 조회).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- py_eval_frame: after each opcode, if py_err_occurred() then traceback + exception table lookup
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_eval_frame(frame_id UUID)
RETURNS UUID AS $$
DECLARE
    code_obj_id UUID;
    co_code_id UUID;
    bytecode bytea;
    exc_table bytea;
    opcode INTEGER;
    arg INTEGER;
    i INTEGER := 0;
    instruction_size INTEGER;
    return_value UUID := NULL;
    should_return BOOLEAN := FALSE;
    bytecode_length INTEGER;
    next_i INTEGER := NULL;
    handler_target integer;
    handler_depth integer;
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

    SELECT co_exceptiontable INTO exc_table FROM public.py_code_object WHERE ob_base = code_obj_id;

    bytecode_length := length(bytecode);

    WHILE i < bytecode_length LOOP
        next_i := NULL;
        opcode := get_byte(bytecode, i);
        arg := get_byte(bytecode, i + 1);

        CASE opcode
            WHEN 1 THEN
                PERFORM public.py_opcode_POP_TOP(frame_id);
            WHEN 100 THEN
                PERFORM public.py_opcode_LOAD_CONST(frame_id, arg);
            WHEN 101 THEN
                PERFORM public.py_opcode_LOAD_NAME(frame_id, arg);
            WHEN 141 THEN
                PERFORM public.py_opcode_CALL_FUNCTION(frame_id, arg);
            WHEN 90 THEN
                PERFORM public.py_opcode_STORE_NAME(frame_id, arg);
            WHEN 23 THEN
                PERFORM public.py_opcode_BINARY_ADD(frame_id);
            WHEN 24 THEN
                PERFORM public.py_opcode_BINARY_SUBTRACT(frame_id);
            WHEN 20 THEN
                PERFORM public.py_opcode_BINARY_MULTIPLY(frame_id);
            WHEN 107 THEN
                PERFORM public.py_opcode_COMPARE_OP(frame_id, arg);
            WHEN 110 THEN
                next_i := i + 2 + arg * 2;
            WHEN 114 THEN
                next_i := public.py_opcode_POP_JUMP_FORWARD_IF_FALSE(frame_id, i, arg);
            WHEN 115 THEN
                next_i := public.py_opcode_POP_JUMP_FORWARD_IF_TRUE(frame_id, i, arg);
            WHEN 35 THEN
                PERFORM public.py_opcode_PUSH_EXC_INFO(frame_id);
            WHEN 36 THEN
                PERFORM public.py_opcode_CHECK_EXC_MATCH(frame_id);
            WHEN 83 THEN
                return_value := public.py_stack_pop(frame_id);
                should_return := TRUE;
                UPDATE public.py_frame_object SET f_lasti = i WHERE ob_base = frame_id;
                EXIT;
            WHEN 89 THEN
                PERFORM public.py_opcode_POP_EXCEPT(frame_id);
            WHEN 119 THEN
                PERFORM public.py_opcode_RERAISE(frame_id);
            WHEN 130 THEN
                PERFORM public.py_opcode_RAISE_VARARGS(frame_id, arg);
            ELSE
                RAISE EXCEPTION 'Unknown opcode: % at byte offset %', opcode, i;
        END CASE;

        IF public.py_err_occurred() THEN
            PERFORM public.py_traceback_here(frame_id, i);
            IF exc_table IS NOT NULL AND length(exc_table) > 0 THEN
                SELECT h.target_offset, h.depth INTO handler_target, handler_depth
                FROM public.py_get_exception_handler(exc_table, i / 2) h;
                IF FOUND THEN
                    PERFORM public.py_stack_trim(frame_id, handler_depth);
                    next_i := handler_target * 2;
                ELSE
                    RETURN NULL;
                END IF;
            ELSE
                RETURN NULL;
            END IF;
        END IF;

        IF opcode != 83 THEN
            UPDATE public.py_frame_object SET f_lasti = i WHERE ob_base = frame_id;
        END IF;

        instruction_size := public.py_get_opcode_size(opcode);
        IF next_i IS NOT NULL THEN
            i := next_i;
        ELSE
            i := i + instruction_size;
        END IF;
    END LOOP;

    IF should_return THEN
        RETURN return_value;
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;
