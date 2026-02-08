-- ============================================================================
-- Test: VM POP_JUMP_BACKWARD_IF_NONE(173), POP_JUMP_BACKWARD_IF_NOT_NONE(174) (CPython 3.11)
--
-- Purpose:
--   POP_JUMP_BACKWARD_IF_NONE: pop TOS; if TOS is None, jump to target (oparg*2).
--   POP_JUMP_BACKWARD_IF_NOT_NONE: pop TOS; if TOS is not None, jump to target (oparg*2).
--
-- Usage:
--   Run after migrations. If any assertion fails, an exception is raised.
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_NONE_OBJ UUID := '00000000-0000-4000-b000-000000000001';

    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;

    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_consts_id UUID;
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;

    const1_id UUID;
    const2_id UUID;
    result_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM POP_JUMP_BACKWARD IF_NONE/IF_NOT_NONE Opcode Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, (SELECT ob_type FROM public.py_object WHERE id = '00000000-0000-4000-a000-000000000003'));
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

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: Functions exist
    RAISE NOTICE 'Test 1: py_opcode_POP_JUMP_BACKWARD_IF_NONE/IF_NOT_NONE exist...';
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_pop_jump_backward_if_none' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_POP_JUMP_BACKWARD_IF_NONE does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_pop_jump_backward_if_not_none' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_POP_JUMP_BACKWARD_IF_NOT_NONE does not exist';
    END IF;
    RAISE NOTICE '  ✓ Both functions exist';
    pass_count := pass_count + 1;

    -- const1, const2 (non-None)
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 1);

    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const2_id, 2);

    -- Test 2: POP_JUMP_BACKWARD_IF_NONE — TOS None → jump to target (const2); TOS not None → no jump (const1)
    -- Bytecode: LOAD_CONST 0, POP_JUMP_BACKWARD_IF_NONE 4, LOAD_CONST 1, RETURN, LOAD_CONST 2, RETURN.
    -- 100,0 173,4 100,1 83,0 100,2 83,0 = \x6400ad046401530064025300 (173=0xAD)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: POP_JUMP_BACKWARD_IF_NONE — None jumps, non-None does not...';
    test_count := test_count + 1;

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[ID_NONE_OBJ, const1_id, const2_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x6400ad046401530064025300'::bytea);

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
    UPDATE public.py_code_object SET co_consts = co_consts_id WHERE ob_base = code_obj_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: POP_JUMP_BACKWARD_IF_NONE (None) returned NULL'; END IF;
    IF result_id != const2_id THEN RAISE EXCEPTION 'FAIL: Expected const2 (jump when None), got %', result_id; END IF;

    UPDATE public.py_tuple_object SET ob_item = ARRAY[const1_id, const1_id, const2_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: POP_JUMP_BACKWARD_IF_NONE (non-None) returned NULL'; END IF;
    IF result_id != const1_id THEN RAISE EXCEPTION 'FAIL: Expected const1 (no jump when non-None), got %', result_id; END IF;

    RAISE NOTICE '  ✓ POP_JUMP_BACKWARD_IF_NONE: None→jump→const2, non-None→no jump→const1';
    pass_count := pass_count + 1;

    -- Test 3: POP_JUMP_BACKWARD_IF_NOT_NONE — TOS not None → jump (const2); TOS None → no jump (const1)
    -- Bytecode: LOAD_CONST 0, POP_JUMP_BACKWARD_IF_NOT_NONE 4, LOAD_CONST 1, RETURN, LOAD_CONST 2, RETURN.
    -- 100,0 174,4 100,1 83,0 100,2 83,0 = \x6400ae046401530064025300 (174=0xAE)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: POP_JUMP_BACKWARD_IF_NOT_NONE — non-None jumps, None does not...';
    test_count := test_count + 1;

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x6400ae046401530064025300'::bytea);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );

    UPDATE public.py_tuple_object SET ob_item = ARRAY[const1_id, const1_id, const2_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_code = code_obj_id, f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: POP_JUMP_BACKWARD_IF_NOT_NONE (non-None) returned NULL'; END IF;
    IF result_id != const2_id THEN RAISE EXCEPTION 'FAIL: Expected const2 (jump when non-None), got %', result_id; END IF;

    UPDATE public.py_tuple_object SET ob_item = ARRAY[ID_NONE_OBJ, const1_id, const2_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: POP_JUMP_BACKWARD_IF_NOT_NONE (None) returned NULL'; END IF;
    IF result_id != const1_id THEN RAISE EXCEPTION 'FAIL: Expected const1 (no jump when None), got %', result_id; END IF;

    RAISE NOTICE '  ✓ POP_JUMP_BACKWARD_IF_NOT_NONE: non-None→jump→const2, None→no jump→const1';
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

    RAISE NOTICE '✅ All POP_JUMP_BACKWARD IF_NONE/IF_NOT_NONE opcode tests passed!';

END $$;
