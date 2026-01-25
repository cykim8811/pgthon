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
    bytecode bytea;  -- bytes object의 bytes_value
    opcode INTEGER;
    arg INTEGER;
    i INTEGER := 0;
    instruction_size INTEGER;
    return_value UUID := NULL;
    should_return BOOLEAN := FALSE;
    bytecode_length INTEGER;
BEGIN
    -- Validate frame exists
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    
    -- 1. Frame에서 code object 가져오기
    SELECT f_code INTO code_obj_id
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'Frame with id % does not have a code object', frame_id;
    END IF;
    
    -- 2. Code object에서 bytecode 가져오기
    SELECT co_code INTO co_code_id
    FROM public.py_code_object
    WHERE ob_base = code_obj_id;
    
    IF co_code_id IS NULL THEN
        RAISE EXCEPTION 'Code object with id % does not have co_code', code_obj_id;
    END IF;
    
    SELECT bytes_value INTO bytecode
    FROM public.py_bytes_object
    WHERE ob_base = co_code_id;
    
    IF bytecode IS NULL THEN
        RAISE EXCEPTION 'Bytes object with id % does not have bytes_value', co_code_id;
    END IF;
    
    bytecode_length := length(bytecode);
    
    -- 3. Bytecode 실행 루프
    -- CPython의 PyEval_EvalFrameEx와 동일하게, RETURN_VALUE opcode에서만 반환하고 루프 종료
    WHILE i < bytecode_length LOOP
        -- Opcode 읽기 (1바이트)
        opcode := get_byte(bytecode, i);  -- get_byte uses 0-based indexing
        
        -- Operand 읽기 (1바이트, 나중에 EXTENDED_ARG 지원 시 확장 가능)
        arg := get_byte(bytecode, i + 1);
        
        -- Opcode dispatch
        -- Note: Only implemented opcodes are dispatched here.
        -- Unimplemented opcodes will raise "Unknown opcode" exception.
        CASE opcode
            WHEN 100 THEN  -- LOAD_CONST
                PERFORM public.py_opcode_LOAD_CONST(frame_id, arg);
            WHEN 83 THEN   -- RETURN_VALUE
                -- CPython: PyEval_EvalFrameEx returns the value on top of the stack
                -- when RETURN_VALUE opcode is executed
                return_value := public.py_stack_pop(frame_id);
                should_return := TRUE;
                -- f_lasti 업데이트 (RETURN_VALUE instruction의 byte offset)
                UPDATE public.py_frame_object
                SET f_lasti = i
                WHERE ob_base = frame_id;
                EXIT;  -- 루프 종료 (CPython과 동일)
            -- TODO: Implement the following opcodes:
            --   - 101 (LOAD_NAME): Load name from namespace
            --   - 23 (BINARY_ADD): Binary addition operation
            --   - ... (other opcodes to be added)
            ELSE
                RAISE EXCEPTION 'Unknown opcode: % at byte offset %', opcode, i;
        END CASE;
        
        -- f_lasti 업데이트 (byte offset)
        -- CPython의 f_lasti는 byte offset을 저장합니다 (instruction index가 아님)
        -- RETURN_VALUE의 경우 위에서 이미 업데이트했으므로 여기서는 건너뜀
        IF opcode != 83 THEN
            UPDATE public.py_frame_object
            SET f_lasti = i
            WHERE ob_base = frame_id;
        END IF;
        
        -- 다음 instruction으로 이동
        instruction_size := public.py_get_opcode_size(opcode);
        i := i + instruction_size;
    END LOOP;
    
    -- 4. 반환값 처리
    -- CPython: PyEval_EvalFrameEx returns the value popped by RETURN_VALUE,
    -- or NULL if no RETURN_VALUE was executed (rare, usually indicates error)
    IF should_return THEN
        RETURN return_value;
    ELSE
        -- 모든 bytecode 실행 완료 (일반적이지 않음, 보통 RETURN_VALUE가 있어야 함)
        -- CPython에서는 이런 경우 NULL을 반환하거나 예외가 발생함
        RETURN NULL;  -- 또는 None 객체 (나중에 None 객체 구현 시 변경)
    END IF;
END;
$$ LANGUAGE plpgsql;
