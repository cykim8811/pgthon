-- =====================================================
-- Test 05: VM Bytecode Execution
-- Description: Test bytecode assembler and interpreter with full programs
-- Dependencies: Migrations 11-12 (vm_interpreter, vm_assembler)
-- =====================================================

DO $$
DECLARE
    v_source text;
    v_result uuid;
    v_val bigint;
BEGIN
    -------------------------------------------------------
    -- 1. Test Simple Constant Return
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Simple Constant Return ===';
    
    v_source := 'LOAD_CONST 42
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 42, 'LOAD_CONST 42; RETURN_VALUE = 42');
    
    -------------------------------------------------------
    -- 2. Test Variables (LOAD_FAST, STORE_FAST)
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Variables ===';
    
    v_source := 'LOAD_CONST 100
STORE_FAST x
LOAD_FAST x
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 100, 'x = 100; return x');
    
    -------------------------------------------------------
    -- 3. Test Binary Addition
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Binary Addition ===';
    
    v_source := 'LOAD_CONST 10
STORE_FAST a
LOAD_CONST 20
STORE_FAST b
LOAD_FAST a
LOAD_FAST b
BINARY_ADD
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 30, 'a=10; b=20; return a+b = 30');
    
    -- Chained addition
    v_source := 'LOAD_CONST 1
LOAD_CONST 2
BINARY_ADD
LOAD_CONST 3
BINARY_ADD
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 6, '1 + 2 + 3 = 6');
    
    -------------------------------------------------------
    -- 4. Test Comparisons
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Comparisons ===';
    
    -- 10 < 20 should be True (value 1)
    v_source := 'LOAD_CONST 10
LOAD_CONST 20
COMPARE_OP 0
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 1, '10 < 20 returns True (1)');
    
    -- 10 > 20 should be False (value 0)
    v_source := 'LOAD_CONST 10
LOAD_CONST 20
COMPARE_OP 4
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 0, '10 > 20 returns False (0)');
    
    -------------------------------------------------------
    -- 5. Test Conditional Jumps
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Conditional Jumps ===';
    
    -- If 10 > 20 (False), jump to line 7, return 200
    v_source := 'LOAD_CONST 10
LOAD_CONST 20
COMPARE_OP 4
POP_JUMP_IF_FALSE 7
LOAD_CONST 100
RETURN_VALUE
LOAD_CONST 200
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 200, 'Jump if false (10 > 20) → 200');
    
    -- If 10 < 20 (True), don't jump, return 100
    v_source := 'LOAD_CONST 10
LOAD_CONST 20
COMPARE_OP 0
POP_JUMP_IF_FALSE 7
LOAD_CONST 100
RETURN_VALUE
LOAD_CONST 200
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 100, 'No jump if true (10 < 20) → 100');
    
    -------------------------------------------------------
    -- 6. Test Complex Expression
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Complex Expression ===';
    
    -- (5 + 3) * 2 = 16
    v_source := 'LOAD_CONST 5
LOAD_CONST 3
BINARY_ADD
STORE_FAST temp
LOAD_FAST temp
LOAD_CONST 2
BINARY_ADD
BINARY_ADD
RETURN_VALUE';
    
    -- Actually let's simplify: a = 5; b = 3; c = a + b; d = c + 2; return d
    v_source := 'LOAD_CONST 5
STORE_FAST a
LOAD_CONST 3
STORE_FAST b
LOAD_FAST a
LOAD_FAST b
BINARY_ADD
STORE_FAST c
LOAD_FAST c
LOAD_CONST 2
BINARY_ADD
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 10, '(5 + 3) + 2 = 10');
    
    RAISE NOTICE E'\n=== All Bytecode Execution Tests Passed! ===\n';
END $$;
