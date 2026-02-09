-- ============================================================================
-- py_eval_frame 정의 (예외 디스패치 포함, CPython 3.11)
-- 20260114241100_ceval_eval_frame.sql
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md, docs/BYTECODE_ENCODING_3_11.md
-- Bytecode: wordcode (2 bytes per instruction, 0-based byte offset). CACHE(0) = skip 2 bytes.
-- 241000에서 예외 디스패치·헬퍼를 정의하고, 이 파일에서 py_eval_frame을 정의.
-- 예외 발생 시 py_traceback_here + exception table 조회 → 핸들러 점프 또는 전파.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- py_eval_frame: CPython-faithful — only dispatch when *this* opcode set the exception.
-- Before opcode: had_err := py_err_occurred(). After opcode: if NOT had_err AND py_err_occurred()
-- then traceback + exception table lookup (so handler runs without re-dispatching).
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
    had_err BOOLEAN;
    start_i INTEGER;
    extended INTEGER;
    pending_kw_names_const_i INTEGER := NULL;
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
        had_err := public.py_err_occurred();
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
            WHEN 0 THEN
                NULL;  -- CACHE (3.11): 2-byte no-op, do not update f_lasti
            WHEN 9 THEN
                NULL;  -- NOP (3.11): no-op; f_lasti updated below (unlike CACHE)
            WHEN 1 THEN
                PERFORM public.py_opcode_POP_TOP(frame_id);
            WHEN 2 THEN
                PERFORM public.py_opcode_PUSH_NULL(frame_id);
            WHEN 100 THEN
                PERFORM public.py_opcode_LOAD_CONST(frame_id, arg);
            WHEN 101 THEN
                PERFORM public.py_opcode_LOAD_NAME(frame_id, arg);
            WHEN 116 THEN
                PERFORM public.py_opcode_LOAD_GLOBAL(frame_id, arg);
            WHEN 124 THEN
                PERFORM public.py_opcode_LOAD_FAST(frame_id, arg);
            WHEN 125 THEN
                PERFORM public.py_opcode_STORE_FAST(frame_id, arg);
            WHEN 126 THEN
                PERFORM public.py_opcode_DELETE_FAST(frame_id, arg);
            WHEN 166 THEN
                PERFORM public.py_opcode_PRECALL(frame_id, arg);
            WHEN 171 THEN
                PERFORM public.py_opcode_CALL(frame_id, arg, pending_kw_names_const_i);
                pending_kw_names_const_i := NULL;
            WHEN 172 THEN
                pending_kw_names_const_i := arg;
            WHEN 90 THEN
                PERFORM public.py_opcode_STORE_NAME(frame_id, arg);
            WHEN 95 THEN
                PERFORM public.py_opcode_STORE_ATTR(frame_id, arg);
            WHEN 96 THEN
                PERFORM public.py_opcode_DELETE_ATTR(frame_id, arg);
            WHEN 97 THEN
                PERFORM public.py_opcode_STORE_GLOBAL(frame_id, arg);
            WHEN 98 THEN
                PERFORM public.py_opcode_DELETE_GLOBAL(frame_id, arg);
            WHEN 120 THEN
                PERFORM public.py_opcode_COPY(frame_id, arg);
            WHEN 10 THEN
                PERFORM public.py_opcode_UNARY_POSITIVE(frame_id);
            WHEN 11 THEN
                PERFORM public.py_opcode_UNARY_NEGATIVE(frame_id);
            WHEN 12 THEN
                PERFORM public.py_opcode_UNARY_NOT(frame_id);
            WHEN 23 THEN
                PERFORM public.py_opcode_BINARY_ADD(frame_id);
            WHEN 24 THEN
                PERFORM public.py_opcode_BINARY_SUBTRACT(frame_id);
            WHEN 25 THEN
                PERFORM public.py_opcode_BINARY_SUBSCR(frame_id);
            WHEN 60 THEN
                PERFORM public.py_opcode_STORE_SUBSCR(frame_id);
            WHEN 61 THEN
                PERFORM public.py_opcode_DELETE_SUBSCR(frame_id);
            WHEN 133 THEN
                PERFORM public.py_opcode_BUILD_SLICE(frame_id, arg);
            WHEN 20 THEN
                PERFORM public.py_opcode_BINARY_MULTIPLY(frame_id);
            WHEN 122 THEN
                PERFORM public.py_opcode_BINARY_OP(frame_id, arg);
            WHEN 102 THEN
                PERFORM public.py_opcode_BUILD_TUPLE(frame_id, arg);
            WHEN 103 THEN
                PERFORM public.py_opcode_BUILD_LIST(frame_id, arg);
            WHEN 105 THEN
                PERFORM public.py_opcode_BUILD_MAP(frame_id, arg);
            WHEN 82 THEN
                PERFORM public.py_opcode_LIST_TO_TUPLE(frame_id);
            WHEN 92 THEN
                PERFORM public.py_opcode_UNPACK_SEQUENCE(frame_id, arg);
            WHEN 118 THEN
                PERFORM public.py_opcode_CONTAINS_OP(frame_id, arg);
            WHEN 106 THEN
                PERFORM public.py_opcode_LOAD_ATTR(frame_id, arg);
            WHEN 160 THEN
                PERFORM public.py_opcode_LOAD_METHOD(frame_id, arg);
            WHEN 107 THEN
                PERFORM public.py_opcode_COMPARE_OP(frame_id, arg);
            WHEN 117 THEN
                PERFORM public.py_opcode_IS_OP(frame_id, arg);
            WHEN 110 THEN
                next_i := start_i + 2 + arg * 2;
            WHEN 140 THEN
                next_i := arg * 2;  -- JUMP_BACKWARD (3.11): oparg = target instruction offset (bytes = arg*2)
            WHEN 114 THEN
                next_i := public.py_opcode_POP_JUMP_FORWARD_IF_FALSE(frame_id, start_i, arg);
            WHEN 115 THEN
                next_i := public.py_opcode_POP_JUMP_FORWARD_IF_TRUE(frame_id, start_i, arg);
            WHEN 111 THEN
                next_i := public.py_opcode_JUMP_IF_FALSE_OR_POP(frame_id, start_i, arg);
            WHEN 112 THEN
                next_i := public.py_opcode_JUMP_IF_TRUE_OR_POP(frame_id, start_i, arg);
            WHEN 128 THEN
                next_i := public.py_opcode_POP_JUMP_FORWARD_IF_NONE(frame_id, start_i, arg);
            WHEN 129 THEN
                next_i := public.py_opcode_POP_JUMP_FORWARD_IF_NOT_NONE(frame_id, start_i, arg);
            WHEN 173 THEN
                next_i := public.py_opcode_POP_JUMP_BACKWARD_IF_NONE(frame_id, arg);
            WHEN 174 THEN
                next_i := public.py_opcode_POP_JUMP_BACKWARD_IF_NOT_NONE(frame_id, arg);
            WHEN 175 THEN
                next_i := public.py_opcode_POP_JUMP_BACKWARD_IF_FALSE(frame_id, arg);
            WHEN 176 THEN
                next_i := public.py_opcode_POP_JUMP_BACKWARD_IF_TRUE(frame_id, arg);
            WHEN 151 THEN
                PERFORM public.py_opcode_RESUME(frame_id, arg);
            WHEN 35 THEN
                PERFORM public.py_opcode_PUSH_EXC_INFO(frame_id);
            WHEN 36 THEN
                PERFORM public.py_opcode_CHECK_EXC_MATCH(frame_id);
            WHEN 83 THEN
                return_value := public.py_stack_pop(frame_id);
                should_return := TRUE;
                UPDATE public.py_frame_object SET f_lasti = start_i WHERE ob_base = frame_id;
                EXIT;
            WHEN 89 THEN
                PERFORM public.py_opcode_POP_EXCEPT(frame_id);
            WHEN 119 THEN
                PERFORM public.py_opcode_RERAISE(frame_id);
            WHEN 130 THEN
                PERFORM public.py_opcode_RAISE_VARARGS(frame_id, arg);
            WHEN 132 THEN
                PERFORM public.py_opcode_MAKE_FUNCTION(frame_id, arg);
            WHEN 68 THEN
                PERFORM public.py_opcode_GET_ITER(frame_id);
            WHEN 93 THEN
                next_i := public.py_opcode_FOR_ITER(frame_id, start_i, arg);
            WHEN 135 THEN
                PERFORM public.py_opcode_MAKE_CELL(frame_id, arg);
            WHEN 136 THEN
                PERFORM public.py_opcode_LOAD_CLOSURE(frame_id, arg);
            WHEN 137 THEN
                PERFORM public.py_opcode_LOAD_DEREF(frame_id, arg);
            WHEN 138 THEN
                PERFORM public.py_opcode_STORE_DEREF(frame_id, arg);
            WHEN 139 THEN
                PERFORM public.py_opcode_DELETE_DEREF(frame_id, arg);
            WHEN 149 THEN
                PERFORM public.py_opcode_COPY_FREE_VARS(frame_id, arg);
            WHEN 71 THEN
                PERFORM public.py_opcode_LOAD_BUILD_CLASS(frame_id);
            ELSE
                RAISE EXCEPTION 'Unknown opcode: % at byte offset %', opcode, i;
        END CASE;

        IF NOT had_err AND public.py_err_occurred() THEN
            PERFORM public.py_traceback_here(frame_id, start_i);
            IF exc_table IS NOT NULL AND length(exc_table) > 0 THEN
                SELECT h.target_offset, h.depth INTO handler_target, handler_depth
                FROM public.py_get_exception_handler(exc_table, start_i / 2) h;
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

        IF opcode != 83 AND opcode != 0 THEN
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
