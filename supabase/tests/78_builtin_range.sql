-- ============================================================================
-- Test: range() Builtin + Range Iterator
--
-- Tests:
--   1. range/range_iterator types and functions exist
--   2. range(5) sum via for loop → 0+1+2+3+4 = 10
--   3. range(1, 10, 2) sum via for loop → 1+3+5+7+9 = 25
--   4. range(0) — empty range → sum = 0
-- ============================================================================

DO $$
DECLARE
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_BUILTINS_MODULE uuid := '00000000-0000-4000-b000-000000000002';

    test_count int := 0;
    pass_count int := 0;

    -- Shared helpers
    empty_str_id uuid;
    co_varnames_id uuid;
    co_cellvars_id uuid;
    co_freevars_id uuid;

    -- Frame setup
    frame_id uuid;
    code_obj_id uuid;
    co_code_id uuid;
    co_consts_id uuid;
    co_names_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;

    -- Constants
    const_0_id uuid;
    const_1_id uuid;
    const_2_id uuid;
    const_5_id uuid;
    const_10_id uuid;
    name_range_id uuid;

    -- Results
    res_id uuid;
    res_val numeric;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'range() Builtin Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup shared objects
    empty_str_id := public.py_str_from_text('');
    name_range_id := public.py_str_from_text('range');

    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, array[]::uuid[]);

    co_cellvars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_cellvars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_cellvars_id, array[]::uuid[]);

    co_freevars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_freevars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_freevars_id, array[]::uuid[]);

    SELECT md_dict INTO builtins_dict_id FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    -- Create shared constants
    const_0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_0_id, 0);

    const_1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_1_id, 1);

    const_2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_2_id, 2);

    const_5_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_5_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_5_id, 5);

    const_10_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_10_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_10_id, 10);

    -- ================================================================
    -- Test 1: Types and functions exist
    -- ================================================================
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_builtin_range') THEN
        RAISE EXCEPTION 'FAIL: py_builtin_range does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_range_tp_iter') THEN
        RAISE EXCEPTION 'FAIL: py_range_tp_iter does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_range_iterator_tp_iternext') THEN
        RAISE EXCEPTION 'FAIL: py_range_iterator_tp_iternext does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE tp_name = 'range') THEN
        RAISE EXCEPTION 'FAIL: range type does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE tp_name = 'range_iterator') THEN
        RAISE EXCEPTION 'FAIL: range_iterator type does not exist';
    END IF;
    RAISE NOTICE '  Test 1 PASS: range types and functions exist';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 2: total=0; for x in range(5): total += x → 10
    -- Bytecode: RESUME 0 | LOAD_CONST 0 (0) | STORE_FAST 0 (total) |
    --   PUSH_NULL | LOAD_NAME 0 (range) | LOAD_CONST 1 (5) | PRECALL 1 | CALL 1 |
    --   GET_ITER | FOR_ITER 6 | STORE_FAST 1 (x) | LOAD_FAST 0 | LOAD_FAST 1 |
    --   BINARY_OP 0 (+) | STORE_FAST 0 | JUMP_BACKWARD 7 | LOAD_FAST 0 | RETURN_VALUE
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const_0_id, const_5_id]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_range_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- Note: JUMP_BACKWARD uses absolute target (arg*2 = byte offset)
    -- FOR_ITER at byte 18 → JUMP_BACKWARD needs arg=9 (9*2=18)
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064007d00020065006401a601ab0144005d067d017c007c017a007d008c097c005300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, co_cellvars_id, co_freevars_id, 2);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame(frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: range(5) loop raised exception';
    END IF;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: range(5) loop returned NULL';
    END IF;
    SELECT long_value INTO res_val FROM public.py_long_object WHERE ob_base = res_id;
    IF res_val IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'FAIL: range(5) sum expected 10, got %', res_val;
    END IF;
    RAISE NOTICE '  Test 2 PASS: for x in range(5): total += x → 10';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 3: total=0; for x in range(1, 10, 2): total += x → 25
    -- Bytecode: RESUME 0 | LOAD_CONST 0 (0) | STORE_FAST 0 (total) |
    --   PUSH_NULL | LOAD_NAME 0 (range) | LOAD_CONST 1 (1) | LOAD_CONST 2 (10) | LOAD_CONST 3 (2) |
    --   PRECALL 3 | CALL 3 | GET_ITER | FOR_ITER 6 | STORE_FAST 1 | LOAD_FAST 0 | LOAD_FAST 1 |
    --   BINARY_OP 0 | STORE_FAST 0 | JUMP_BACKWARD 7 | LOAD_FAST 0 | RETURN_VALUE
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const_0_id, const_1_id, const_10_id, const_2_id]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_range_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- Note: JUMP_BACKWARD uses absolute target (arg*2 = byte offset)
    -- FOR_ITER at byte 22 → JUMP_BACKWARD needs arg=11 (11*2=22)
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064007d0002006500640164026403a603ab0344005d067d017c007c017a007d008c0b7c005300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, co_cellvars_id, co_freevars_id, 2);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame(frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: range(1,10,2) loop raised exception';
    END IF;
    SELECT long_value INTO res_val FROM public.py_long_object WHERE ob_base = res_id;
    IF res_val IS DISTINCT FROM 25 THEN
        RAISE EXCEPTION 'FAIL: range(1,10,2) sum expected 25, got %', res_val;
    END IF;
    RAISE NOTICE '  Test 3 PASS: for x in range(1, 10, 2): total += x → 25';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 4: range(0) — empty, sum stays 0
    -- Same bytecode as test 2 but with const 0 as range arg
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const_0_id, const_0_id]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_range_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- Same bytecode as test 2 (JUMP_BACKWARD arg=9 for absolute target byte 18)
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064007d00020065006401a601ab0144005d067d017c007c017a007d008c097c005300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, co_cellvars_id, co_freevars_id, 2);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame(frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: range(0) loop raised exception';
    END IF;
    SELECT long_value INTO res_val FROM public.py_long_object WHERE ob_base = res_id;
    IF res_val IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'FAIL: range(0) sum expected 0, got %', res_val;
    END IF;
    RAISE NOTICE '  Test 4 PASS: for x in range(0): total += x → 0 (empty range)';
    pass_count := pass_count + 1;

    -- ================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE 'All range builtin tests passed!';
END $$;
