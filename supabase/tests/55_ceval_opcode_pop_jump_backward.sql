-- ============================================================================
-- Test: VM POP_JUMP_BACKWARD_IF_FALSE(175), POP_JUMP_BACKWARD_IF_TRUE(176) (CPython 3.11)
--
-- Purpose:
--   POP_JUMP_BACKWARD_IF_FALSE: pop TOS; if false, jump to target instruction offset (oparg*2).
--   POP_JUMP_BACKWARD_IF_TRUE: pop TOS; if true, jump to target instruction offset (oparg*2).
--
-- Usage:
--   Run after migrations. If any assertion fails, an exception is raised.
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
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
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;

    const1_id UUID;
    const2_id UUID;
    result_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM POP_JUMP_BACKWARD Opcode Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
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
    RAISE NOTICE 'Test 1: py_opcode_POP_JUMP_BACKWARD_IF_FALSE/IF_TRUE exist...';
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_pop_jump_backward_if_false' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_POP_JUMP_BACKWARD_IF_FALSE does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_pop_jump_backward_if_true' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_POP_JUMP_BACKWARD_IF_TRUE does not exist';
    END IF;
    RAISE NOTICE '  ✓ Both functions exist';
    pass_count := pass_count + 1;

    -- Test 2: POP_JUMP_BACKWARD_IF_FALSE — TOS False → jump to target; TOS True → no jump
    -- Bytecode: LOAD_CONST 0 (False), POP_JUMP_BACKWARD_IF_FALSE 4 (jump to instr 4 = byte 8 = LOAD_CONST 2),
    --           LOAD_CONST 1, RETURN (4-7), LOAD_CONST 2, RETURN (8-11).
    -- False → jump to 8 → LOAD_CONST 2, RETURN → const2. True → no jump → LOAD_CONST 1, RETURN → const1.
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: POP_JUMP_BACKWARD_IF_FALSE — False jumps, True does not...';
    test_count := test_count + 1;

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 1);

    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const2_id, 2);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[ID_FALSE_OBJ, const1_id, const2_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- 100,0 175,4 100,1 83,0 100,2 83,0 = \x6400af046401530064025300 (jump to instr 4 = byte 8 = LOAD_CONST 2)
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x6400af046401530064025300'::bytea);

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
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: POP_JUMP_BACKWARD_IF_FALSE (False) returned NULL'; END IF;
    IF result_id != const2_id THEN RAISE EXCEPTION 'FAIL: Expected const2 (jump when False), got %', result_id; END IF;

    -- Same bytecode but consts[0] = True → no jump → return const1
    UPDATE public.py_tuple_object SET ob_item = ARRAY[ID_TRUE_OBJ, const1_id, const2_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: POP_JUMP_BACKWARD_IF_FALSE (True) returned NULL'; END IF;
    IF result_id != const1_id THEN RAISE EXCEPTION 'FAIL: Expected const1 (no jump when True), got %', result_id; END IF;

    RAISE NOTICE '  ✓ POP_JUMP_BACKWARD_IF_FALSE: False→jump→const2, True→no jump→const1';
    pass_count := pass_count + 1;

    -- Test 3: POP_JUMP_BACKWARD_IF_TRUE — TOS True → jump; TOS False → no jump
    -- Bytecode: LOAD_CONST 0, POP_JUMP_BACKWARD_IF_TRUE 4, LOAD_CONST 1, RETURN, LOAD_CONST 2, RETURN.
    -- True → jump to 8 (LOAD_CONST 2) → const2. False → no jump → const1.
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: POP_JUMP_BACKWARD_IF_TRUE — True jumps, False does not...';
    test_count := test_count + 1;

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- 100,0 176,4 100,1 83,0 100,2 83,0 = \x6400b0046401530064025300
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x6400b0046401530064025300'::bytea);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );

    UPDATE public.py_tuple_object SET ob_item = ARRAY[ID_TRUE_OBJ, const1_id, const2_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_code = code_obj_id, f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: POP_JUMP_BACKWARD_IF_TRUE (True) returned NULL'; END IF;
    IF result_id != const2_id THEN RAISE EXCEPTION 'FAIL: Expected const2 (jump when True), got %', result_id; END IF;

    UPDATE public.py_tuple_object SET ob_item = ARRAY[ID_FALSE_OBJ, const1_id, const2_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: POP_JUMP_BACKWARD_IF_TRUE (False) returned NULL'; END IF;
    IF result_id != const1_id THEN RAISE EXCEPTION 'FAIL: Expected const1 (no jump when False), got %', result_id; END IF;

    RAISE NOTICE '  ✓ POP_JUMP_BACKWARD_IF_TRUE: True→jump→const2, False→no jump→const1';
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

    RAISE NOTICE '✅ All POP_JUMP_BACKWARD opcode tests passed!';

END $$;
