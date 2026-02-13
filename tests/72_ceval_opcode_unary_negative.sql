-- ============================================================================
-- Test: VM UNARY_NEGATIVE(11) Opcode (CPython 3.11)
--
-- Purpose:
--   UNARY_NEGATIVE: pop TOS, push -TOS via nb_negative (int/float).
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_FLOAT_TYPE UUID := '00000000-0000-4000-a000-000000000009';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';

    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_consts_id UUID;
    empty_tuple_id UUID;
    empty_str_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    locals_dict_id UUID;
    const5_id UUID;
    const_minus3_id UUID;
    float_2_5_id UUID;
    str_hello_id UUID;
    result_id UUID;
    val numeric;
    fval double precision;
    exc_type_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM UNARY_NEGATIVE(11) Opcode Test (CPython 3.11)';
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
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
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

    const5_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const5_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const5_id, 5);
    const_minus3_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_minus3_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_minus3_id, -3);
    float_2_5_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (float_2_5_id, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (float_2_5_id, 2.5);
    str_hello_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_hello_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_hello_id, 'hello');

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_unary_negative' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_UNARY_NEGATIVE does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_UNARY_NEGATIVE exists';
    pass_count := pass_count + 1;

    -- -5: LOAD_CONST 0 (5), UNARY_NEGATIVE, RETURN. 64 00 0B 00 53 00
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[const5_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_bytes_object SET bytes_value = E'\\x64000B005300'::bytea WHERE ob_base = co_code_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: -5 returned NULL'; END IF;
    SELECT long_value INTO val FROM public.py_long_object WHERE ob_base = result_id;
    IF val IS NULL OR val != -5 THEN RAISE EXCEPTION 'FAIL: -5 expected -5, got %', val; END IF;
    RAISE NOTICE '  ✓ -5 → -5';
    pass_count := pass_count + 1;

    -- -(-3) = 3
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[const_minus3_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: -(-3) returned NULL'; END IF;
    SELECT long_value INTO val FROM public.py_long_object WHERE ob_base = result_id;
    IF val IS NULL OR val != 3 THEN RAISE EXCEPTION 'FAIL: -(-3) expected 3, got %', val; END IF;
    RAISE NOTICE '  ✓ -(-3) → 3';
    pass_count := pass_count + 1;

    -- float: -2.5
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[float_2_5_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: -2.5 returned NULL'; END IF;
    SELECT ob_fval INTO fval FROM public.py_float_object WHERE ob_base = result_id;
    IF fval IS NULL OR fval != -2.5 THEN RAISE EXCEPTION 'FAIL: -2.5 expected -2.5, got %', fval; END IF;
    RAISE NOTICE '  ✓ -2.5 → -2.5';
    pass_count := pass_count + 1;

    -- TypeError: unary - on str
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[str_hello_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL THEN RAISE EXCEPTION 'FAIL: -"hello" should raise'; END IF;
    IF NOT public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: expected TypeError'; END IF;
    SELECT e.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() e;
    IF exc_type_id != '00000000-0000-4000-a000-000000000022' THEN
        RAISE EXCEPTION 'FAIL: expected TypeError (022), got %', exc_type_id;
    END IF;
    RAISE NOTICE '  ✓ -"hello" → TypeError';
    pass_count := pass_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE '✅ All UNARY_NEGATIVE(11) opcode tests passed!';
END $$;
