-- ============================================================================
-- Test: VM DELETE_SUBSCR(61) Opcode (CPython 3.11)
--
-- Purpose:
--   DELETE_SUBSCR: stack ..., obj, key → .... del obj[key].
--   list: remove element at index; dict: py_dict_del_item; tuple → TypeError.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';

    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;

    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_consts_id UUID;
    empty_tuple_id UUID;
    empty_str_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    locals_dict_id UUID;

    list_id UUID;
    dict_id UUID;
    tuple_id UUID;
    int0_id UUID;
    key_str_id UUID;
    elem_a_id UUID;
    elem_b_id UUID;
    result_id UUID;
    exc_type_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM DELETE_SUBSCR(61) Opcode Test (CPython 3.11)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

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
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
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

    elem_a_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (elem_a_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (elem_a_id, 'a');
    elem_b_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (elem_b_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (elem_b_id, 'b');
    list_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (list_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item) VALUES (list_id, ARRAY[elem_a_id, elem_b_id]);
    int0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int0_id, 0);
    key_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (key_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (key_str_id, 'x');
    dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_id);
    PERFORM public.py_dict_set_item(dict_id, key_str_id, elem_a_id);
    tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (tuple_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (tuple_id, ARRAY[elem_a_id, elem_b_id]);

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: py_opcode_DELETE_SUBSCR exists
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_delete_subscr' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_DELETE_SUBSCR does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_DELETE_SUBSCR exists';
    pass_count := pass_count + 1;

    -- Test 2: del list[0] then list[0] → second element. consts [list, 0]. Bytecode: LOAD_CONST 0,1 DELETE_SUBSCR LOAD_CONST 0,1 BINARY_SUBSCR RETURN_VALUE
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[list_id, int0_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_bytes_object SET bytes_value = E'\\x640064013D006400640119005300'::bytea WHERE ob_base = co_code_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: del list[0] then list[0] returned NULL'; END IF;
    IF result_id != elem_b_id THEN RAISE EXCEPTION 'FAIL: after del list[0], list[0] expected elem_b, got %', result_id; END IF;
    RAISE NOTICE '  ✓ del list[0]; list[0] → second element';
    pass_count := pass_count + 1;

    -- Test 3: del dict["x"] then dict["x"] → KeyError. consts [dict, "x"]. Bytecode: LOAD_CONST 0,1 DELETE_SUBSCR LOAD_CONST 0 LOAD_CONST 1 BINARY_SUBSCR RETURN_VALUE → will set KeyError
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[dict_id, key_str_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_bytes_object SET bytes_value = E'\\x640064013D006400640119005300'::bytea WHERE ob_base = co_code_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL THEN RAISE EXCEPTION 'FAIL: after del dict["x"], dict["x"] should raise KeyError'; END IF;
    IF NOT public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: expected KeyError'; END IF;
    SELECT e.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() e;
    IF exc_type_id != '00000000-0000-4000-a000-000000000029' THEN
        RAISE EXCEPTION 'FAIL: expected KeyError (029), got %', exc_type_id;
    END IF;
    RAISE NOTICE '  ✓ del dict["x"]; dict["x"] → KeyError';
    pass_count := pass_count + 1;

    -- Test 4: del tuple[0] → TypeError
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[tuple_id, int0_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_bytes_object SET bytes_value = E'\\x640064013D005300'::bytea WHERE ob_base = co_code_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL THEN RAISE EXCEPTION 'FAIL: del tuple[0] should raise'; END IF;
    IF NOT public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: expected TypeError'; END IF;
    SELECT e.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() e;
    IF exc_type_id != '00000000-0000-4000-a000-000000000022' THEN
        RAISE EXCEPTION 'FAIL: expected TypeError (022), got %', exc_type_id;
    END IF;
    RAISE NOTICE '  ✓ del tuple[0] → TypeError';
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
    RAISE NOTICE '✅ All DELETE_SUBSCR(61) opcode tests passed!';
END $$;
