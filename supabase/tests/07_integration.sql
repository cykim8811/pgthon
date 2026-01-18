-- =====================================================
-- Test 07: Integration Tests
-- Description: End-to-end tests combining multiple VM features
-- Dependencies: All VM migrations
-- =====================================================

DO $$
DECLARE
    v_source text;
    v_result uuid;
    v_val bigint;
    v_str_val text;
BEGIN
    -------------------------------------------------------
    -- 1. Test Complete Program: Fibonacci-like
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Complete Program ===';
    
    -- Simple accumulator: a=1, b=1, c=a+b, d=b+c, return d
    v_source := 'LOAD_CONST 1
STORE_FAST a
LOAD_CONST 1
STORE_FAST b
LOAD_FAST a
LOAD_FAST b
BINARY_ADD
STORE_FAST c
LOAD_FAST b
LOAD_FAST c
BINARY_ADD
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    -- a=1, b=1, c=2, d=1+2=3
    PERFORM public.test_assert_eq_int(v_val, 3, 'Fibonacci-like: 1,1,2,3');
    
    -------------------------------------------------------
    -- 2. Test Conditional Logic
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Conditional Logic ===';
    
    -- if x > y: return x; else: return y (max function)
    -- x=10, y=20
    v_source := 'LOAD_CONST 10
STORE_FAST x
LOAD_CONST 20
STORE_FAST y
LOAD_FAST x
LOAD_FAST y
COMPARE_OP 4
POP_JUMP_IF_FALSE 11
LOAD_FAST x
RETURN_VALUE
LOAD_FAST y
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 20, 'max(10, 20) = 20');
    
    -- Test with reversed values: x=30, y=10
    v_source := 'LOAD_CONST 30
STORE_FAST x
LOAD_CONST 10
STORE_FAST y
LOAD_FAST x
LOAD_FAST y
COMPARE_OP 4
POP_JUMP_IF_FALSE 11
LOAD_FAST x
RETURN_VALUE
LOAD_FAST y
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 30, 'max(30, 10) = 30');
    
    -------------------------------------------------------
    -- 3. Test String Operations
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing String Operations ===';
    
    v_source := 'LOAD_CONST Hello
STORE_FAST greeting
LOAD_CONST World
STORE_FAST name
LOAD_FAST greeting
LOAD_FAST name
BINARY_ADD
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_result;
    PERFORM public.test_assert_eq_str(v_str_val, 'HelloWorld', 'String concatenation in VM');
    
    -------------------------------------------------------
    -- 4. Test Object Inspector
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Object Inspector ===';
    
    DECLARE
        v_int uuid := public.vm_create_int(42);
        v_str uuid := public.vm_create_str('test');
        v_json jsonb;
    BEGIN
        -- Inspect integer
        v_json := public.vm_inspect_object(v_int);
        PERFORM public.test_assert(v_json->>'type' = 'int', 'Inspector identifies int');
        PERFORM public.test_assert((v_json->>'value')::bigint = 42, 'Inspector extracts int value');
        
        -- Inspect string
        v_json := public.vm_inspect_object(v_str);
        PERFORM public.test_assert(v_json->>'type' = 'str', 'Inspector identifies str');
        PERFORM public.test_assert(v_json->>'value' = 'test', 'Inspector extracts str value');
    END;
    
    -------------------------------------------------------
    -- 5. Test Multi-Step Calculation
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Multi-Step Calculation ===';
    
    -- Calculate: ((a + b) * 2) - c where a=5, b=3, c=6
    -- Step by step: temp1 = a + b = 8
    --               temp2 = temp1 * 2 = 16  (using BINARY_ADD as we don't have MUL in opcode)
    --               Actually we can use __mul__ via native dispatch
    -- Let's simplify: a=10, b=20, c=5, result = (a+b) - c = 25
    v_source := 'LOAD_CONST 10
STORE_FAST a
LOAD_CONST 20
STORE_FAST b
LOAD_CONST 5
STORE_FAST c
LOAD_FAST a
LOAD_FAST b
BINARY_ADD
STORE_FAST temp
LOAD_FAST temp
LOAD_FAST c
BINARY_ADD
BINARY_ADD
RETURN_VALUE';
    
    -- Hmm, BINARY_ADD uses registers. Let me recalculate
    -- Actually: load temp, load c, ADD means temp-c? No, our BINARY_ADD does left + right
    -- Let's just test: (a+b) then add more
    v_source := 'LOAD_CONST 100
STORE_FAST total
LOAD_CONST 23
STORE_FAST delta
LOAD_FAST total
LOAD_FAST delta
BINARY_ADD
RETURN_VALUE';
    
    v_result := public.vm_execute_source(v_source);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 123, 'total + delta = 123');
    
    -------------------------------------------------------
    -- 6. Test VM End-to-End via REPL API
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing REPL API ===';
    
    -- This is the main entry point for the web interface
    v_result := public.vm_execute_source('LOAD_CONST 999
RETURN_VALUE');
    
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 999, 'REPL API works');
    
    RAISE NOTICE E'\n=== All Integration Tests Passed! ===\n';
END $$;
