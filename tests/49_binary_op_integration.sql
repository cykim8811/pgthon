-- ============================================================================
-- Test: BINARY_OP(122) Bytecode Integration (CPython 3.11)
--
-- Purpose:
--   py_eval_frame으로 opcode 122 (BINARY_OP) + 하위 opcode(NB_*) 동작 검증.
--   - NB_ADD(0): 1+2 → 3
--   - NB_SUBTRACT(10): 5-3 → 2
--   - NB_MULTIPLY(5): 2*3 → 6
--   - 미지원 sub-op (e.g. NB_AND 1): TypeError
--
-- Bytecode: LOAD_CONST(0) LOAD_CONST(1) BINARY_OP(oparg) RETURN_VALUE
--   = 100,0, 100,1, 122,oparg, 83,0
--   oparg 0  → \x640064017a005300
--   oparg 10 → \x640064017a0a5300
--   oparg 5  → \x640064017a055300
--   oparg 1  → \x640064017a015300 (unsupported)
--
-- Usage:
--   Run after migration 20260114240324_opcode_binary_op.sql.
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE   uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE   uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE  uuid := '00000000-0000-4000-a000-000000000006';

    test_count int := 0;
    pass_count int := 0;
    fail_count int := 0;

    frame_id uuid;
    code_obj_id uuid;
    co_code_id uuid;
    co_names_id uuid;
    co_consts_id uuid;
    empty_tuple_id uuid;
    empty_str_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;

    const0_id uuid;
    const1_id uuid;
    result_id uuid;
    result_num numeric;
    exc_type_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'BINARY_OP(122) Bytecode Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);

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
        code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- -------------------------------------------------------------------------
    -- Test 1: BINARY_OP(0) NB_ADD — 1+2 → 3
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 1: bytecode BINARY_OP(0) 1+2 → 3...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 2);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064017a005300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);

    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: BINARY_OP(0) 1+2 returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 3 THEN
        RAISE EXCEPTION 'FAIL: BINARY_OP(0) 1+2 result %, expected 3', result_num;
    END IF;
    RAISE NOTICE '  ✓ BINARY_OP(0) 1+2 = 3';
    pass_count := pass_count + 1;

    -- -------------------------------------------------------------------------
    -- Test 2: BINARY_OP(10) NB_SUBTRACT — 5-3 → 2
    -- -------------------------------------------------------------------------
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: bytecode BINARY_OP(10) 5-3 → 2...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 5);

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 3);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064017a0a5300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);

    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: BINARY_OP(10) 5-3 returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 2 THEN
        RAISE EXCEPTION 'FAIL: BINARY_OP(10) 5-3 result %, expected 2', result_num;
    END IF;
    RAISE NOTICE '  ✓ BINARY_OP(10) 5-3 = 2';
    pass_count := pass_count + 1;

    -- -------------------------------------------------------------------------
    -- Test 3: BINARY_OP(5) NB_MULTIPLY — 2*3 → 6
    -- -------------------------------------------------------------------------
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: bytecode BINARY_OP(5) 2*3 → 6...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 2);

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 3);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064017a055300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);

    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: BINARY_OP(5) 2*3 returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 6 THEN
        RAISE EXCEPTION 'FAIL: BINARY_OP(5) 2*3 result %, expected 6', result_num;
    END IF;
    RAISE NOTICE '  ✓ BINARY_OP(5) 2*3 = 6';
    pass_count := pass_count + 1;

    -- -------------------------------------------------------------------------
    -- Test 4: BINARY_OP(4) NB_MATRIX_MULTIPLY — unsupported sub-op → TypeError
    -- bytecode: LOAD_CONST(0) LOAD_CONST(1) BINARY_OP(4) RETURN_VALUE
    --   = 0x6400 6401 7a04 5300
    -- -------------------------------------------------------------------------
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: bytecode BINARY_OP(4) unsupported sub-op raises TypeError...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 2);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064017a045300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL OR NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: BINARY_OP(4) should raise TypeError, got result_id=%', result_id;
    END IF;
    SELECT g.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() g LIMIT 1;
    IF exc_type_id IS DISTINCT FROM '00000000-0000-4000-a000-000000000022' THEN
        RAISE EXCEPTION 'FAIL: BINARY_OP(4) should set TypeError, got exc_type_id %', exc_type_id;
    END IF;
    PERFORM public.py_err_clear();
    RAISE NOTICE '  ✓ BINARY_OP(4) raises TypeError';
    pass_count := pass_count + 1;

    -- -------------------------------------------------------------------------
    -- Summary
    -- -------------------------------------------------------------------------
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total: %  Passed: %  Failed: %', test_count, pass_count, fail_count;
    RAISE NOTICE '';

    IF fail_count > 0 THEN
        RAISE EXCEPTION 'FAIL: % test(s) failed', fail_count;
    END IF;

    RAISE NOTICE '✓ All BINARY_OP(122) bytecode integration tests passed!';
END $$;
