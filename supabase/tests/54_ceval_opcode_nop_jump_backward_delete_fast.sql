-- ============================================================================
-- Test: VM NOP(9), JUMP_BACKWARD(140), DELETE_FAST(126) Opcode (CPython 3.11)
--
-- Purpose:
--   NOP(9): no-op; f_lasti advances (unlike CACHE 0).
--   JUMP_BACKWARD(140): oparg = target instruction offset (bytes = arg*2).
--   DELETE_FAST(126): set fast local slot to NULL; no stack pop.
--
-- Usage:
--   Run after migrations. If any assertion fails, an exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
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
    co_varnames_id UUID;
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    name_x_id UUID;

    const0_id UUID;
    const1_id UUID;
    result_id UUID;
    fast_arr uuid[];
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM NOP / JUMP_BACKWARD / DELETE_FAST Opcode Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- Setup
    -- ========================================================================
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');

    name_x_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_x_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_x_id, 'x');

    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, ARRAY[name_x_id]);

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
        0, co_varnames_id, empty_tuple_id, empty_tuple_id
    );

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);

    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- ========================================================================
    -- Test 1: py_opcode_DELETE_FAST exists
    -- ========================================================================
    RAISE NOTICE 'Test 1: py_opcode_DELETE_FAST exists...';
    test_count := test_count + 1;

    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_delete_fast' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_DELETE_FAST does not exist';
    END IF;

    RAISE NOTICE '  ✓ py_opcode_DELETE_FAST exists';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 2: DELETE_FAST sets slot to NULL (STORE_FAST then DELETE_FAST then LOAD_FAST → error)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: DELETE_FAST sets f_fastlocals slot to NULL...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 42);

    UPDATE public.py_frame_object SET f_fastlocals = array[]::uuid[] WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();
    PERFORM public.py_stack_push(frame_id, const0_id);
    PERFORM public.py_opcode_STORE_FAST(frame_id, 0);
    PERFORM public.py_opcode_DELETE_FAST(frame_id, 0);

    SELECT f_fastlocals INTO fast_arr FROM public.py_frame_object WHERE ob_base = frame_id;
    IF coalesce(array_length(fast_arr, 1), 0) < 1 THEN
        RAISE EXCEPTION 'FAIL: f_fastlocals too short after DELETE_FAST(0)';
    END IF;
    IF fast_arr[1] IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: f_fastlocals[1] should be NULL after DELETE_FAST(0), got %', fast_arr[1];
    END IF;

    PERFORM public.py_opcode_LOAD_FAST(frame_id, 0);
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Expected py_err_occurred() after LOAD_FAST(0) following DELETE_FAST(0)';
    END IF;

    RAISE NOTICE '  ✓ DELETE_FAST sets slot to NULL; LOAD_FAST then raises';
    pass_count := pass_count + 1;
    PERFORM public.py_err_clear();

    -- ========================================================================
    -- Test 3: DELETE_FAST negative var_num raises
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: DELETE_FAST with negative var_num raises...';
    test_count := test_count + 1;

    BEGIN
        PERFORM public.py_opcode_DELETE_FAST(frame_id, -1);
        RAISE EXCEPTION 'FAIL: Expected exception on DELETE_FAST(-1)';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM NOT LIKE '%non-negative%' THEN
                RAISE EXCEPTION 'FAIL: Expected "non-negative", got: %', SQLERRM;
            END IF;
    END;

    RAISE NOTICE '  ✓ DELETE_FAST with negative var_num correctly raises';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 4: py_eval_frame with NOP — LOAD_CONST 0, NOP, RETURN_VALUE → const0
    -- Bytecode: 100,0 9,0 83,0 = \x640009005300
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: py_eval_frame with NOP(9) advances and returns const0...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640009005300'::bytea);

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

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_eval_frame with NOP returned NULL';
    END IF;
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: py_eval_frame with NOP returned %, expected const0 %', result_id, const0_id;
    END IF;

    RAISE NOTICE '  ✓ NOP(9) no-op; execution advances and returns correct value';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 5: py_eval_frame with JUMP_BACKWARD — relative backward jump
    -- CPython 3.11: JUMP_BACKWARD oparg = relative backward offset in instructions.
    -- target = start_i + 2 - arg * 2
    -- Bytecode: JUMP_FORWARD 2 (0-1) | LOAD_CONST 1 (2-3) | RETURN_VALUE (4-5) |
    --           LOAD_CONST 0 (6-7) | JUMP_BACKWARD 4 (8-9)
    -- Flow: 0→6→8→2→4(return const1=99)
    -- JUMP_FORWARD arg=2: next_i = 0+2+2*2 = 6
    -- JUMP_BACKWARD arg=4: next_i = 8+2-4*2 = 2
    -- Hex: 6e02 6401 5300 6400 8c04
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: py_eval_frame with JUMP_BACKWARD(140) relative backward jump...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 0);

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 99);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('6e026401530064008c04', 'hex'));

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

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_eval_frame with JUMP_BACKWARD returned NULL';
    END IF;
    IF result_id != const1_id THEN
        RAISE EXCEPTION 'FAIL: py_eval_frame with JUMP_BACKWARD returned %, expected const1 %', result_id, const1_id;
    END IF;

    RAISE NOTICE '  ✓ JUMP_BACKWARD(140) relative backward jump; returns correct value';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 6: py_eval_frame with DELETE_FAST — STORE_FAST 0, DELETE_FAST 0, LOAD_FAST 0 → VM error
    -- Bytecode: LOAD_CONST 0, STORE_FAST 0, DELETE_FAST 0, LOAD_FAST 0, RETURN_VALUE
    -- 100,0 125,0 126,0 124,0 83,0 = \x64007d007e007c005300
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: py_eval_frame with DELETE_FAST; LOAD_FAST after delete sets error...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 42);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64007d007e007c005300'::bytea);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, co_varnames_id, empty_tuple_id, empty_tuple_id
    );

    UPDATE public.py_frame_object SET f_code = code_obj_id, f_valuestack = array[]::uuid[], f_fastlocals = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Expected NULL return (exception) after DELETE_FAST then LOAD_FAST, got %', result_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Expected py_err_occurred() after DELETE_FAST then LOAD_FAST';
    END IF;

    RAISE NOTICE '  ✓ DELETE_FAST in bytecode; LOAD_FAST after delete triggers VM error';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Summary
    -- ========================================================================
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

    RAISE NOTICE '✅ All NOP / JUMP_BACKWARD / DELETE_FAST opcode tests passed!';

END $$;
