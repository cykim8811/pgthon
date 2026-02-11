-- ============================================================================
-- Test: VM JUMP_IF_FALSE_OR_POP(111), JUMP_IF_TRUE_OR_POP(112) (CPython 3.11)
--
-- Purpose:
--   JUMP_IF_FALSE_OR_POP: if TOS false → jump (leave TOS); else pop and fall through.
--   JUMP_IF_TRUE_OR_POP: if TOS true → jump (leave TOS); else pop and fall through.
--
-- Usage:
--   Run after migrations. If any assertion fails, an exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000011';
    ID_TRUE_OBJ UUID := '00000000-0000-4000-b000-000000000010';

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

    const1_id UUID;
    const2_id UUID;
    result_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM JUMP_IF_FALSE_OR_POP / JUMP_IF_TRUE_OR_POP Opcode Test';
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
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
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

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 1);
    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const2_id, 2);

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: Functions exist
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_jump_if_false_or_pop' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_JUMP_IF_FALSE_OR_POP does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_jump_if_true_or_pop' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_JUMP_IF_TRUE_OR_POP does not exist';
    END IF;
    RAISE NOTICE '  ✓ Both functions exist';
    pass_count := pass_count + 1;

    -- Test 2: JUMP_IF_FALSE_OR_POP — False → jump (leave TOS), True → pop and fall through
    -- Bytecode: LOAD_CONST 0 (False), JUMP_IF_FALSE_OR_POP 2, LOAD_CONST 1, RETURN, LOAD_CONST 2, RETURN.
    -- 100,0 111,2 100,1 83,0 100,2 83,0. 111=0x6F. start_i=2, jump delta 2 → next_i=2+2+4=8.
    test_count := test_count + 1;
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[ID_FALSE_OBJ, const1_id, const2_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64006f026401530064025300'::bytea);

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
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: JUMP_IF_FALSE_OR_POP (False) returned NULL'; END IF;
    IF result_id != const2_id THEN RAISE EXCEPTION 'FAIL: Expected const2 (jump when False), got %', result_id; END IF;

    UPDATE public.py_tuple_object SET ob_item = ARRAY[ID_TRUE_OBJ, const1_id, const2_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: JUMP_IF_FALSE_OR_POP (True) returned NULL'; END IF;
    IF result_id != const1_id THEN RAISE EXCEPTION 'FAIL: Expected const1 (no jump when True), got %', result_id; END IF;

    RAISE NOTICE '  ✓ JUMP_IF_FALSE_OR_POP: False→jump→const2, True→fall through→const1';
    pass_count := pass_count + 1;

    -- Test 3: JUMP_IF_TRUE_OR_POP — True → jump (leave TOS), False → pop and fall through
    -- 100,0 112,2 100,1 83,0 100,2 83,0. 112=0x70.
    test_count := test_count + 1;
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640070026401530064025300'::bytea);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );
    UPDATE public.py_tuple_object SET ob_item = ARRAY[ID_TRUE_OBJ, const1_id, const2_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_code = code_obj_id, f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: JUMP_IF_TRUE_OR_POP (True) returned NULL'; END IF;
    IF result_id != const2_id THEN RAISE EXCEPTION 'FAIL: Expected const2 (jump when True), got %', result_id; END IF;

    UPDATE public.py_tuple_object SET ob_item = ARRAY[ID_FALSE_OBJ, const1_id, const2_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: JUMP_IF_TRUE_OR_POP (False) returned NULL'; END IF;
    IF result_id != const1_id THEN RAISE EXCEPTION 'FAIL: Expected const1 (no jump when False), got %', result_id; END IF;

    RAISE NOTICE '  ✓ JUMP_IF_TRUE_OR_POP: True→jump→const2, False→fall through→const1';
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
    RAISE NOTICE '✅ All JUMP_IF_FALSE_OR_POP/JUMP_IF_TRUE_OR_POP opcode tests passed!';
END $$;
