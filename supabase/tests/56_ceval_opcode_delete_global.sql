-- ============================================================================
-- Test: VM DELETE_GLOBAL(98) Opcode (CPython 3.11)
--
-- Purpose:
--   DELETE_GLOBAL(namei): delete globals[name]; no stack pop. NameError if not in globals.
--
-- Usage:
--   Run after migrations. If any assertion fails, an exception is raised.
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
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
    co_names_id UUID;
    co_consts_id UUID;
    empty_tuple_id UUID;
    empty_str_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    locals_dict_id UUID;

    name_x_id UUID;
    name_y_id UUID;
    const42_id UUID;
    result_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM DELETE_GLOBAL Opcode Test (CPython 3.11)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');

    name_x_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_x_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_x_id, 'x');

    name_y_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_y_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_y_id, 'y');

    const42_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const42_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const42_id, 42);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_x_id, name_y_id]);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const42_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id,
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

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: py_opcode_DELETE_GLOBAL exists
    RAISE NOTICE 'Test 1: py_opcode_DELETE_GLOBAL exists...';
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_delete_global' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_DELETE_GLOBAL does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_DELETE_GLOBAL exists';
    pass_count := pass_count + 1;

    -- Test 2: STORE_GLOBAL "x" then DELETE_GLOBAL "x" then LOAD_GLOBAL "x" → NameError
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: STORE_GLOBAL then DELETE_GLOBAL then LOAD_GLOBAL → NameError...';
    test_count := test_count + 1;

    PERFORM public.py_err_clear();
    PERFORM public.py_stack_push(frame_id, const42_id);
    PERFORM public.py_opcode_STORE_GLOBAL(frame_id, 0);
    PERFORM public.py_opcode_DELETE_GLOBAL(frame_id, 0);
    PERFORM public.py_opcode_LOAD_GLOBAL(frame_id, 0);

    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Expected py_err_occurred() after DELETE_GLOBAL then LOAD_GLOBAL';
    END IF;
    RAISE NOTICE '  ✓ DELETE_GLOBAL removes name; LOAD_GLOBAL then raises NameError';
    pass_count := pass_count + 1;
    PERFORM public.py_err_clear();

    -- Test 3: DELETE_GLOBAL on non-existent name → NameError
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: DELETE_GLOBAL on non-existent name → NameError...';
    test_count := test_count + 1;

    PERFORM public.py_err_clear();
    PERFORM public.py_opcode_DELETE_GLOBAL(frame_id, 1);

    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Expected py_err_occurred() after DELETE_GLOBAL on non-existent name';
    END IF;
    RAISE NOTICE '  ✓ DELETE_GLOBAL on missing name sets NameError';
    pass_count := pass_count + 1;
    PERFORM public.py_err_clear();

    -- Test 4: py_eval_frame bytecode LOAD_CONST 0, STORE_GLOBAL 0, DELETE_GLOBAL 0, LOAD_GLOBAL 0, RETURN → NameError
    -- Bytecode: 100,0 97,0 98,0 116,0 83,0 = \x64006100620074005300
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: py_eval_frame STORE_GLOBAL DELETE_GLOBAL LOAD_GLOBAL → NameError...';
    test_count := test_count + 1;

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64006100620074005300'::bytea);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );

    UPDATE public.py_frame_object SET f_code = code_obj_id, f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Expected NULL return (NameError) after DELETE_GLOBAL in bytecode, got %', result_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Expected py_err_occurred() after bytecode DELETE_GLOBAL then LOAD_GLOBAL';
    END IF;

    RAISE NOTICE '  ✓ Bytecode STORE_GLOBAL + DELETE_GLOBAL + LOAD_GLOBAL triggers NameError';
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
        RAISE EXCEPTION 'Some tests failed. See details above.';
    END IF;

    RAISE NOTICE '✅ All DELETE_GLOBAL opcode tests passed!';

END $$;
