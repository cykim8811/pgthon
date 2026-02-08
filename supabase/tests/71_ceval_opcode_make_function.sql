-- ============================================================================
-- Test: VM MAKE_FUNCTION(132) Opcode + py_call_function (CPython 3.11)
--
-- Purpose:
--   Tests MAKE_FUNCTION opcode and user-defined function calling:
--   1. Simple function definition + call: def f(): return 42 → f() = 42
--   2. Function with positional args: def add(a,b): return a+b → add(10,20) = 30
--   3. Function with default args: def greet(x=1): return x → greet() = 1
--   4. Function with default args overridden: greet(5) = 5
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE    UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_BYTES_TYPE  UUID := '00000000-0000-4000-a000-000000000012';
    ID_FUNCTION_TYPE UUID := '00000000-0000-4000-a000-000000000017';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_NONE_OBJ UUID := '00000000-0000-4000-b000-000000000001';

    test_count INTEGER := 0;
    pass_count INTEGER := 0;

    empty_tuple_id UUID;
    empty_str_id UUID;
    builtins_dict_id UUID;
    str_module_id UUID;

    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_consts_id UUID;
    co_names_id UUID;
    globals_dict_id UUID;
    locals_dict_id UUID;
    result_id UUID;
    result_value NUMERIC;

    inner_code_obj_id UUID;
    inner_co_code_id UUID;
    inner_co_consts_id UUID;
    inner_co_varnames_id UUID;

    const_42_id UUID;
    const_10_id UUID;
    const_20_id UUID;
    const_1_id UUID;
    const_5_id UUID;

    str_f_id UUID;
    str_add_id UUID;
    str_greet_id UUID;
    str_a_id UUID;
    str_b_id UUID;
    str_x_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM MAKE_FUNCTION(132) Opcode Test (CPython 3.11)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    SELECT md_dict INTO builtins_dict_id
    FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    -- Shared helpers
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '<test>');

    str_module_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_module_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_module_id, '<module>');

    -- Constants
    const_42_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_42_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_42_id, 42);

    const_10_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_10_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_10_id, 10);

    const_20_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_20_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_20_id, 20);

    const_1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_1_id, 1);

    const_5_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_5_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_5_id, 5);

    -- String names
    str_f_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_f_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_f_id, 'f');

    str_add_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_add_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_add_id, 'add');

    str_greet_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_greet_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_greet_id, 'greet');

    str_a_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_a_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_a_id, 'a');

    str_b_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_b_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_b_id, 'b');

    str_x_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_x_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_x_id, 'x');

    -- ========================================================================
    -- Test 1: def f(): return 42 → f() = 42
    -- ========================================================================
    RAISE NOTICE 'Test 1: def f(): return 42; f() = 42 ...';
    test_count := test_count + 1;

    -- Inner code for f(): RESUME(0) LOAD_CONST(0) RETURN_VALUE
    inner_co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_consts_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (inner_co_consts_id, ARRAY[const_42_id]);

    inner_co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_code_id, ID_BYTES_TYPE);
    -- RESUME=97 0, LOAD_CONST=64 0, RETURN_VALUE=53 0
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (inner_co_code_id, decode('970064005300', 'hex'));

    inner_code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (inner_code_obj_id, inner_co_code_id, inner_co_consts_id, empty_tuple_id, empty_str_id, str_f_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);

    -- Outer: RESUME(0) LOAD_CONST(0) LOAD_CONST(1) MAKE_FUNCTION(0) STORE_NAME(0) PUSH_NULL(0) LOAD_NAME(0) PRECALL(0) CALL(0) RETURN_VALUE
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inner_code_obj_id, str_f_id]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[str_f_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- 97 00 | 64 00 | 64 01 | 84 00 | 5a 00 | 02 00 | 65 00 | a6 00 | ab 00 | 53 00
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('97006400640184005a0002006500a600ab005300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, str_module_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);

    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    result_id := public.py_eval_frame(frame_id);

    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL Test 1: f() returned NULL';
    END IF;
    SELECT long_value INTO result_value FROM public.py_long_object WHERE ob_base = result_id;
    IF result_value != 42 THEN
        RAISE EXCEPTION 'FAIL Test 1: f() = %, expected 42', result_value;
    END IF;

    RAISE NOTICE '  ✓ def f(): return 42; f() = 42';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 2: def add(a, b): return a + b → add(10, 20) = 30
    -- ========================================================================
    RAISE NOTICE 'Test 2: def add(a, b): return a + b; add(10, 20) = 30 ...';
    test_count := test_count + 1;

    -- Inner code: RESUME(0) LOAD_FAST(0) LOAD_FAST(1) BINARY_ADD RETURN_VALUE
    inner_co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_consts_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (inner_co_consts_id, ARRAY[ID_NONE_OBJ]);

    inner_co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_varnames_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (inner_co_varnames_id, ARRAY[str_a_id, str_b_id]);

    inner_co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_code_id, ID_BYTES_TYPE);
    -- 97 00 | 7c 00 | 7c 01 | 17 00 | 53 00
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (inner_co_code_id, decode('97007c007c0117005300', 'hex'));

    inner_code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (inner_code_obj_id, inner_co_code_id, inner_co_consts_id, empty_tuple_id, empty_str_id, str_add_id, 2, inner_co_varnames_id, empty_tuple_id, empty_tuple_id);

    -- Outer: RESUME(0) LOAD_CONST(0) LOAD_CONST(1) MAKE_FUNCTION(0) STORE_NAME(0) PUSH_NULL(0) LOAD_NAME(0) LOAD_CONST(2) LOAD_CONST(3) PRECALL(2) CALL(2) RETURN_VALUE
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inner_code_obj_id, str_add_id, const_10_id, const_20_id]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[str_add_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- 97 00 | 64 00 | 64 01 | 84 00 | 5a 00 | 02 00 | 65 00 | 64 02 | 64 03 | a6 02 | ab 02 | 53 00
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('97006400640184005a000200650064026403a602ab025300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, str_module_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);

    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    result_id := public.py_eval_frame(frame_id);

    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL Test 2: add(10, 20) returned NULL';
    END IF;
    SELECT long_value INTO result_value FROM public.py_long_object WHERE ob_base = result_id;
    IF result_value != 30 THEN
        RAISE EXCEPTION 'FAIL Test 2: add(10, 20) = %, expected 30', result_value;
    END IF;

    RAISE NOTICE '  ✓ def add(a, b): return a + b; add(10, 20) = 30';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 3: def greet(x=1): return x → greet() = 1
    -- ========================================================================
    RAISE NOTICE 'Test 3: def greet(x=1): return x; greet() = 1 ...';
    test_count := test_count + 1;

    -- Inner code: RESUME(0) LOAD_FAST(0) RETURN_VALUE
    inner_co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_consts_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (inner_co_consts_id, ARRAY[ID_NONE_OBJ]);

    inner_co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_varnames_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (inner_co_varnames_id, ARRAY[str_x_id]);

    inner_co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_code_id, ID_BYTES_TYPE);
    -- 97 00 | 7c 00 | 53 00
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (inner_co_code_id, decode('97007c005300', 'hex'));

    inner_code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (inner_code_obj_id, inner_co_code_id, inner_co_consts_id, empty_tuple_id, empty_str_id, str_greet_id, 1, inner_co_varnames_id, empty_tuple_id, empty_tuple_id);

    -- Outer: RESUME(0) LOAD_CONST(0) BUILD_TUPLE(1) LOAD_CONST(1) LOAD_CONST(2) MAKE_FUNCTION(1) STORE_NAME(0) PUSH_NULL(0) LOAD_NAME(0) PRECALL(0) CALL(0) RETURN_VALUE
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const_1_id, inner_code_obj_id, str_greet_id]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[str_greet_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- 97 00 | 64 00 | 66 01 | 64 01 | 64 02 | 84 01 | 5a 00 | 02 00 | 65 00 | a6 00 | ab 00 | 53 00
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('9700640066016401640284015a0002006500a600ab005300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, str_module_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);

    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    result_id := public.py_eval_frame(frame_id);

    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL Test 3: greet() returned NULL';
    END IF;
    SELECT long_value INTO result_value FROM public.py_long_object WHERE ob_base = result_id;
    IF result_value != 1 THEN
        RAISE EXCEPTION 'FAIL Test 3: greet() = %, expected 1', result_value;
    END IF;

    RAISE NOTICE '  ✓ def greet(x=1): return x; greet() = 1';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 4: def greet(x=1): return x → greet(5) = 5 (override default)
    -- ========================================================================
    RAISE NOTICE 'Test 4: greet(5) = 5 (override default) ...';
    test_count := test_count + 1;

    -- Outer: RESUME(0) LOAD_CONST(0) BUILD_TUPLE(1) LOAD_CONST(1) LOAD_CONST(2) MAKE_FUNCTION(1) STORE_NAME(0) PUSH_NULL(0) LOAD_NAME(0) LOAD_CONST(3) PRECALL(1) CALL(1) RETURN_VALUE
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const_1_id, inner_code_obj_id, str_greet_id, const_5_id]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[str_greet_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- 97 00 | 64 00 | 66 01 | 64 01 | 64 02 | 84 01 | 5a 00 | 02 00 | 65 00 | 64 03 | a6 01 | ab 01 | 53 00
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('9700640066016401640284015a00020065006403a601ab015300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, str_module_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);

    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    result_id := public.py_eval_frame(frame_id);

    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL Test 4: greet(5) returned NULL';
    END IF;
    SELECT long_value INTO result_value FROM public.py_long_object WHERE ob_base = result_id;
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL Test 4: greet(5) = %, expected 5', result_value;
    END IF;

    RAISE NOTICE '  ✓ greet(5) = 5 (default overridden)';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test Summary
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total tests: %', test_count;
    RAISE NOTICE 'Passed: %', pass_count;
    RAISE NOTICE '';
    RAISE NOTICE 'All tests passed! ✓';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Test failed with error:';
        RAISE NOTICE '%', SQLERRM;
        RAISE NOTICE '========================================';
        RAISE;
END $$;
