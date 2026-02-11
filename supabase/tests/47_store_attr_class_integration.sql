-- ============================================================================
-- Test: STORE_ATTR Class Attribute (C.x = v) — Type Object setattr
--
-- Purpose:
--   setattr(C, "x", v) 즉 타입(클래스) 객체에 대한 속성 저장 검증.
--   - Bytecode: LOAD_CONST(v), LOAD_CONST(C), STORE_ATTR("x") → C의 tp_dict에 저장
--   - 이후 LOAD_ATTR(C, "x") 또는 getattr(C, "x") → v 반환
--   - 타입 여부는 py_type_object 존재로만 판별 (tp_name 분기 금지).
--
-- Usage:
--   Run after migrations (Phase 46). If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_TYPE_TYPE   uuid := '00000000-0000-4000-a000-000000000002';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_ATTRIBUTE_ERROR_TYPE uuid := '00000000-0000-4000-a000-000000000027';

    test_count int := 0;
    pass_count int := 0;

    bases_tuple_id uuid;
    dict_empty_id uuid;
    type_c_id uuid;
    value_42_id uuid;
    value_99_id uuid;
    name_x_id uuid;
    name_z_id uuid;
    res_id uuid;
    got_exc_type_id uuid;
    empty_tuple_id uuid;
    empty_str_id uuid;
    co_names_id uuid;
    co_consts_id uuid;
    co_code_id uuid;
    code_obj_id uuid;
    frame_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'STORE_ATTR Class (C.x = v) Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    SELECT tp_bases INTO bases_tuple_id FROM public.py_type_object WHERE ob_base = ID_INT_TYPE LIMIT 1;
    IF bases_tuple_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: tp_bases (object,) not found';
    END IF;

    value_42_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_42_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_42_id, 42);
    value_99_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_99_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_99_id, 99);
    name_x_id := public.py_str_from_text('x');
    name_z_id := public.py_str_from_text('z');

    -- Type C with empty tp_dict (class to which we will set C.x = 42)
    dict_empty_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_empty_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_empty_id);
    type_c_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_c_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_c_id, 'C', bases_tuple_id, dict_empty_id);

    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    empty_str_id := public.py_str_from_text('');

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);

    -- ------------------------------------------------------------------------
    -- Test 1: C.x = 42 (bytecode STORE_ATTR on type C), then getattr(C, "x") → 42
    -- Bytecode: LOAD_CONST(42), LOAD_CONST(C), STORE_ATTR("x")
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 1: STORE_ATTR on type C (C.x = 42) then getattr(C, "x") → 42...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_x_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[value_42_id, type_c_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064015f00', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: STORE_ATTR(C, "x", 42) raised exception';
    END IF;

    res_id := public.py_object_getattr(type_c_id, name_x_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(C, "x") raised after C.x = 42';
    END IF;
    IF res_id IS DISTINCT FROM value_42_id THEN
        RAISE EXCEPTION 'FAIL: getattr(C, "x") expected value 42 id %, got %', value_42_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ C.x = 42 then getattr(C, "x") → 42';

    -- ------------------------------------------------------------------------
    -- Test 2: C.z = 99 (same class, another name), then getattr(C, "z") → 99
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 2: C.z = 99 then getattr(C, "z") → 99...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_z_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[value_99_id, type_c_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064015f00', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: STORE_ATTR(C, "z", 99) raised exception';
    END IF;

    res_id := public.py_object_getattr(type_c_id, name_z_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(C, "z") raised after C.z = 99';
    END IF;
    IF res_id IS DISTINCT FROM value_99_id THEN
        RAISE EXCEPTION 'FAIL: getattr(C, "z") expected value 99 id %, got %', value_99_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ C.z = 99 then getattr(C, "z") → 99';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'STORE_ATTR class integration: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
