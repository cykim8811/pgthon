-- ============================================================================
-- Test: LOAD_ATTR Bytecode Integration
--
-- Purpose:
--   LOAD_ATTR(106) opcode 검증. CPython 고증: TOS=obj, getattr(obj, co_names[namei]).
--   Phase 1: type(obj).tp_dict 조회만; 디스크립터 __get__ 호출.
--   - 타입 tp_dict에 있는 속성 조회 → 성공 시 해당 값 반환
--   - tp_dict에 없는 이름 → AttributeError 설정, NULL 반환
--
-- Usage:
--   Run after migrations. If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_TYPE_TYPE   uuid := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE    uuid := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_ATTRIBUTE_ERROR_TYPE uuid := '00000000-0000-4000-a000-000000000027';

    test_count int := 0;
    pass_count int := 0;

    bases_tuple_id uuid;
    dict_id uuid;
    value_42_id uuid;
    name_x_id uuid;
    name_y_id uuid;
    type_t_id uuid;
    inst_id uuid;
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
    RAISE NOTICE 'LOAD_ATTR Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- tp_bases (object,) from bootstrap
    SELECT tp_bases INTO bases_tuple_id FROM public.py_type_object WHERE ob_base = ID_INT_TYPE LIMIT 1;
    IF bases_tuple_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: tp_bases (object,) not found';
    END IF;

    -- Value 42
    value_42_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_42_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_42_id, 42);

    -- Name strings 'x', 'y'
    name_x_id := public.py_str_from_text('x');
    name_y_id := public.py_str_from_text('y');

    -- Dict for type T, and set D["x"] = 42
    dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_id);
    PERFORM public.py_dict_set_item(dict_id, name_x_id, value_42_id);

    -- Type T with tp_dict = D, tp_bases = (object,)
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_id);

    -- Instance of T
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);

    -- ------------------------------------------------------------------------
    -- Test 1: obj.x where type(obj).tp_dict["x"] = 42 → result 42
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 1: LOAD_ATTR("x") on instance of T with tp_dict["x"]=42...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    empty_str_id := public.py_str_from_text('');
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_x_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inst_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64006a005300', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
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

    res_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: LOAD_ATTR("x") raised but attribute exists in tp_dict';
    END IF;
    IF res_id IS DISTINCT FROM value_42_id THEN
        RAISE EXCEPTION 'FAIL: LOAD_ATTR("x") expected value 42 id %, got %', value_42_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ obj.x = 42';

    -- ------------------------------------------------------------------------
    -- Test 2: obj.y where "y" not in type(obj).tp_dict → AttributeError
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 2: LOAD_ATTR("y") with "y" not in tp_dict → AttributeError...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_y_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inst_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64006a005300', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF res_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: LOAD_ATTR("y") should return NULL, got %', res_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: LOAD_ATTR("y") should set exception';
    END IF;
    SELECT exc_type_id INTO got_exc_type_id FROM public.py_thread_state WHERE id = current_setting('elytra.thread_state_id')::uuid;
    IF got_exc_type_id IS DISTINCT FROM ID_ATTRIBUTE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: expected AttributeError, got exc_type_id %', got_exc_type_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ obj.y → AttributeError';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'LOAD_ATTR integration: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
