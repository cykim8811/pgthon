-- ============================================================================
-- Test: VM BINARY_SUBSCR(25) Opcode (CPython 3.11)
--
-- Purpose:
--   BINARY_SUBSCR: stack ..., obj, key → ..., result. obj[key].
--   tuple/list: key=int index (negative = from end); dict: key lookup.
--   IndexError / KeyError / TypeError.
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
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

    tuple_id UUID;
    list_id UUID;
    dict_id UUID;
    key_str_id UUID;
    val_id UUID;
    int0_id UUID;
    int1_id UUID;
    elem_a_id UUID;
    elem_b_id UUID;
    result_id UUID;
    exc_type_id UUID;
    int99_id UUID;
    int_minus1_id UUID;
    missing_key_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM BINARY_SUBSCR(25) Opcode Test (CPython 3.11)';
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

    -- tuple (a, b), list [a, b], int 0, 1, str "k", value 42
    elem_a_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (elem_a_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (elem_a_id, 'a');
    elem_b_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (elem_b_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (elem_b_id, 'b');
    tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (tuple_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (tuple_id, ARRAY[elem_a_id, elem_b_id]);
    list_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (list_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item) VALUES (list_id, ARRAY[elem_a_id, elem_b_id]);
    int0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int0_id, 0);
    int1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int1_id, 1);
    int99_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int99_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int99_id, 99);
    int_minus1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int_minus1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int_minus1_id, -1);
    missing_key_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (missing_key_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (missing_key_id, 'missing');
    key_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (key_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (key_str_id, 'k');
    val_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (val_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (val_id, 42);
    dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_id);
    PERFORM public.py_dict_set_item(dict_id, key_str_id, val_id);

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: py_opcode_BINARY_SUBSCR exists
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_binary_subscr' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_BINARY_SUBSCR does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_BINARY_SUBSCR exists';
    pass_count := pass_count + 1;

    -- Test 2: tuple[1] → second element. consts[0]=tuple, consts[1]=1. Bytecode: LOAD_CONST 0, LOAD_CONST 1, BINARY_SUBSCR(25,0), RETURN_VALUE
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[tuple_id, int1_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_bytes_object SET bytes_value = E'\\x6400640119005300'::bytea WHERE ob_base = co_code_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: tuple[1] returned NULL'; END IF;
    IF result_id != elem_b_id THEN RAISE EXCEPTION 'FAIL: tuple[1] expected elem_b, got %', result_id; END IF;
    RAISE NOTICE '  ✓ tuple[1] → second element';
    pass_count := pass_count + 1;

    -- Test 3: list[0] → first element. consts[0]=list, consts[1]=0
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[list_id, int0_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: list[0] returned NULL'; END IF;
    IF result_id != elem_a_id THEN RAISE EXCEPTION 'FAIL: list[0] expected elem_a, got %', result_id; END IF;
    RAISE NOTICE '  ✓ list[0] → first element';
    pass_count := pass_count + 1;

    -- Test 4: dict["k"] → 42. consts[0]=dict, consts[1]=key_str
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[dict_id, key_str_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: dict[key] returned NULL'; END IF;
    IF result_id != val_id THEN RAISE EXCEPTION 'FAIL: dict[key] expected 42, got %', result_id; END IF;
    RAISE NOTICE '  ✓ dict[key] → value';
    pass_count := pass_count + 1;

    -- Test 5: tuple index out of range → IndexError. consts[0]=tuple, consts[1]=99
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[tuple_id, int99_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL THEN RAISE EXCEPTION 'FAIL: tuple[99] should raise IndexError'; END IF;
    IF NOT public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: expected exception'; END IF;
    SELECT e.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() e;
    IF exc_type_id != '00000000-0000-4000-a000-000000000028' THEN
        RAISE EXCEPTION 'FAIL: expected IndexError (028), got %', exc_type_id;
    END IF;
    RAISE NOTICE '  ✓ tuple index out of range → IndexError';
    pass_count := pass_count + 1;

    -- Test 5b: tuple[-1] → last element
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[tuple_id, int_minus1_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: tuple[-1] returned NULL'; END IF;
    IF result_id != elem_b_id THEN RAISE EXCEPTION 'FAIL: tuple[-1] expected elem_b, got %', result_id; END IF;
    RAISE NOTICE '  ✓ tuple[-1] → last element';
    pass_count := pass_count + 1;

    -- Test 6: dict key not found → KeyError. consts[0]=dict, consts[1]=missing_key
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[dict_id, missing_key_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL THEN RAISE EXCEPTION 'FAIL: dict[missing] should raise'; END IF;
    IF NOT public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: expected exception'; END IF;
    SELECT e.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() e;
    IF exc_type_id != '00000000-0000-4000-a000-000000000029' THEN
        RAISE EXCEPTION 'FAIL: expected KeyError (029), got %', exc_type_id;
    END IF;
    RAISE NOTICE '  ✓ dict key not found → KeyError';
    pass_count := pass_count + 1;

    -- Test 7: non-subscriptable (int) → TypeError. consts[0]=int 1, consts[1]=0
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[int1_id, int0_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL THEN RAISE EXCEPTION 'FAIL: int[0] should raise'; END IF;
    IF NOT public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: expected TypeError'; END IF;
    SELECT e.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() e;
    IF exc_type_id != '00000000-0000-4000-a000-000000000022' THEN
        RAISE EXCEPTION 'FAIL: expected TypeError (022), got %', exc_type_id;
    END IF;
    RAISE NOTICE '  ✓ int not subscriptable → TypeError';
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
    RAISE NOTICE '✅ All BINARY_SUBSCR(25) opcode tests passed!';
END $$;
