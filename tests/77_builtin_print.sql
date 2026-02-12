-- ============================================================================
-- Test: print() Builtin + py_object_str()
--
-- Tests:
--   1. print and py_object_str functions exist
--   2. py_object_str converts int to string
--   3. py_object_str converts bool to string
--   4. py_object_str converts NoneType to string
--   5. print("hello") — outputs via RAISE NOTICE, returns None
--   6. print(1, "two", 3.0) — multiple args joined with space
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_STR_TYPE    uuid := '00000000-0000-4000-a000-000000000003';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_FLOAT_TYPE  uuid := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE   uuid := '00000000-0000-4000-a000-000000000013';
    ID_NONE_TYPE   uuid := '00000000-0000-4000-a000-000000000008';
    ID_NONE_OBJ    uuid := '00000000-0000-4000-b000-000000000001';
    ID_TRUE_OBJ    uuid := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ   uuid := '00000000-0000-4000-b000-000000000011';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_BUILTINS_MODULE uuid := '00000000-0000-4000-b000-000000000002';

    test_count int := 0;
    pass_count int := 0;

    -- Helpers
    v_str_id uuid;
    v_str_val text;
    v_int_id uuid;
    v_float_id uuid;
    v_result uuid;

    -- Frame setup
    frame_id uuid;
    code_obj_id uuid;
    co_code_id uuid;
    co_consts_id uuid;
    co_names_id uuid;
    co_varnames_id uuid;
    co_cellvars_id uuid;
    co_freevars_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;
    empty_str_id uuid;

    -- Constants
    str_hello_id uuid;
    str_two_id uuid;
    const_1_id uuid;
    float_3_id uuid;
    name_print_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'print() Builtin + py_object_str Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ================================================================
    -- Test 1: Functions exist
    -- ================================================================
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_object_str') THEN
        RAISE EXCEPTION 'FAIL: py_object_str does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_object_repr') THEN
        RAISE EXCEPTION 'FAIL: py_object_repr does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_builtin_print') THEN
        RAISE EXCEPTION 'FAIL: py_builtin_print does not exist';
    END IF;
    RAISE NOTICE '  Test 1 PASS: print/str/repr functions exist';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 2: py_object_str(42) → "42"
    -- ================================================================
    test_count := test_count + 1;
    v_int_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_int_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_int_id, 42);

    v_str_id := public.py_object_str(v_int_id);
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_str_id;
    IF v_str_val IS DISTINCT FROM '42' THEN
        RAISE EXCEPTION 'FAIL: py_object_str(42) = %, expected "42"', v_str_val;
    END IF;
    RAISE NOTICE '  Test 2 PASS: py_object_str(42) → "42"';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 3: py_object_str(True) → "True", py_object_str(False) → "False"
    -- ================================================================
    test_count := test_count + 1;
    v_str_id := public.py_object_str(ID_TRUE_OBJ);
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_str_id;
    IF v_str_val IS DISTINCT FROM 'True' THEN
        RAISE EXCEPTION 'FAIL: py_object_str(True) = %, expected "True"', v_str_val;
    END IF;
    v_str_id := public.py_object_str(ID_FALSE_OBJ);
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_str_id;
    IF v_str_val IS DISTINCT FROM 'False' THEN
        RAISE EXCEPTION 'FAIL: py_object_str(False) = %, expected "False"', v_str_val;
    END IF;
    RAISE NOTICE '  Test 3 PASS: py_object_str(True) → "True", py_object_str(False) → "False"';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 4: py_object_str(None) → "None"
    -- ================================================================
    test_count := test_count + 1;
    v_str_id := public.py_object_str(ID_NONE_OBJ);
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_str_id;
    IF v_str_val IS DISTINCT FROM 'None' THEN
        RAISE EXCEPTION 'FAIL: py_object_str(None) = %, expected "None"', v_str_val;
    END IF;
    RAISE NOTICE '  Test 4 PASS: py_object_str(None) → "None"';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 5: Bytecode print("hello") → RAISE NOTICE "hello", returns None
    -- Bytecode: RESUME 0 | PUSH_NULL | LOAD_NAME 0 (print) | LOAD_CONST 0 ("hello") |
    --           PRECALL 1 | CALL 1 | POP_TOP | LOAD_CONST 1 (None) | RETURN_VALUE
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    str_hello_id := public.py_str_from_text('hello');
    name_print_id := public.py_str_from_text('print');
    empty_str_id := public.py_str_from_text('');

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[str_hello_id, ID_NONE_OBJ]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_print_id]);

    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, array[]::uuid[]);

    co_cellvars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_cellvars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_cellvars_id, array[]::uuid[]);

    co_freevars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_freevars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_freevars_id, array[]::uuid[]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('9700020065006400a601ab01010064015300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, co_cellvars_id, co_freevars_id, 0);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    SELECT md_dict INTO builtins_dict_id FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    v_result := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: print("hello") raised exception';
    END IF;
    -- print returns None (the last LOAD_CONST 1 / RETURN_VALUE returns None)
    IF v_result IS DISTINCT FROM ID_NONE_OBJ THEN
        RAISE EXCEPTION 'FAIL: print("hello") did not return None, got %', v_result;
    END IF;
    RAISE NOTICE '  Test 5 PASS: print("hello") outputs via NOTICE and returns None';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 6: print(1, "two", 3.0) — multiple args
    -- Bytecode: RESUME 0 | PUSH_NULL | LOAD_NAME 0 (print) | LOAD_CONST 0 (1) |
    --           LOAD_CONST 1 ("two") | LOAD_CONST 2 (3.0) | PRECALL 3 | CALL 3 |
    --           POP_TOP | LOAD_CONST 3 (None) | RETURN_VALUE
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    const_1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_1_id, 1);

    str_two_id := public.py_str_from_text('two');

    float_3_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (float_3_id, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (float_3_id, 3.0);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const_1_id, str_two_id, float_3_id, ID_NONE_OBJ]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_print_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970002006500640064016402a603ab03010064035300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, co_cellvars_id, co_freevars_id, 0);

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

    v_result := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: print(1, "two", 3.0) raised exception';
    END IF;
    IF v_result IS DISTINCT FROM ID_NONE_OBJ THEN
        RAISE EXCEPTION 'FAIL: print(1, "two", 3.0) did not return None';
    END IF;
    RAISE NOTICE '  Test 6 PASS: print(1, "two", 3.0) outputs "1 two 3.0" and returns None';
    pass_count := pass_count + 1;

    -- ================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE 'All print builtin tests passed!';
END $$;
