-- ============================================================================
-- Test: VM LOAD_GLOBAL Integration Test (CPython 3.11 opcode 116)
--
-- Purpose:
--   Tests LOAD_GLOBAL opcode in realistic integration scenarios. This verifies:
--   - LOAD_GLOBAL + RETURN_VALUE: globals/builtins에서 로드 후 반환
--   - LOAD_GLOBAL ignores locals (globals → builtins only)
--   - LOAD_GLOBAL + LOAD_CONST + PRECALL + CALL + RETURN_VALUE: len("hello") via LOAD_GLOBAL
--   - Combined: STORE_NAME in locals, LOAD_GLOBAL returns global (not local)
--
-- Usage:
--   Run this file after migrations to verify LOAD_GLOBAL integration.
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_LEN_FUNCTION UUID := '00000000-0000-4000-b000-000000000003';
    
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    
    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_names_id UUID;
    co_consts_id UUID;
    
    const0_id UUID;
    const1_id UUID;
    const0_str_id UUID;
    name0_str_id UUID;
    len_str_id UUID;
    result_id UUID;
    result_value NUMERIC;
    
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    real_builtins_dict_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM LOAD_GLOBAL Integration Test (CPython 3.11 opcode 116)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    RAISE NOTICE 'Setting up test environment...';
    
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 42);
    
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 100);
    
    const0_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const0_str_id, 'hello');
    
    name0_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name0_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name0_str_id, 'x');
    
    SELECT ob_base INTO len_str_id FROM public.py_unicode_object WHERE str_value = 'len' LIMIT 1;
    IF len_str_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: ''len'' string not found in bootstrap.';
    END IF;
    
    SELECT md_dict INTO real_builtins_dict_id FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;
    IF real_builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ module dict not found.';
    END IF;
    
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    
    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
    
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    
    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);
    
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);
    
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);
    
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);
    
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );
    
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';
    
    -- Test 1: LOAD_GLOBAL from globals + RETURN_VALUE (bytecode 116,0 83,0)
    RAISE NOTICE 'Test 1: LOAD_GLOBAL from globals + RETURN_VALUE...';
    test_count := test_count + 1;
    
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
    VALUES (globals_dict_id, name0_str_id, const0_id, public.py_object_hash(name0_str_id));
    
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id]);
    
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x74005300'::bytea);
    
    UPDATE public.py_code_object SET co_code = co_code_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    
    result_id := public.py_eval_frame(frame_id);
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: LOAD_GLOBAL + RETURN_VALUE returned %, expected % (from globals)', result_id, const0_id;
    END IF;
    RAISE NOTICE '  ✓ LOAD_GLOBAL from globals + RETURN_VALUE works correctly';
    pass_count := pass_count + 1;
    
    -- Test 2: LOAD_GLOBAL from builtins (len) + RETURN_VALUE
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: LOAD_GLOBAL from builtins (len) + RETURN_VALUE...';
    test_count := test_count + 1;
    
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[len_str_id]);
    
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x74005300'::bytea);
    
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    
    UPDATE public.py_code_object SET co_code = co_code_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object
    SET f_globals = globals_dict_id, f_builtins = real_builtins_dict_id,
        f_valuestack = array[]::uuid[], f_lasti = 0
    WHERE ob_base = frame_id;
    
    result_id := public.py_eval_frame(frame_id);
    IF result_id != ID_LEN_FUNCTION THEN
        RAISE EXCEPTION 'FAIL: LOAD_GLOBAL from builtins returned %, expected ID_LEN_FUNCTION', result_id;
    END IF;
    RAISE NOTICE '  ✓ LOAD_GLOBAL from builtins (len) works correctly';
    pass_count := pass_count + 1;
    
    -- Test 3: LOAD_GLOBAL ignores locals (x in locals=42, x in globals=100 → returns 100)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: LOAD_GLOBAL ignores locals (returns global value)...';
    test_count := test_count + 1;
    
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
    VALUES (locals_dict_id, name0_str_id, const0_id, public.py_object_hash(name0_str_id));
    
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
    VALUES (globals_dict_id, name0_str_id, const1_id, public.py_object_hash(name0_str_id));
    
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id]);
    
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x74005300'::bytea);
    
    UPDATE public.py_code_object SET co_code = co_code_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object
    SET f_locals = locals_dict_id, f_globals = globals_dict_id,
        f_valuestack = array[]::uuid[], f_lasti = 0
    WHERE ob_base = frame_id;
    
    result_id := public.py_eval_frame(frame_id);
    IF result_id != const1_id THEN
        RAISE EXCEPTION 'FAIL: LOAD_GLOBAL should return global value (100), got %', result_id;
    END IF;
    IF result_id = const0_id THEN
        RAISE EXCEPTION 'FAIL: LOAD_GLOBAL must not return local value (42)';
    END IF;
    RAISE NOTICE '  ✓ LOAD_GLOBAL correctly ignores locals (returns global 100)';
    pass_count := pass_count + 1;
    
    -- Test 4: LOAD_GLOBAL + LOAD_CONST + PRECALL + CALL + RETURN_VALUE → len("hello") = 5
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: LOAD_GLOBAL + LOAD_CONST + PRECALL + CALL + RETURN_VALUE (len("hello"))...';
    test_count := test_count + 1;
    
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_str_id]);
    
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[len_str_id]);
    
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x74006400a601ab015300'::bytea);
    
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object
    SET f_globals = globals_dict_id, f_builtins = real_builtins_dict_id,
        f_valuestack = array[]::uuid[], f_lasti = 0
    WHERE ob_base = frame_id;
    
    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: len("hello") via LOAD_GLOBAL returned NULL';
    END IF;
    SELECT long_value INTO result_value FROM public.py_long_object WHERE ob_base = result_id;
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL: len("hello") via LOAD_GLOBAL returned %, expected 5', result_value;
    END IF;
    RAISE NOTICE '  ✓ LOAD_GLOBAL + LOAD_CONST + PRECALL + CALL: len("hello") = 5';
    pass_count := pass_count + 1;
    
    -- Test 5: Combined — STORE_NAME in locals, LOAD_GLOBAL returns global (not local)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: STORE_NAME in locals, LOAD_GLOBAL returns global...';
    test_count := test_count + 1;
    
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id]);
    
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005a0074005300'::bytea);
    
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
    VALUES (globals_dict_id, name0_str_id, const1_id, public.py_object_hash(name0_str_id));
    
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object
    SET f_locals = locals_dict_id, f_globals = globals_dict_id,
        f_valuestack = array[]::uuid[], f_lasti = 0
    WHERE ob_base = frame_id;
    
    result_id := public.py_eval_frame(frame_id);
    IF result_id != const1_id THEN
        RAISE EXCEPTION 'FAIL: LOAD_GLOBAL after STORE_NAME should return global (100), got %', result_id;
    END IF;
    RAISE NOTICE '  ✓ STORE_NAME then LOAD_GLOBAL returns global value (100)';
    pass_count := pass_count + 1;
    
    -- Summary
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
