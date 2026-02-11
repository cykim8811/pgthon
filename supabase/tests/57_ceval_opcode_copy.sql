-- ============================================================================
-- Test: VM COPY(120) Opcode (CPython 3.11)
--
-- Purpose:
--   COPY(depth): copy stack[-depth] to top of stack. depth >= 1.
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

    const0_id UUID;
    const1_id UUID;
    result_id UUID;
    stack_len INTEGER;
    top_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM COPY Opcode Test (CPython 3.11)';
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

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: py_opcode_COPY exists
    RAISE NOTICE 'Test 1: py_opcode_COPY exists...';
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_copy' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_COPY does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_COPY exists';
    pass_count := pass_count + 1;

    -- Test 2: COPY(1) duplicates TOS
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: COPY(1) duplicates TOS...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 42);

    PERFORM public.py_stack_push(frame_id, const0_id);
    PERFORM public.py_opcode_COPY(frame_id, 1);

    SELECT array_length(f_valuestack, 1), f_valuestack[array_length(f_valuestack, 1)]
    INTO stack_len, top_id
    FROM public.py_frame_object WHERE ob_base = frame_id;
    IF stack_len != 2 THEN
        RAISE EXCEPTION 'FAIL: After COPY(1) stack length expected 2, got %', stack_len;
    END IF;
    IF top_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: After COPY(1) TOS expected %, got %', const0_id, top_id;
    END IF;
    IF (SELECT f_valuestack[1] FROM public.py_frame_object WHERE ob_base = frame_id) != const0_id THEN
        RAISE EXCEPTION 'FAIL: After COPY(1) stack[1] expected %', const0_id;
    END IF;

    RAISE NOTICE '  ✓ COPY(1) duplicates TOS (stack length 2, both same ref)';
    pass_count := pass_count + 1;

    -- Test 3: COPY(2) copies stack[-2] to top
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: COPY(2) copies stack[-2] to top...';
    test_count := test_count + 1;

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 99);

    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[] WHERE ob_base = frame_id;
    PERFORM public.py_stack_push(frame_id, const0_id);
    PERFORM public.py_stack_push(frame_id, const1_id);
    PERFORM public.py_opcode_COPY(frame_id, 2);

    SELECT array_length(f_valuestack, 1), f_valuestack[3]
    INTO stack_len, top_id
    FROM public.py_frame_object WHERE ob_base = frame_id;
    IF stack_len != 3 THEN
        RAISE EXCEPTION 'FAIL: After COPY(2) stack length expected 3, got %', stack_len;
    END IF;
    IF top_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: After COPY(2) TOS (stack[-1]) expected const0 %, got %', const0_id, top_id;
    END IF;

    RAISE NOTICE '  ✓ COPY(2) copies stack[-2] to top (stack [const0, const1, const0])';
    pass_count := pass_count + 1;

    -- Test 4: py_eval_frame LOAD_CONST 0, COPY 1, RETURN_VALUE → returns const0
    -- Bytecode: 100,0 120,1 83,0 = \x640078015300
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: py_eval_frame LOAD_CONST COPY RETURN_VALUE...';
    test_count := test_count + 1;

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640078015300'::bytea);

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
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_eval_frame with COPY returned NULL';
    END IF;
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Expected const0 %, got %', const0_id, result_id;
    END IF;

    RAISE NOTICE '  ✓ Bytecode LOAD_CONST 0, COPY 1, RETURN_VALUE returns const0';
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

    RAISE NOTICE '✅ All COPY opcode tests passed!';

END $$;
