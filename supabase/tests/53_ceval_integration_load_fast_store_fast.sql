-- ============================================================================
-- Test: VM LOAD_FAST / STORE_FAST Integration (CPython 3.11)
--
-- Purpose:
--   Integration scenarios using LOAD_FAST(124) and STORE_FAST(125) in bytecode:
--   - x=1; return x  (LOAD_CONST + STORE_FAST + LOAD_FAST + RETURN_VALUE)
--   - a=10; b=20; return b  (multiple STORE_FAST, LOAD_FAST one slot)
--   - a=1; b=2; return a+b  (STORE_FAST x2, LOAD_FAST x2, BINARY_ADD, RETURN_VALUE)
--   - Frame isolation: two frames with independent f_fastlocals
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
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';

    test_count INTEGER := 0;
    pass_count INTEGER := 0;

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

    const0_id UUID;
    const1_id UUID;
    const10_id UUID;
    const20_id UUID;
    name_x_id UUID;
    name_a_id UUID;
    name_b_id UUID;
    result_id UUID;
    result_num NUMERIC;
    real_builtins_dict_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM LOAD_FAST / STORE_FAST Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- Setup: frame infrastructure (code with co_varnames for fast locals)
    -- ========================================================================
    RAISE NOTICE 'Setting up test environment...';

    SELECT md_dict INTO real_builtins_dict_id
    FROM public.py_module_object
    WHERE ob_base = ID_BUILTINS_MODULE;
    IF real_builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ dict not found';
    END IF;

    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');

    name_x_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_x_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_x_id, 'x');
    name_a_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_a_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_a_id, 'a');
    name_b_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_b_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_b_id, 'b');

    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, ARRAY[name_a_id, name_b_id]);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);

    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

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
        0, co_varnames_id, empty_tuple_id, empty_tuple_id
    );

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, real_builtins_dict_id
    );

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- ========================================================================
    -- Test 1: x=1; return x  (LOAD_CONST STORE_FAST LOAD_FAST RETURN_VALUE)
    -- ========================================================================
    RAISE NOTICE 'Test 1: bytecode x=1; return x...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);

    -- co_varnames for one local 'x'
    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, ARRAY[name_x_id]);

    -- Bytecode: LOAD_CONST(0) STORE_FAST(0) LOAD_FAST(0) RETURN_VALUE
    -- 100,0  125,0  124,0  83,0
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64007d007c005300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_varnames = co_varnames_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_fastlocals = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: x=1; return x returned NULL';
    END IF;
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: x=1; return x returned %, expected 1', result_id;
    END IF;

    RAISE NOTICE '  ✓ x=1; return x → 1';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 2: a=10; b=20; return b
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: bytecode a=10; b=20; return b...';
    test_count := test_count + 1;

    const10_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const10_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const10_id, 10);
    const20_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const20_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const20_id, 20);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const10_id, const20_id]);

    -- Bytecode: LOAD_CONST(0) STORE_FAST(0) LOAD_CONST(1) STORE_FAST(1) LOAD_FAST(1) RETURN_VALUE
    -- 64 00 7d 00  64 01 7d 01  7c 01 53 00
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64007d0064017d017c015300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_fastlocals = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: a=10; b=20; return b returned NULL';
    END IF;
    IF result_id != const20_id THEN
        RAISE EXCEPTION 'FAIL: return b returned %, expected 20', result_id;
    END IF;

    RAISE NOTICE '  ✓ a=10; b=20; return b → 20';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 3: a=1; b=2; return a+b
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: bytecode a=1; b=2; return a+b...';
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

    -- LOAD_CONST(0) STORE_FAST(0) LOAD_CONST(1) STORE_FAST(1) LOAD_FAST(0) LOAD_FAST(1) BINARY_ADD RETURN_VALUE
    -- 64 00 7d 00  64 01 7d 01  7c 00 7c 01  17 00 53 00
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64007d0064017d017c007c0117005300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_fastlocals = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: a=1; b=2; return a+b returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 3 THEN
        RAISE EXCEPTION 'FAIL: a+b returned %, expected 3', result_num;
    END IF;

    RAISE NOTICE '  ✓ a=1; b=2; return a+b → 3';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 4: Frame isolation — two frames, independent f_fastlocals
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Frame isolation (two frames, independent f_fastlocals)...';
    test_count := test_count + 1;

    DECLARE
        frame1_id UUID;
        frame2_id UUID;
        code1_id UUID;
        code2_id UUID;
        co_code1_id UUID;
        co_code2_id UUID;
        co_consts1_id UUID;
        co_consts2_id UUID;
        co_varnames1_id UUID;
        locals1_id UUID;
        locals2_id UUID;
        c1_id UUID;
        c2_id UUID;
        r1_id UUID;
        r2_id UUID;
    BEGIN
        c1_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (c1_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (c1_id, 100);
        c2_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (c2_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (c2_id, 200);

        co_consts1_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_consts1_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts1_id, ARRAY[c1_id]);
        co_consts2_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_consts2_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts2_id, ARRAY[c2_id]);

        co_varnames1_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames1_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames1_id, ARRAY[name_x_id]);

        co_code1_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_code1_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code1_id, E'\\x64007d007c005300'::bytea);
        co_code2_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_code2_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code2_id, E'\\x64007d007c005300'::bytea);

        code1_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (code1_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_code_object (
            ob_base, co_code, co_consts, co_names, co_filename, co_name,
            co_argcount, co_varnames, co_cellvars, co_freevars
        ) VALUES (
            code1_id, co_code1_id, co_consts1_id, empty_tuple_id, empty_str_id, empty_str_id,
            0, co_varnames1_id, empty_tuple_id, empty_tuple_id
        );
        code2_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (code2_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_code_object (
            ob_base, co_code, co_consts, co_names, co_filename, co_name,
            co_argcount, co_varnames, co_cellvars, co_freevars
        ) VALUES (
            code2_id, co_code2_id, co_consts2_id, empty_tuple_id, empty_str_id, empty_str_id,
            0, co_varnames1_id, empty_tuple_id, empty_tuple_id
        );

        locals1_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (locals1_id, ID_DICT_TYPE);
        INSERT INTO public.py_dict_object (ob_base) VALUES (locals1_id);
        locals2_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (locals2_id, ID_DICT_TYPE);
        INSERT INTO public.py_dict_object (ob_base) VALUES (locals2_id);

        frame1_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (frame1_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
        VALUES (frame1_id, code1_id, globals_dict_id, locals1_id, real_builtins_dict_id);

        frame2_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (frame2_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
        VALUES (frame2_id, code2_id, globals_dict_id, locals2_id, real_builtins_dict_id);

        r1_id := public.py_eval_frame(frame1_id);
        r2_id := public.py_eval_frame(frame2_id);

        IF r1_id IS NULL OR r2_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: One of the frames returned NULL';
        END IF;
        IF r1_id != c1_id THEN
            RAISE EXCEPTION 'FAIL: Frame 1 (x=100; return x) returned %, expected 100', r1_id;
        END IF;
        IF r2_id != c2_id THEN
            RAISE EXCEPTION 'FAIL: Frame 2 (x=200; return x) returned %, expected 200', r2_id;
        END IF;
    END;

    RAISE NOTICE '  ✓ Frame isolation: two frames return 100 and 200 independently';
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
    RAISE NOTICE '';

    RAISE NOTICE '✅ All LOAD_FAST / STORE_FAST integration tests passed!';

END $$;
