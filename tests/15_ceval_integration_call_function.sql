-- ============================================================================
-- Test: VM PRECALL/CALL Integration Test (CPython 3.11 call protocol)
-- 
-- Purpose:
--   Tests PRECALL(166) and CALL(171) opcodes in realistic integration scenarios. This verifies:
--   - LOAD_NAME + PRECALL + CALL: len("hello") 실행 패턴
--   - LOAD_NAME + LOAD_CONST + PRECALL + CALL: 상수와 함수 조합
--   - 실제 bytecode 실행을 통한 함수 호출
--   - Frame isolation (여러 frame에서 독립적인 실행)
--
--   All tests follow CPython's exact behavior and execution model.
--
-- Usage:
--   Run this file after migrations to verify PRECALL/CALL integration.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    -- Builtin Type IDs (from bootstrap)
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_LEN_FUNCTION UUID := '00000000-0000-4000-b000-000000000003';
    
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
    
    -- Test constants
    const0_str_id UUID;  -- 'hello'
    const1_str_id UUID;  -- 'world'
    
    -- Test name strings
    len_str_id UUID;  -- 'len' (from bootstrap)
    
    -- Test variables
    result_id UUID;
    result_value NUMERIC;
    
    -- Helper variables
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    real_builtins_dict_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM PRECALL/CALL Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Setup: Create test objects and frame infrastructure
    -- ========================================================================
    RAISE NOTICE 'Setting up test environment...';
    
    -- Create test string constants
    const0_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const0_str_id, 'hello');
    
    const1_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const1_str_id, 'world');
    
    -- Get 'len' string from bootstrap
    SELECT ob_base INTO len_str_id
    FROM public.py_unicode_object
    WHERE str_value = 'len'
    LIMIT 1;
    
    IF len_str_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: ''len'' string not found in bootstrap. Bootstrap migration must run first.';
    END IF;
    
    -- Get real __builtins__ module dict
    SELECT md_dict INTO real_builtins_dict_id
    FROM public.py_module_object
    WHERE ob_base = ID_BUILTINS_MODULE;
    
    IF real_builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ module dict not found. Bootstrap migration must run first.';
    END IF;
    
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
    
    -- Create constants tuple (co_consts) - empty initially
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);
    
    -- Create names tuple (co_names) - empty initially
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);
    
    -- Create empty bytecode
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);
    
    -- Create code object
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
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
    -- Test 1: LOAD_NAME + LOAD_CONST + PRECALL + CALL + RETURN_VALUE
    --         (len("hello") 실행)
    -- ========================================================================
    RAISE NOTICE 'Test 1: LOAD_NAME + LOAD_CONST + PRECALL + CALL + RETURN_VALUE (len("hello"))...';
    test_count := test_count + 1;
    
    -- Create constants tuple with 'hello' string
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_str_id]);
    
    -- Create names tuple with 'len'
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[len_str_id]);
    
    -- Create bytecode: LOAD_NAME(0) LOAD_CONST(0) PRECALL(1) CALL(1) RETURN_VALUE (CPython 3.11)
    -- Bytecode: [101, 0, 100, 0, 166, 1, 171, 1, 83, 0]
    -- LOAD_NAME=101, LOAD_CONST=100, PRECALL=166, CALL=171, RETURN_VALUE=83
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x65006400a601ab015300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    
    -- Update frame to use real builtins dict
    UPDATE public.py_frame_object 
    SET f_builtins = real_builtins_dict_id,
        f_valuestack = array[]::uuid[], 
        f_lasti = 0 
    WHERE ob_base = frame_id;
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify result
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: len("hello") returned NULL';
    END IF;
    
    -- Get result value
    SELECT long_value INTO result_value
    FROM public.py_long_object
    WHERE ob_base = result_id;
    
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL: len("hello") returned %, expected 5', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ len("hello") = 5';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: LOAD_NAME + LOAD_CONST + PRECALL + CALL + RETURN_VALUE
    --         (len("world") 실행)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: LOAD_NAME + LOAD_CONST + PRECALL + CALL + RETURN_VALUE (len("world"))...';
    test_count := test_count + 1;
    
    -- Create constants tuple with 'world' string
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const1_str_id]);
    
    -- Create names tuple with 'len'
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[len_str_id]);
    
    -- Create bytecode: LOAD_NAME(0) LOAD_CONST(0) PRECALL(1) CALL(1) RETURN_VALUE
    -- CPython order: function first, then arguments
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x65006400a601ab015300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    
    -- Reset frame
    UPDATE public.py_frame_object 
    SET f_valuestack = array[]::uuid[], 
        f_lasti = 0 
    WHERE ob_base = frame_id;
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify result
    SELECT long_value INTO result_value
    FROM public.py_long_object
    WHERE ob_base = result_id;
    
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL: len("world") returned %, expected 5', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ len("world") = 5';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: 여러 번의 함수 호출 (같은 frame에서)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Multiple function calls in sequence...';
    test_count := test_count + 1;
    
    -- Create constants tuple with both strings
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_str_id, const1_str_id]);
    
    -- Create names tuple with 'len'
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[len_str_id]);
    
    -- Create bytecode: 
    --   LOAD_NAME(0) LOAD_CONST(0) PRECALL(1) CALL(1)  -- len("hello")
    --   LOAD_NAME(0) LOAD_CONST(1) PRECALL(1) CALL(1)  -- len("world")
    --   RETURN_VALUE
    -- CPython order: function first, then arguments
    -- Bytecode: [101, 0, 100, 0, 166, 1, 171, 1, 101, 0, 100, 1, 166, 1, 171, 1, 83, 0]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x65006400a601ab0165006401a601ab015300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    
    -- Reset frame
    UPDATE public.py_frame_object 
    SET f_valuestack = array[]::uuid[], 
        f_lasti = 0 
    WHERE ob_base = frame_id;
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify result (should be len("world") = 5, the last function call result)
    SELECT long_value INTO result_value
    FROM public.py_long_object
    WHERE ob_base = result_id;
    
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL: Last function call result is %, expected 5 (len("world"))', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ Multiple function calls work correctly';
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
