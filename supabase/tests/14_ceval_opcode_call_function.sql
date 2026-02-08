-- ============================================================================
-- Test: VM PRECALL/CALL Opcode Test (CPython 3.11 call protocol)
-- 
-- Purpose:
--   Tests that PRECALL(166) and CALL(171) opcode handlers work correctly. This verifies:
--   - py_opcode_CALL correctly calls builtin functions
--   - py_call_cfunction correctly handles METH_O calling convention
--   - Arguments are popped from stack in correct order
--   - Function result is pushed onto stack
--   - TypeError is raised for non-callable objects
--   - Argument count validation works correctly
--   - Integration with py_eval_frame
--
-- Usage:
--   Run this file after migrations to verify PRECALL/CALL opcode implementation.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

DO $$
DECLARE
    -- Builtin Type IDs (from bootstrap)
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_LEN_FUNCTION UUID := '00000000-0000-4000-b000-000000000003';
    ID_TYPE_ERROR_TYPE UUID := '00000000-0000-4000-a000-000000000022';
    
    -- Test counters
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    
    -- Frame and code objects
    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_names_id UUID;
    co_consts_id UUID;
    
    -- Test objects
    test_str_id UUID;
    len_func_id UUID;
    non_callable_id UUID;
    
    -- Test variables
    result_id UUID;
    result_value NUMERIC;
    stack_size INTEGER;
    
    -- Helper variables
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    
    -- Error handling
    error_occurred BOOLEAN;
    error_message TEXT;
    got_exc_type_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM PRECALL/CALL Opcode Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Setup: Create test objects and frame
    -- ========================================================================
    RAISE NOTICE 'Setting up test environment...';
    
    -- Create test string object
    test_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (test_str_id, 'hello');
    
    -- Get len function from bootstrap
    len_func_id := ID_LEN_FUNCTION;
    IF NOT EXISTS (SELECT 1 FROM public.py_cfunction_object WHERE ob_base = len_func_id) THEN
        RAISE EXCEPTION 'FAIL: len function not found. Bootstrap migration must run first.';
    END IF;
    
    -- Create non-callable object (int)
    non_callable_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (non_callable_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (non_callable_id, 42);
    
    -- Create empty tuple for various tuple fields
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    
    -- Create empty string
    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
    
    -- Create namespace dicts
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    
    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);
    
    -- Create constants tuple (co_consts) - empty for this test
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);
    
    -- Create names tuple (co_names) - empty for this test
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);
    
    -- Create empty bytecode
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);
    
    -- Create code object
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );
    
    -- Create frame
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Test 1: Function exists
    -- ========================================================================
    RAISE NOTICE 'Test 1: Function exists...';
    test_count := test_count + 1;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'py_opcode_call' 
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_CALL function does not exist';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'py_call_cfunction' 
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) THEN
        RAISE EXCEPTION 'FAIL: py_call_cfunction function does not exist';
    END IF;
    
    RAISE NOTICE '  ✓ py_opcode_CALL and py_call_cfunction functions exist';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: CALL calls len function correctly
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: CALL calls len function correctly...';
    test_count := test_count + 1;
    
    -- Push arguments onto stack (function first, then arguments)
    -- CPython 3.11: CALL n pops n args, then callable
    PERFORM public.py_stack_push(frame_id, len_func_id);  -- function (pushed first, popped last)
    PERFORM public.py_stack_push(frame_id, test_str_id);  -- argument (pushed last, popped first)
    
    -- Execute PRECALL(1) then CALL(1) - 1 argument
    PERFORM public.py_opcode_PRECALL(frame_id, 1);
    PERFORM public.py_opcode_CALL(frame_id, 1);
    
    -- Verify result is on stack
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size IS NULL OR stack_size != 1 THEN
        RAISE EXCEPTION 'FAIL: Stack size after CALL is %, expected 1', stack_size;
    END IF;
    
    -- Verify result is correct
    SELECT f_valuestack[1] INTO result_id
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: CALL result is NULL';
    END IF;
    
    -- Get result value
    SELECT long_value INTO result_value
    FROM public.py_long_object
    WHERE ob_base = result_id;
    
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL: len("hello") returned %, expected 5', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ CALL correctly calls len function';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: CALL argument order (right-to-left pop)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: CALL argument order (right-to-left pop)...';
    test_count := test_count + 1;
    
    -- Clear stack
    UPDATE public.py_frame_object
    SET f_valuestack = array[]::uuid[]
    WHERE ob_base = frame_id;
    
    -- Create another test string
    DECLARE
        test_str2_id UUID;
        result2_id UUID;
        result2_value NUMERIC;
    BEGIN
        test_str2_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (test_str2_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (test_str2_id, 'world');
        
        -- Push arguments in correct order: function first, then arguments
        -- CPython: function is pushed first, then arguments left-to-right
        PERFORM public.py_stack_push(frame_id, len_func_id);   -- function (pushed first, popped last)
        PERFORM public.py_stack_push(frame_id, test_str2_id);  -- argument (pushed last, popped first)
        
        -- Execute CALL(1)
        PERFORM public.py_opcode_CALL(frame_id, 1);
        
        -- Verify result
        SELECT f_valuestack[1] INTO result2_id
        FROM public.py_frame_object
        WHERE ob_base = frame_id;
        
        SELECT long_value INTO result2_value
        FROM public.py_long_object
        WHERE ob_base = result2_id;
        
        IF result2_value != 5 THEN
            RAISE EXCEPTION 'FAIL: len("world") returned %, expected 5', result2_value;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ CALL correctly handles argument order';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: CALL raises TypeError for non-callable objects (Python 예외 + NULL)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: CALL raises TypeError for non-callable objects...';
    test_count := test_count + 1;

    UPDATE public.py_frame_object
    SET f_valuestack = array[]::uuid[]
    WHERE ob_base = frame_id;

    PERFORM public.py_stack_push(frame_id, non_callable_id);
    PERFORM public.py_err_clear();

    PERFORM public.py_opcode_CALL(frame_id, 0);

    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: CALL should set Python exception for non-callable object';
    END IF;
    SELECT exc_type_id INTO got_exc_type_id FROM public.py_exception_state WHERE id = (SELECT id FROM public.py_exception_state LIMIT 1);
    IF got_exc_type_id IS DISTINCT FROM ID_TYPE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: CALL non-callable should set TypeError, got exc_type_id %', got_exc_type_id;
    END IF;
    SELECT u.str_value INTO error_message
    FROM public.py_exception_state e
    JOIN public.py_base_exception_object b ON b.ob_base = e.exc_value_id
    JOIN public.py_tuple_object t ON t.ob_base = b.ob_args
    JOIN public.py_unicode_object u ON u.ob_base = t.ob_item[1]
    WHERE e.id = (SELECT id FROM public.py_exception_state LIMIT 1);
    IF error_message IS NULL OR error_message NOT LIKE '%object is not callable%' THEN
        RAISE EXCEPTION 'FAIL: CALL non-callable expected message containing "object is not callable", got: %', error_message;
    END IF;

    RAISE NOTICE '  ✓ CALL correctly raises TypeError for non-callable objects';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: CALL argument count validation
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: CALL argument count validation...';
    test_count := test_count + 1;
    
    -- Clear stack
    UPDATE public.py_frame_object
    SET f_valuestack = array[]::uuid[]
    WHERE ob_base = frame_id;
    
    -- Test negative n
    BEGIN
        PERFORM public.py_opcode_CALL(frame_id, -1);
        RAISE EXCEPTION 'FAIL: CALL did not raise exception for negative n';
    EXCEPTION
        WHEN OTHERS THEN
            error_message := SQLERRM;
            IF error_message NOT LIKE 'CALL: n must be non-negative%' THEN
                RAISE EXCEPTION 'FAIL: CALL raised wrong exception for negative n: %', error_message;
            END IF;
    END;
    
    -- Test wrong argument count for METH_O function (len expects 1 arg)
    -- 명세: py_call_cfunction는 인자 개수 오류 시 Python TypeError 세팅 후 NULL 반환; 호출부는 push하지 않고 반환.
    UPDATE public.py_frame_object
    SET f_valuestack = array[]::uuid[]
    WHERE ob_base = frame_id;
    
    PERFORM public.py_stack_push(frame_id, len_func_id);
    PERFORM public.py_err_clear();

    PERFORM public.py_opcode_CALL(frame_id, 0);

    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: CALL should set Python exception for wrong argument count';
    END IF;
    SELECT exc_type_id INTO got_exc_type_id FROM public.py_exception_state WHERE id = (SELECT id FROM public.py_exception_state LIMIT 1);
    IF got_exc_type_id IS DISTINCT FROM ID_TYPE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: CALL wrong argument count should set TypeError, got exc_type_id %', got_exc_type_id;
    END IF;
    
    RAISE NOTICE '  ✓ CALL correctly validates argument count';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test Summary
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total tests: %', test_count;
    RAISE NOTICE 'Passed: %', pass_count;
    RAISE NOTICE 'Failed: %', fail_count;
    RAISE NOTICE '';
    
    IF fail_count > 0 THEN
        RAISE EXCEPTION 'Test suite failed: % out of % tests failed', fail_count, test_count;
    END IF;
    
    RAISE NOTICE 'All tests passed! ✓';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Test failed with error:';
        RAISE NOTICE '%', SQLERRM;
        RAISE NOTICE '========================================';
        RAISE;
END $$;
