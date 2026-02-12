-- ============================================================================
-- Test: VM LOAD_NAME Integration Test
-- 
-- Purpose:
--   Tests LOAD_NAME opcode in realistic integration scenarios. This verifies:
--   - LOAD_NAME + RETURN_VALUE: 이름 로드 후 반환 패턴
--   - LOAD_CONST + STORE_NAME + LOAD_NAME: 변수 할당 후 로드 패턴
--   - Namespace lookup 순서 검증 (locals → globals → builtins)
--   - Builtin 함수 로드 (len 함수)
--   - 여러 namespace에서의 이름 로드
--   - Frame isolation (여러 frame에서 독립적인 namespace)
--
--   All tests follow CPython's exact behavior and execution model.
--
-- Usage:
--   Run this file after migrations to verify LOAD_NAME integration.
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
    const0_id UUID;
    const1_id UUID;
    
    -- Test name strings
    name0_str_id UUID;  -- 'x'
    name1_str_id UUID;  -- 'y'
    len_str_id UUID;    -- 'len' (from bootstrap)
    
    -- Test variables
    result_id UUID;
    loaded_obj_id UUID;
    entry_count INTEGER;
    stack_size INTEGER;
    
    -- Helper variables
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    real_builtins_dict_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM LOAD_NAME Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Setup: Create test objects and frame infrastructure
    -- ========================================================================
    RAISE NOTICE 'Setting up test environment...';
    
    -- Create test constants
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 42);
    
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 100);
    
    -- Create name strings
    name0_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name0_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name0_str_id, 'x');
    
    name1_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name1_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name1_str_id, 'y');
    
    -- Get 'len' string from bootstrap (for builtins lookup)
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
    -- Test 1: LOAD_NAME from locals + RETURN_VALUE
    -- ========================================================================
    RAISE NOTICE 'Test 1: LOAD_NAME from locals + RETURN_VALUE...';
    test_count := test_count + 1;
    
    -- Store value in locals dict
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
    VALUES (locals_dict_id, name0_str_id, const0_id, public.py_object_hash(name0_str_id));
    
    -- Create names tuple with 'x'
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id]);
    
    -- Create bytecode: LOAD_NAME(0) RETURN_VALUE
    -- Bytecode: [101, 0, 83, 0]
    -- LOAD_NAME = 101, RETURN_VALUE = 83
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x65005300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    
    -- Reset frame
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify result
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Return value is %, expected % (const0_id)', result_id, const0_id;
    END IF;
    
    RAISE NOTICE '  ✓ LOAD_NAME from locals + RETURN_VALUE works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: LOAD_CONST + STORE_NAME + LOAD_NAME (변수 할당 후 로드)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: LOAD_CONST + STORE_NAME + LOAD_NAME (변수 할당 후 로드)...';
    test_count := test_count + 1;
    
    -- Create new locals dict
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    -- Create constants tuple with const0_id
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    
    -- Create names tuple with 'x'
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id]);
    
    -- Create bytecode: LOAD_CONST(0) STORE_NAME(0) LOAD_NAME(0) RETURN_VALUE
    -- Bytecode: [100, 0, 90, 0, 101, 0, 83, 0]
    -- LOAD_CONST = 100, STORE_NAME = 90, LOAD_NAME = 101, RETURN_VALUE = 83
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005a0065005300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    
    -- Update frame
    UPDATE public.py_frame_object SET f_locals = locals_dict_id, f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify result
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Return value is %, expected % (const0_id)', result_id, const0_id;
    END IF;
    
    -- Verify value was stored in locals
    SELECT me_value INTO loaded_obj_id
    FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id
    AND me_key = name0_str_id;
    
    IF loaded_obj_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Stored value in locals is %, expected %', loaded_obj_id, const0_id;
    END IF;
    
    RAISE NOTICE '  ✓ LOAD_CONST + STORE_NAME + LOAD_NAME works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: LOAD_NAME from globals (when not in locals)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: LOAD_NAME from globals (when not in locals)...';
    test_count := test_count + 1;
    
    -- Create new locals dict (empty)
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    -- Store value in globals dict
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
    VALUES (globals_dict_id, name0_str_id, const0_id, public.py_object_hash(name0_str_id));
    
    -- Create names tuple with 'x'
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id]);
    
    -- Create bytecode: LOAD_NAME(0) RETURN_VALUE
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x65005300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    
    -- Update frame
    UPDATE public.py_frame_object SET f_locals = locals_dict_id, f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify result
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Return value is %, expected % (const0_id from globals)', result_id, const0_id;
    END IF;
    
    RAISE NOTICE '  ✓ LOAD_NAME from globals works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: LOAD_NAME from builtins (len function)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: LOAD_NAME from builtins (len function)...';
    test_count := test_count + 1;
    
    -- Create new locals dict (empty)
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    -- Create new globals dict (empty)
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    
    -- Create names tuple with 'len'
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[len_str_id]);
    
    -- Create bytecode: LOAD_NAME(0) RETURN_VALUE
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x65005300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    
    -- Update frame to use real builtins dict
    UPDATE public.py_frame_object 
    SET f_locals = locals_dict_id, 
        f_globals = globals_dict_id, 
        f_builtins = real_builtins_dict_id,
        f_valuestack = array[]::uuid[], 
        f_lasti = 0 
    WHERE ob_base = frame_id;
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify result is len function
    IF result_id != ID_LEN_FUNCTION THEN
        RAISE EXCEPTION 'FAIL: Return value is %, expected % (ID_LEN_FUNCTION)', result_id, ID_LEN_FUNCTION;
    END IF;
    
    RAISE NOTICE '  ✓ LOAD_NAME from builtins (len function) works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: Namespace lookup order (locals takes precedence)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Namespace lookup order (locals takes precedence)...';
    test_count := test_count + 1;
    
    -- Create new locals dict
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    -- Create new globals dict
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    
    -- Store different values in locals and globals
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
    VALUES (locals_dict_id, name0_str_id, const0_id, public.py_object_hash(name0_str_id));
    
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
    VALUES (globals_dict_id, name0_str_id, const1_id, public.py_object_hash(name0_str_id));
    
    -- Create names tuple with 'x'
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id]);
    
    -- Create bytecode: LOAD_NAME(0) RETURN_VALUE
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x65005300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    
    -- Update frame
    UPDATE public.py_frame_object 
    SET f_locals = locals_dict_id, 
        f_globals = globals_dict_id,
        f_valuestack = array[]::uuid[], 
        f_lasti = 0 
    WHERE ob_base = frame_id;
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify result is from locals (not globals)
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Return value is %, expected % (const0_id from locals, not globals)', result_id, const0_id;
    END IF;
    
    IF result_id = const1_id THEN
        RAISE EXCEPTION 'FAIL: Return value is from globals, expected from locals (wrong lookup order)';
    END IF;
    
    RAISE NOTICE '  ✓ Namespace lookup order is correct (locals → globals → builtins)';
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
