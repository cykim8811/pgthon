-- ============================================================================
-- Test: STORE_ATTR Bytecode Integration
--
-- Purpose:
--   STORE_ATTR(95) opcode 검증. CPython 고증: TOS=owner, SECOND=value,
--   setattr(owner, co_names[name_index], value).
--   - 인스턴스 __dict__에 저장 후 LOAD_ATTR로 확인
--   - 인스턴스가 아닌 객체에 저장 시 AttributeError
--   - 타입에 data descriptor(__set__)가 있으면 descriptor.__set__(obj, value) 호출 후 LOAD_ATTR로 확인
--
-- Usage:
--   Run after migrations. If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_TYPE_TYPE   uuid := '00000000-0000-4000-a000-000000000002';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_ATTRIBUTE_ERROR_TYPE uuid := '00000000-0000-4000-a000-000000000027';
    ID_DESCRIPTOR_SET uuid := '00000000-0000-4000-b000-000000000020';
    ID_DESCRIPTOR_GET uuid := '00000000-0000-4000-b000-000000000021';

    test_count int := 0;
    pass_count int := 0;

    bases_tuple_id uuid;
    dict_empty_id uuid;
    dict_t_id uuid;
    value_42_id uuid;
    value_99_id uuid;
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
    -- Test 3: data descriptor
    dict_descriptor_type_id uuid;
    type_descriptor_id uuid;
    desc_inst_id uuid;
    desc_in_dict_id uuid;
    type_t_with_desc_id uuid;
    dict_t_with_desc_id uuid;
    inst_with_desc_id uuid;
    inst_with_desc_in_dict_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'STORE_ATTR Integration Test';
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
    name_y_id := public.py_str_from_text('y');

    -- Type T with empty tp_dict
    dict_empty_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_empty_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_empty_id);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_empty_id);

    -- Instance with py_instance_object and in_dict (empty dict)
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_t_id);

    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    empty_str_id := public.py_str_from_text('');

    -- ------------------------------------------------------------------------
    -- Test 1: STORE_ATTR then LOAD_ATTR — obj.x = 42, then obj.x → 42
    -- Bytecode: LOAD_CONST(inst), LOAD_CONST(42), STORE_ATTR("x")
    --          then LOAD_CONST(inst), LOAD_ATTR("x") → 42
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 1: STORE_ATTR("x") then LOAD_ATTR("x") → 42...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_x_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    -- consts[0]=value_42, consts[1]=inst so that LOAD_CONST 0, LOAD_CONST 1 → stack [value_42, inst], TOS=owner
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[value_42_id, inst_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- LOAD_CONST 0 (value_42), LOAD_CONST 1 (inst), STORE_ATTR 0 ("x") → setattr(inst, "x", value_42)
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064015f00', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
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
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: STORE_ATTR("x") raised exception';
    END IF;

    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "x") raised after STORE_ATTR';
    END IF;
    IF res_id IS DISTINCT FROM value_42_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "x") expected value 42 id %, got %', value_42_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ obj.x = 42 then obj.x → 42';

    -- ------------------------------------------------------------------------
    -- Test 2: STORE_ATTR on non-instance (no py_instance_object row) → AttributeError
    -- int 42 has no py_instance_object; setattr(42, "x", value) → AttributeError
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 2: STORE_ATTR on non-instance (int 42) → AttributeError...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[value_42_id, value_42_id]);
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
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: STORE_ATTR on int 42 should set exception';
    END IF;
    SELECT exc_type_id INTO got_exc_type_id FROM public.py_thread_state WHERE id = current_setting('pgthon.thread_state_id')::uuid;
    IF got_exc_type_id IS DISTINCT FROM ID_ATTRIBUTE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: expected AttributeError, got exc_type_id %', got_exc_type_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ STORE_ATTR on non-instance → AttributeError';

    -- ------------------------------------------------------------------------
    -- Test 3: Data descriptor — type has __set__ in tp_dict; STORE_ATTR calls descriptor.__set__, LOAD_ATTR returns value
    -- Type T has tp_dict["y"] = descriptor (instance of DescriptorType with __set__/__get__ builtins).
    -- obj.y = 99 → descriptor.__set__(descriptor, obj, 99); obj.y → 99 via descriptor.__get__
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 3: STORE_ATTR on instance with data descriptor → __set__ called, LOAD_ATTR returns value...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_descriptor_type_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_descriptor_type_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_descriptor_type_id);
    PERFORM public.py_dict_set_item(dict_descriptor_type_id, public.py_str_from_text('__set__'), ID_DESCRIPTOR_SET);
    PERFORM public.py_dict_set_item(dict_descriptor_type_id, public.py_str_from_text('__get__'), ID_DESCRIPTOR_GET);
    type_descriptor_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_descriptor_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_descriptor_id, 'DescriptorType', bases_tuple_id, dict_descriptor_type_id);
    desc_in_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (desc_in_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (desc_in_dict_id);
    desc_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (desc_inst_id, type_descriptor_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (desc_inst_id, desc_in_dict_id);
    dict_t_with_desc_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_with_desc_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_with_desc_id);
    PERFORM public.py_dict_set_item(dict_t_with_desc_id, name_y_id, desc_inst_id);
    type_t_with_desc_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_with_desc_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_with_desc_id, 'T', bases_tuple_id, dict_t_with_desc_id);
    inst_with_desc_in_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_with_desc_in_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (inst_with_desc_in_dict_id);
    inst_with_desc_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_with_desc_id, type_t_with_desc_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_with_desc_id, inst_with_desc_in_dict_id);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_y_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[value_99_id, inst_with_desc_id]);
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
        RAISE EXCEPTION 'FAIL: STORE_ATTR("y") with descriptor raised exception';
    END IF;
    res_id := public.py_object_getattr(inst_with_desc_id, name_y_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "y") raised after STORE_ATTR via descriptor';
    END IF;
    IF res_id IS DISTINCT FROM value_99_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "y") expected value 99 id %, got %', value_99_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ STORE_ATTR via data descriptor __set__, LOAD_ATTR → 99';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'STORE_ATTR integration: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
