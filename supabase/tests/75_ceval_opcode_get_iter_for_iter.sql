-- ============================================================================
-- Test: VM GET_ITER(68) + FOR_ITER(93) Opcodes (CPython 3.11)
--
-- Purpose:
--   GET_ITER: pop TOS, call tp_iter to create iterator, push iterator.
--   FOR_ITER: peek TOS (iterator), call tp_iternext.
--     - value returned: push value
--     - StopIteration: clear err, pop iterator, jump past loop
--
-- Tests:
--   1. Function existence checks
--   2. Iterate list: total=0; for x in [1,2,3]: total += x → 6
--   3. Iterate tuple: total=0; for x in (10,20): total += x → 30
--   4. Empty list: for x in []: total=1 → total stays 0
--   5. GET_ITER on int → TypeError
-- ============================================================================

DO $$
DECLARE
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_STOP_ITERATION_TYPE uuid := '00000000-0000-4000-a000-00000000002a';
    ID_TYPE_ERROR_TYPE uuid := '00000000-0000-4000-a000-000000000022';

    test_count int := 0;
    pass_count int := 0;

    -- Shared helpers
    empty_tuple_id uuid;
    empty_str_id uuid;

    -- Per-test variables
    co_consts_id uuid;
    co_code_id uuid;
    co_varnames_id uuid;
    code_obj_id uuid;
    frame_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;
    co_names_id uuid;

    const_0_id uuid;
    const_1_id uuid;
    const_2_id uuid;
    const_3_id uuid;
    const_10_id uuid;
    const_20_id uuid;
    const_42_id uuid;

    var_total_id uuid;
    var_x_id uuid;

    res_id uuid;
    res_val numeric;
    exc_type uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM GET_ITER(68) + FOR_ITER(93) Opcode Test (CPython 3.11)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup shared objects
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    empty_str_id := public.py_str_from_text('');

    -- Create integer constants
    const_0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_0_id, 0);

    const_1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_1_id, 1);

    const_2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_2_id, 2);

    const_3_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_3_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_3_id, 3);

    const_10_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_10_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_10_id, 10);

    const_20_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_20_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_20_id, 20);

    const_42_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_42_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_42_id, 42);

    -- Create variable name strings
    var_total_id := public.py_str_from_text('total');
    var_x_id := public.py_str_from_text('x');

    RAISE NOTICE '  Setup complete';
    RAISE NOTICE '';

    -- ================================================================
    -- Test 1: py_opcode_GET_ITER exists
    -- ================================================================
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_get_iter' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_GET_ITER does not exist';
    END IF;
    RAISE NOTICE '  Test 1 PASS: py_opcode_GET_ITER exists';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 2: py_opcode_FOR_ITER exists
    -- ================================================================
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_for_iter' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_FOR_ITER does not exist';
    END IF;
    RAISE NOTICE '  Test 2 PASS: py_opcode_FOR_ITER exists';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 3: Iterate list — total=0; for x in [1,2,3]: total += x → 6
    -- Bytecode: RESUME 0 | LOAD_CONST 0 | STORE_FAST 0 | LOAD_CONST 1 | LOAD_CONST 2 | LOAD_CONST 3 |
    --           BUILD_LIST 3 | GET_ITER 0 | FOR_ITER 6 | STORE_FAST 1 | LOAD_FAST 0 | LOAD_FAST 1 |
    --           BINARY_ADD 0 | STORE_FAST 0 | JUMP_BACKWARD 8 | LOAD_FAST 0 | RETURN_VALUE 0
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- co_consts = (0, 1, 2, 3)
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const_0_id, const_1_id, const_2_id, const_3_id]);

    -- co_varnames = (total, x)
    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, ARRAY[var_total_id, var_x_id]);

    -- co_names (empty)
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);

    -- co_code
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064007d00640164026403670344005d067d017c007c0117007d008c087c005300', 'hex'));

    -- code object
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, empty_tuple_id, empty_tuple_id);

    -- frame
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
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame(frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: iterate list raised exception';
    END IF;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: iterate list returned NULL';
    END IF;
    SELECT long_value INTO res_val FROM public.py_long_object WHERE ob_base = res_id;
    IF res_val IS DISTINCT FROM 6 THEN
        RAISE EXCEPTION 'FAIL: iterate list expected 6, got %', res_val;
    END IF;
    RAISE NOTICE '  Test 3 PASS: for x in [1,2,3]: total += x → 6';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 4: Iterate tuple — total=0; for x in (10,20): total += x → 30
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const_0_id, const_10_id, const_20_id]);

    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, ARRAY[var_total_id, var_x_id]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064007d0064016402660244005d067d017c007c0117007d008c077c005300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, empty_tuple_id, empty_tuple_id);

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
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame(frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: iterate tuple raised exception';
    END IF;
    SELECT long_value INTO res_val FROM public.py_long_object WHERE ob_base = res_id;
    IF res_val IS DISTINCT FROM 30 THEN
        RAISE EXCEPTION 'FAIL: iterate tuple expected 30, got %', res_val;
    END IF;
    RAISE NOTICE '  Test 4 PASS: for x in (10,20): total += x → 30';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 5: Empty list — total stays 0
    -- for x in []: total = 1; return total → should return 0
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const_0_id, const_1_id]);

    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, ARRAY[var_total_id, var_x_id]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064007d00670044005d047d0164017d008c057c005300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, empty_tuple_id, empty_tuple_id);

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
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame(frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: empty list iteration raised exception';
    END IF;
    SELECT long_value INTO res_val FROM public.py_long_object WHERE ob_base = res_id;
    IF res_val IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'FAIL: empty list expected 0, got %', res_val;
    END IF;
    RAISE NOTICE '  Test 5 PASS: for x in []: total=1 → total stays 0';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 6: GET_ITER on int → TypeError
    -- RESUME 0 | LOAD_CONST 0 (42) | GET_ITER | RETURN_VALUE
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const_42_id]);

    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, array[]::uuid[]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('9700640044005300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, empty_tuple_id, empty_tuple_id);

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
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame(frame_id);
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: GET_ITER on int should raise TypeError';
    END IF;
    SELECT exc_type_id INTO exc_type FROM public.py_exception_state WHERE id = '00000000-0000-4000-e000-000000000001';
    IF exc_type IS DISTINCT FROM ID_TYPE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: GET_ITER on int expected TypeError, got %', exc_type;
    END IF;
    RAISE NOTICE '  Test 6 PASS: GET_ITER on int → TypeError';
    pass_count := pass_count + 1;

    -- ================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE 'All GET_ITER(68) + FOR_ITER(93) opcode tests passed!';
END $$;
