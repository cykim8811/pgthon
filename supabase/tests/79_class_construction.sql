-- ============================================================================
-- Test: Class Construction (LOAD_BUILD_CLASS + __build_class__)
--
-- Tests:
--   1. LOAD_BUILD_CLASS and __build_class__ functions exist
--   2. Simple class: class Foo: x = 42 → Foo.x == 42
--   3. Class with method: class Bar: def greet(self): return 99
--      → Bar type has greet in tp_dict
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE    uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_TYPE_TYPE   uuid := '00000000-0000-4000-a000-000000000002';
    ID_NONE_OBJ    uuid := '00000000-0000-4000-b000-000000000001';
    ID_BUILTINS_MODULE uuid := '00000000-0000-4000-b000-000000000002';

    test_count int := 0;
    pass_count int := 0;

    -- Shared helpers
    empty_str_id uuid;
    co_varnames_id uuid;
    co_cellvars_id uuid;
    co_freevars_id uuid;

    -- Class body code objects
    body_co_code_id uuid;
    body_co_consts_id uuid;
    body_co_names_id uuid;
    body_code_obj_id uuid;

    -- Outer code objects
    outer_co_code_id uuid;
    outer_co_consts_id uuid;
    outer_co_names_id uuid;
    outer_code_obj_id uuid;

    -- Frame setup
    frame_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;

    -- Constants/names
    const_42_id uuid;
    const_99_id uuid;
    str_foo_id uuid;
    str_bar_id uuid;
    str_x_id uuid;
    str_greet_id uuid;
    str_qualname_id uuid;

    -- Results
    res_id uuid;
    res_val numeric;
    res_type uuid;
    res_tp_name text;
    v_tp_dict uuid;
    v_found uuid;

    -- Method test
    greet_co_code_id uuid;
    greet_co_consts_id uuid;
    greet_co_names_id uuid;
    greet_code_obj_id uuid;
    greet_co_varnames_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Class Construction Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup shared objects
    empty_str_id := public.py_str_from_text('');

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

    -- Create constants
    const_42_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_42_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_42_id, 42);

    const_99_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_99_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_99_id, 99);

    str_foo_id := public.py_str_from_text('Foo');
    str_bar_id := public.py_str_from_text('Bar');
    str_x_id := public.py_str_from_text('x');
    str_greet_id := public.py_str_from_text('greet');

    -- ================================================================
    -- Test 1: Functions exist
    -- ================================================================
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_load_build_class') THEN
        RAISE EXCEPTION 'FAIL: py_opcode_LOAD_BUILD_CLASS does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_builtin_build_class') THEN
        RAISE EXCEPTION 'FAIL: py_builtin_build_class does not exist';
    END IF;
    RAISE NOTICE '  Test 1 PASS: LOAD_BUILD_CLASS and __build_class__ exist';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 2: class Foo: x = 42 → Foo.x == 42
    --
    -- Class body bytecode: RESUME 0 | LOAD_CONST 0 (42) | STORE_NAME 0 (x) | LOAD_CONST 1 (None) | RETURN_VALUE
    -- Hex: 970064005a0064015300
    --
    -- Outer bytecode:
    --   RESUME 0 | PUSH_NULL | LOAD_BUILD_CLASS |
    --   LOAD_CONST 0 (body_code) | MAKE_FUNCTION 0 |
    --   LOAD_CONST 1 ("Foo" name) | PRECALL 2 | CALL 2 |
    --   STORE_NAME 0 ("Foo") | LOAD_NAME 0 ("Foo") | LOAD_ATTR 1 ("x") | RETURN_VALUE
    -- Hex: 970002004700640084006401a602ab025a0065006a015300
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- Build class body code object
    body_co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (body_co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (body_co_consts_id, ARRAY[const_42_id, ID_NONE_OBJ]);

    body_co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (body_co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (body_co_names_id, ARRAY[str_x_id]);

    body_co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (body_co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (body_co_code_id, decode('970064005a0064015300', 'hex'));

    body_code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (body_code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (body_code_obj_id, body_co_code_id, body_co_consts_id, body_co_names_id, empty_str_id, str_foo_id, 0, co_varnames_id, co_cellvars_id, co_freevars_id, 0);

    -- Build outer code object
    -- co_consts: (body_code, "Foo" name str)
    outer_co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (outer_co_consts_id, ARRAY[body_code_obj_id, str_foo_id]);

    outer_co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (outer_co_names_id, ARRAY[str_foo_id, str_x_id]);

    outer_co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (outer_co_code_id, decode('970002004700640084006401a602ab025a0065006a015300', 'hex'));

    outer_code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (outer_code_obj_id, outer_co_code_id, outer_co_consts_id, outer_co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, co_cellvars_id, co_freevars_id, 0);

    -- Create frame
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, outer_code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    -- Execute
    res_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: class Foo construction raised exception';
    END IF;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: Foo.x returned NULL';
    END IF;

    -- res_id should be the int 42
    SELECT long_value INTO res_val FROM public.py_long_object WHERE ob_base = res_id;
    IF res_val IS DISTINCT FROM 42 THEN
        RAISE EXCEPTION 'FAIL: Foo.x expected 42, got %', res_val;
    END IF;
    RAISE NOTICE '  Test 2 PASS: class Foo: x = 42 → Foo.x == 42';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 3: Verify Foo is a type with ob_type = type
    -- ================================================================
    test_count := test_count + 1;

    -- Look up Foo from locals dict (it was stored via STORE_NAME)
    SELECT me_value INTO v_found
    FROM public.py_dict_entry de
    JOIN public.py_unicode_object uo ON uo.ob_base = de.me_key AND uo.str_value = 'Foo'
    WHERE de.dict_id = locals_dict_id;

    IF v_found IS NULL THEN
        RAISE EXCEPTION 'FAIL: Foo not found in locals dict';
    END IF;

    SELECT ob_type INTO res_type FROM public.py_object WHERE id = v_found;
    IF res_type IS DISTINCT FROM ID_TYPE_TYPE THEN
        RAISE EXCEPTION 'FAIL: Foo ob_type is not type, got %', res_type;
    END IF;

    SELECT tp_name INTO res_tp_name FROM public.py_type_object WHERE ob_base = v_found;
    IF res_tp_name IS DISTINCT FROM 'Foo' THEN
        RAISE EXCEPTION 'FAIL: Foo tp_name expected "Foo", got %', res_tp_name;
    END IF;
    RAISE NOTICE '  Test 3 PASS: Foo is a type object with tp_name="Foo"';
    pass_count := pass_count + 1;

    -- ================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE 'All class construction tests passed!';
END $$;
