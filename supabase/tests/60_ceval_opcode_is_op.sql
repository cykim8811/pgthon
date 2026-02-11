-- ============================================================================
-- Test: VM IS_OP(117) Opcode (CPython 3.11)
--
-- Purpose:
--   IS_OP(oparg): oparg 0 = "is" (push True if left is right), oparg 1 = "is not".
--   Stack: ..., left, right → ..., result (bool). Identity = same object (UUID).
--
-- Usage:
--   Run after migrations. If any assertion fails, an exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_TRUE_OBJ UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000011';

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

    obj_a_id UUID;
    obj_b_id UUID;
    result_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM IS_OP(117) Opcode Test (CPython 3.11)';
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

    -- Two distinct int objects for "is" / "is not" tests
    obj_a_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (obj_a_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (obj_a_id, 1);
    obj_b_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (obj_b_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (obj_b_id, 1);

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: py_opcode_IS_OP exists
    RAISE NOTICE 'Test 1: py_opcode_IS_OP exists...';
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_is_op' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_IS_OP does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_IS_OP exists';
    pass_count := pass_count + 1;

    -- Test 2: IS_OP(0) "is" — same object → True, different object → False
    -- Bytecode: LOAD_CONST 0, LOAD_CONST 1, IS_OP 0, RETURN. consts[0]=left, consts[1]=right.
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: IS_OP(0) "is" — same object → True, different → False...';
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[obj_a_id, obj_a_id] WHERE ob_base = co_consts_id;
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- 100,0 100,1 117,0 83,0 = \x6400640175005300
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x6400640175005300'::bytea);
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );
    UPDATE public.py_frame_object SET f_code = code_obj_id, f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: IS_OP(0) same object returned NULL'; END IF;
    IF result_id != ID_TRUE_OBJ THEN RAISE EXCEPTION 'FAIL: Expected True (same object), got %', result_id; END IF;

    UPDATE public.py_tuple_object SET ob_item = ARRAY[obj_a_id, obj_b_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: IS_OP(0) different object returned NULL'; END IF;
    IF result_id != ID_FALSE_OBJ THEN RAISE EXCEPTION 'FAIL: Expected False (different object), got %', result_id; END IF;

    RAISE NOTICE '  ✓ IS_OP(0): same→True, different→False';
    pass_count := pass_count + 1;

    -- Test 3: IS_OP(1) "is not" — different object → True, same object → False
    test_count := test_count + 1;
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- 100,0 100,1 117,1 83,0 = \x6400640175015300
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x6400640175015300'::bytea);
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );
    UPDATE public.py_frame_object SET f_code = code_obj_id, f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[obj_a_id, obj_b_id] WHERE ob_base = co_consts_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: IS_OP(1) different object returned NULL'; END IF;
    IF result_id != ID_TRUE_OBJ THEN RAISE EXCEPTION 'FAIL: Expected True (is not, different), got %', result_id; END IF;

    UPDATE public.py_tuple_object SET ob_item = ARRAY[obj_a_id, obj_a_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: IS_OP(1) same object returned NULL'; END IF;
    IF result_id != ID_FALSE_OBJ THEN RAISE EXCEPTION 'FAIL: Expected False (is not, same), got %', result_id; END IF;

    RAISE NOTICE '  ✓ IS_OP(1): different→True, same→False';
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

    RAISE NOTICE '✅ All IS_OP(117) opcode tests passed!';

END $$;
