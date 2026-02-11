-- ============================================================================
-- Test: Bound Method Integration
--
-- Purpose:
--   인스턴스에서 메서드(builtin) 속성 조회 시 __get__ → bound method 반환,
--   클래스에서 조회 시 함수 그대로 반환. Design: docs/BOUND_METHOD_DESIGN.md.
--
-- Tests:
--   1. getattr(instance, "f") → bound method (py_method_object, im_self=instance, im_func=len)
--   2. getattr(Type, "f") → len (함수 그대로, class-level)
--   3. Bytecode: LOAD_CONST(inst), LOAD_ATTR("f") → bound method; py_method_object 행 검증
--
-- Usage:
--   Run after migrations. If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_TYPE_TYPE   uuid := '00000000-0000-4000-a000-000000000002';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_LEN_FUNCTION uuid := '00000000-0000-4000-b000-000000000003';

    test_count int := 0;
    pass_count int := 0;

    bases_tuple_id uuid;
    dict_t_id uuid;
    type_t_id uuid;
    inst_id uuid;
    dict_inst_id uuid;
    name_f_id uuid;
    res_id uuid;
    got_im_self uuid;
    got_im_func uuid;
    got_im_class uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Bound Method Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    SELECT tp_bases INTO bases_tuple_id FROM public.py_type_object WHERE ob_base = ID_INT_TYPE LIMIT 1;
    IF bases_tuple_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: tp_bases (object,) not found';
    END IF;

    name_f_id := public.py_str_from_text('f');

    -- Type T with tp_dict["f"] = len
    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_f_id, ID_LEN_FUNCTION);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);

    -- Instance of T
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    -- ------------------------------------------------------------------------
    -- Test 1: getattr(instance, "f") → bound method (py_method_object, im_self=inst, im_func=len)
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 1: getattr(instance, "f") → bound method (im_self=inst, im_func=len)...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    res_id := public.py_object_getattr(inst_id, name_f_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "f") raised exception';
    END IF;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "f") returned NULL';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_method_object WHERE ob_base = res_id) THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "f") did not return a py_method_object';
    END IF;
    SELECT im_self, im_func, im_class INTO got_im_self, got_im_func, got_im_class
    FROM public.py_method_object WHERE ob_base = res_id;
    IF got_im_self IS DISTINCT FROM inst_id THEN
        RAISE EXCEPTION 'FAIL: bound method im_self expected %, got %', inst_id, got_im_self;
    END IF;
    IF got_im_func IS DISTINCT FROM ID_LEN_FUNCTION THEN
        RAISE EXCEPTION 'FAIL: bound method im_func expected len %, got %', ID_LEN_FUNCTION, got_im_func;
    END IF;
    IF got_im_class IS DISTINCT FROM type_t_id THEN
        RAISE EXCEPTION 'FAIL: bound method im_class expected %, got %', type_t_id, got_im_class;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ getattr(instance, "f") → bound method (im_self, im_func=len)';

    -- ------------------------------------------------------------------------
    -- Test 2: getattr(Type, "f") → len (class-level, 함수 그대로)
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 2: getattr(Type, "f") → len (class-level)...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    res_id := public.py_object_getattr(type_t_id, name_f_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(T, "f") raised exception';
    END IF;
    IF res_id IS DISTINCT FROM ID_LEN_FUNCTION THEN
        RAISE EXCEPTION 'FAIL: getattr(T, "f") expected len %, got %', ID_LEN_FUNCTION, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ getattr(Type, "f") → len';

    -- ------------------------------------------------------------------------
    -- Test 3: Bytecode LOAD_CONST(inst), LOAD_ATTR("f") → bound method on stack
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 3: Bytecode LOAD_CONST(inst) LOAD_ATTR("f") → bound method...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    DECLARE
        co_names_id uuid;
        co_consts_id uuid;
        co_code_id uuid;
        code_obj_id uuid;
        frame_id uuid;
        locals_dict_id uuid;
        globals_dict_id uuid;
        builtins_dict_id uuid;
        empty_tuple_id uuid;
        empty_str_id uuid;
        ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
        ID_BYTES_TYPE uuid := '00000000-0000-4000-a000-000000000012';
    BEGIN
        empty_tuple_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
        empty_str_id := public.py_str_from_text('');
        co_names_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_f_id]);
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
        IF public.py_err_occurred() THEN
            RAISE EXCEPTION 'FAIL: LOAD_CONST LOAD_ATTR("f") raised exception';
        END IF;
        IF res_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: LOAD_CONST LOAD_ATTR("f") returned NULL';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.py_method_object WHERE ob_base = res_id) THEN
            RAISE EXCEPTION 'FAIL: bytecode LOAD_ATTR("f") did not return py_method_object';
        END IF;
        SELECT im_self, im_func INTO got_im_self, got_im_func FROM public.py_method_object WHERE ob_base = res_id;
        IF got_im_self IS DISTINCT FROM inst_id OR got_im_func IS DISTINCT FROM ID_LEN_FUNCTION THEN
            RAISE EXCEPTION 'FAIL: bytecode bound method im_self/im_func mismatch';
        END IF;
    END;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Bytecode LOAD_ATTR("f") → bound method';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'Bound method integration: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
