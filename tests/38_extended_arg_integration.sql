-- ============================================================================
-- Test: EXTENDED_ARG Bytecode Integration
--
-- Purpose:
--   CPython EXTENDED_ARG(144) 고증. py_eval_frame에서 EXTENDED_ARG 연쇄를
--   읽어 다음 opcode의 operand를 (extended << 8) | arg 로 확장하는지 검증.
--
--   - 단일/연쇄 EXTENDED_ARG, effective arg > 255, JUMP 확장, 통합 시나리오
--
-- Usage:
--   Run after migrations. If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE    uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';

    test_count int := 0;
    pass_count int := 0;

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
    const_arr uuid[];
    k int;
    const_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'EXTENDED_ARG Bytecode Integration Test';
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

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 10);

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 20);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- EXTENDED_ARG 0 (144,0); LOAD_CONST 1 (100,1); RETURN_VALUE (83,0)
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('900064015300', 'hex'));

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

    -- Test 1: EXTENDED_ARG 0 + LOAD_CONST 1 → effective arg 1 → push consts[1], RETURN → 20
    RAISE NOTICE 'Test 1: EXTENDED_ARG 0 + LOAD_CONST 1 returns consts[1] (20)...';
    test_count := test_count + 1;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: EXTENDED_ARG bytecode returned NULL';
    END IF;
    IF result_id IS DISTINCT FROM const1_id THEN
        RAISE EXCEPTION 'FAIL: expected const1 (20), got %', result_id;
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 20 THEN
        RAISE EXCEPTION 'FAIL: expected value 20, got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ EXTENDED_ARG + LOAD_CONST 1 returns 20';
    pass_count := pass_count + 1;

    -- Test 2: EXTENDED_ARG 1 + LOAD_CONST 0 → effective arg 256 → co_consts[256] (operand > 255)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: EXTENDED_ARG 1 + LOAD_CONST 0 → effective 256, returns consts[256] (999)...';
    test_count := test_count + 1;
    const_arr := array[]::uuid[];
    FOR k IN 0..255 LOOP
        const_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (const_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_id, 0);
        const_arr := array_append(const_arr, const_id);
    END LOOP;
    const_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_id, 999);
    const_arr := array_append(const_arr, const_id);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, const_arr);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- EXTENDED_ARG 1 (144,1); LOAD_CONST 0 (100,0) → effective 256; RETURN_VALUE (83,0)
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('900164005300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: Test 2 EXTENDED_ARG 1 + LOAD_CONST 0 returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 999 THEN
        RAISE EXCEPTION 'FAIL: Test 2 expected 999 (consts[256]), got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ EXTENDED_ARG 1 + LOAD_CONST 0 returns 999 (index 256)';
    pass_count := pass_count + 1;

    -- Test 3: EXTENDED_ARG + JUMP_FORWARD (extended jump over padding → LOAD_CONST 1, return 99)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: EXTENDED_ARG 0 + JUMP_FORWARD 3 skips 6 bytes, returns consts[1] (99)...';
    test_count := test_count + 1;
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 99);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- LOAD_CONST 0 (1); EXTENDED_ARG 0, JUMP_FORWARD 3 (skip 6); [6 bytes pad]; LOAD_CONST 1 (99); RETURN
    -- 64 00  90 00 6E 03  64 00 01 00 64 00  64 01 53 00
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640090006E0364000100640064015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: Test 3 EXTENDED_ARG + JUMP_FORWARD returned NULL';
    END IF;
    IF result_id IS DISTINCT FROM const1_id THEN
        RAISE EXCEPTION 'FAIL: Test 3 expected const1 (99), got %', result_id;
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 99 THEN
        RAISE EXCEPTION 'FAIL: Test 3 expected 99, got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ EXTENDED_ARG + JUMP_FORWARD returns 99';
    pass_count := pass_count + 1;

    -- Test 4: Integrated — LOAD_CONST 0 (10), EXTENDED_ARG 0 LOAD_CONST 1 (20), BINARY_ADD, RETURN → 30
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Integrated LOAD_CONST + EXTENDED_ARG LOAD_CONST + BINARY_ADD → 30...';
    test_count := test_count + 1;
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 10);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 20);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- LOAD_CONST 0; EXTENDED_ARG 0 LOAD_CONST 1; BINARY_ADD 23; RETURN_VALUE
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64009000640117005300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: Test 4 integrated bytecode returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 30 THEN
        RAISE EXCEPTION 'FAIL: Test 4 expected 30 (10+20), got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ Integrated EXTENDED_ARG + BINARY_ADD returns 30';
    pass_count := pass_count + 1;

    -- Test 5: Two EXTENDED_ARG (EXTENDED_ARG 0, EXTENDED_ARG 1, LOAD_CONST 0 → effective 256)
    -- Accumulation: ext=0 → ext=(0<<8)|1=1 → effective=(1<<8)|0=256
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Two EXTENDED_ARG (0,1) + LOAD_CONST 0 → effective 256, returns consts[256]...';
    test_count := test_count + 1;
    const_arr := array[]::uuid[];
    FOR k IN 0..255 LOOP
        const_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (const_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_id, 0);
        const_arr := array_append(const_arr, const_id);
    END LOOP;
    const_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_id, 777);
    const_arr := array_append(const_arr, const_id);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, const_arr);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- EXTENDED_ARG 0; EXTENDED_ARG 1; LOAD_CONST 0 → effective 256; RETURN_VALUE
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('9000900164005300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: Test 5 two EXTENDED_ARG returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 777 THEN
        RAISE EXCEPTION 'FAIL: Test 5 expected 777 (consts[256]), got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ Two EXTENDED_ARG + LOAD_CONST 0 returns 777 (index 256)';
    pass_count := pass_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'EXTENDED_ARG integration: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
