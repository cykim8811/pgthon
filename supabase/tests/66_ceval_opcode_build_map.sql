-- ============================================================================
-- Test: VM BUILD_MAP(105) Opcode (CPython 3.11)
--
-- Purpose:
--   BUILD_MAP(count): pop 2*count items (key, value per pair; TOS = last key).
--   Build new dict, push it.
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';

    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;

    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_consts_id UUID;
    co_names_id UUID;
    empty_tuple_id UUID;
    empty_str_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    locals_dict_id UUID;

    key_str_id UUID;
    val_id UUID;
    result_id UUID;
    got_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM BUILD_MAP(105) Opcode Test (CPython 3.11)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );

    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    -- key string "x", value int 42
    key_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (key_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (key_str_id, 'x');
    val_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (val_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (val_id, 42);

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: py_opcode_BUILD_MAP exists
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_build_map' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_BUILD_MAP does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_BUILD_MAP exists';
    pass_count := pass_count + 1;

    -- Test 2: BUILD_MAP 1 — stack: key, value; BUILD_MAP 1 → dict[key]=value. Return dict, verify dict[key]=value.
    -- Bytecode: LOAD_CONST 0 (key), LOAD_CONST 1 (value), BUILD_MAP 1, RETURN. 100,0 100,1 105,1 83,0. 105=0x69.
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[key_str_id, val_id] WHERE ob_base = co_consts_id;
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x6400640169015300'::bytea);
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );
    UPDATE public.py_frame_object SET f_code = code_obj_id, f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: BUILD_MAP 1 returned NULL'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_dict_object WHERE ob_base = result_id) THEN
        RAISE EXCEPTION 'FAIL: Expected dict result';
    END IF;
    got_id := public.py_dict_get_item(result_id, key_str_id);
    IF got_id IS NULL OR got_id != val_id THEN
        RAISE EXCEPTION 'FAIL: Expected dict[key]=value, got %', got_id;
    END IF;
    RAISE NOTICE '  ✓ BUILD_MAP 1: dict with one pair, dict[key]=value';
    pass_count := pass_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total tests: %', test_count;
    RAISE NOTICE 'Passed: %', pass_count;
    RAISE NOTICE 'Failed: %', fail_count;
    RAISE NOTICE '';
    IF fail_count > 0 THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE '✅ All BUILD_MAP(105) opcode tests passed!';
END $$;
