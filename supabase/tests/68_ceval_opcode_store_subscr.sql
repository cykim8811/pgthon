-- ============================================================================
-- Test: VM STORE_SUBSCR(60) Opcode (CPython 3.11)
--
-- Purpose:
--   STORE_SUBSCR: stack ..., obj, key, value → .... obj[key] = value.
--   list: in-place update by index; dict: py_dict_set_item; tuple → TypeError.
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000008';
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
    val_99_id UUID;
    key_str_id UUID;
    elem_a_id UUID;
    elem_b_id UUID;
    result_id UUID;
    exc_type_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM STORE_SUBSCR(60) Opcode Test (CPython 3.11)';
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
    val_99_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (val_99_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (val_99_id, 99);
    key_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (key_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (key_str_id, 'x');
    dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_id);
    tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (tuple_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (tuple_id, ARRAY[elem_a_id, elem_b_id]);

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: py_opcode_STORE_SUBSCR exists
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_store_subscr' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_STORE_SUBSCR does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_STORE_SUBSCR exists';
    pass_count := pass_count + 1;

    -- Test 2: list[0] = 99 then verify with BINARY_SUBSCR. consts: [list, 0, 99]. Bytecode: LOAD_CONST 0,1,2 STORE_SUBSCR LOAD_CONST 0,1 BINARY_SUBSCR RETURN_VALUE
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[list_id, int0_id, val_99_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_bytes_object SET bytes_value = E'\\x6400640164023C006400640119005300'::bytea WHERE ob_base = co_code_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: list[0]=99 then list[0] returned NULL'; END IF;
    IF result_id != val_99_id THEN RAISE EXCEPTION 'FAIL: list[0] expected 99, got %', result_id; END IF;
    RAISE NOTICE '  ✓ list[0] = 99; list[0] → 99';
    pass_count := pass_count + 1;

    -- Test 3: dict["x"] = 99 then verify. consts: [dict, "x", 99]. Same bytecode pattern.
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[dict_id, key_str_id, val_99_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: dict["x"]=99 then dict["x"] returned NULL'; END IF;
    IF result_id != val_99_id THEN RAISE EXCEPTION 'FAIL: dict["x"] expected 99, got %', result_id; END IF;
    RAISE NOTICE '  ✓ dict["x"] = 99; dict["x"] → 99';
    pass_count := pass_count + 1;

    -- Test 4: tuple[0] = 99 → TypeError (tuple does not support item assignment). consts: [tuple, 0, 99]
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[tuple_id, int0_id, val_99_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NOT NULL THEN RAISE EXCEPTION 'FAIL: tuple[0]=99 should raise'; END IF;
    IF NOT public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: expected TypeError'; END IF;
    SELECT e.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() e;
    IF exc_type_id != '00000000-0000-4000-a000-000000000022' THEN
        RAISE EXCEPTION 'FAIL: expected TypeError (022), got %', exc_type_id;
    END IF;
    RAISE NOTICE '  ✓ tuple item assignment → TypeError';
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
    RAISE NOTICE '✅ All STORE_SUBSCR(60) opcode tests passed!';
END $$;
