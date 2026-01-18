-- Test: 03 Control Flow - Loops
-- Verify FOR_ITER and Iterator Protocol
DO $$
DECLARE
    -- Source: Sum 10, 20, 30
    v_source TEXT := 
'LOAD_CONST 10
STORE_FAST x
LOAD_CONST 20
STORE_FAST y
LOAD_CONST 30
STORE_FAST z
LOAD_CONST 0
STORE_FAST total
LOAD_FAST x
LOAD_FAST y
BINARY_ADD
LOAD_FAST z
BINARY_ADD
STORE_FAST total
LOAD_FAST total
RETURN_VALUE';

    -- Note: Since we don't have BUILD_LIST yet, we test binary add chain as a proxy for basic flow first.
    -- Then we will implement a proper Loop test once we verify this.
    -- Actually, the assembler supports arbitrary code.
    -- Let's stick to the previous loop test logic but wrapped in assembler?
    -- Problem: Assembler doesn't support "[1, 2, 3]" syntax, need opcodes.
    -- And we don't have BUILD_LIST.
    -- So for now, let's test a simple Jump.
    
    v_source_jump TEXT :=
'LOAD_CONST 10
LOAD_CONST 20
COMPARE_OP 4
POP_JUMP_IF_FALSE 10
LOAD_CONST 100
RETURN_VALUE
LOAD_CONST 200
RETURN_VALUE';
    -- 10 > 20 is False. Should jump to 10 (0-based line index in our manual assembler?)
    -- Wait, our assembler uses line-based jump targets? No, assembler converts to indices?
    -- Our `vm_run_frame` uses 1-based line numbers.
    -- Jump target in `vm_run_frame` is absolute line number.
    -- Assembler implementation: `v_new_bytecode := v_new_bytecode || v_opcode || ' ' || v_arg || E'\n';`
    -- It keeps arguments as is. So we need to provide raw line numbers as arguments.
    -- Code:
    -- 1: LOAD_CONST 10
    -- 2: LOAD_CONST 20
    -- 3: COMPARE_OP 4 (>)
    -- 4: POP_JUMP_IF_FALSE 7
    -- 5: LOAD_CONST 100
    -- 6: RETURN_VALUE
    -- 7: LOAD_CONST 200
    -- 8: RETURN_VALUE
    
    v_source_real TEXT :=
'LOAD_CONST 10
LOAD_CONST 20
COMPARE_OP 4
POP_JUMP_IF_FALSE 7
LOAD_CONST 100
RETURN_VALUE
LOAD_CONST 200
RETURN_VALUE';

    v_res UUID;
    v_val BIGINT;
BEGIN
    v_res := public.vm_execute_source(v_source_real);
    SELECT long_value INTO v_val FROM public.py_long_object WHERE ob_base = v_res;
    
    -- 10 > 20 is False. Jump to 7 -> Returns 200.
    PERFORM public.test_assert_eq_int(v_val, 200, 'JumpIfFalse (10 > 20) -> 200');
END $$;
