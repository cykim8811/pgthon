-- ============================================================================
-- Test: DELETE_ATTR Bytecode Integration (del obj.x / del C.x)
--
-- Purpose:
--   DELETE_ATTR(96 in CPython 3.11) opcode 검증. CPython: TOS = owner, pop 후 delattr(owner, name).
--   - Instance: obj.x = 42, bytecode DELETE_ATTR("x"), getattr(obj,"x") → AttributeError
--   - Class: C.x = 42, bytecode DELETE_ATTR on C ("x"), getattr(C,"x") → AttributeError
--   - Delete non-existent attribute → AttributeError
--
-- Usage:
--   Run after migrations (Phase 47). If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_TYPE_TYPE   uuid := '00000000-0000-4000-a000-000000000002';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_ATTRIBUTE_ERROR_TYPE uuid := '00000000-0000-4000-a000-000000000027';

    test_count int := 0;
    pass_count int := 0;

    bases_tuple_id uuid;
    dict_empty_id uuid;
    type_t_id uuid;
    type_c_id uuid;
    value_42_id uuid;
    name_x_id uuid;
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
    dict_inst_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'DELETE_ATTR Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    SELECT tp_bases INTO bases_tuple_id FROM public.py_type_object WHERE ob_base = ID_INT_TYPE LIMIT 1;
    IF bases_tuple_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: tp_bases (object,) not found';
    END IF;

    value_42_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_42_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_42_id, 42);
    name_x_id := public.py_str_from_text('x');

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
    -- Test 1: Instance — obj.x = 42, bytecode DELETE_ATTR("x"), getattr(obj,"x") → AttributeError
    -- Bytecode: LOAD_CONST(obj), DELETE_ATTR("x")
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 1: STORE_ATTR obj.x=42, DELETE_ATTR("x"), getattr(obj,"x") → AttributeError...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_empty_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_empty_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_empty_id);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_empty_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    PERFORM public.py_object_setattr(inst_id, name_x_id, value_42_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: setattr(inst,"x",42) raised';
    END IF;

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_x_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inst_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- LOAD_CONST 0 (inst), DELETE_ATTR 0 ("x") — opcode 96 = 0x60 (CPython 3.11)
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64006000', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    PERFORM public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: DELETE_ATTR("x") raised exception';
    END IF;

    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"x") after del expected NULL (AttributeError), got %', res_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"x") after del should set AttributeError';
    END IF;
    SELECT exc_type_id INTO got_exc_type_id FROM public.py_thread_state WHERE id = current_setting('elytra.thread_state_id')::uuid;
    IF got_exc_type_id IS DISTINCT FROM ID_ATTRIBUTE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: expected AttributeError, got exc_type_id %', got_exc_type_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ del obj.x then getattr(obj,"x") → AttributeError';

    -- ------------------------------------------------------------------------
    -- Test 2: Class — C.x = 42, bytecode DELETE_ATTR on C ("x"), getattr(C,"x") → AttributeError
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 2: C.x=42, DELETE_ATTR on C ("x"), getattr(C,"x") → AttributeError...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_empty_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_empty_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_empty_id);
    type_c_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_c_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_c_id, 'C', bases_tuple_id, dict_empty_id);

    PERFORM public.py_object_setattr(type_c_id, name_x_id, value_42_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: setattr(C,"x",42) raised';
    END IF;

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_x_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[type_c_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64006000', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    PERFORM public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: DELETE_ATTR on C raised exception';
    END IF;

    res_id := public.py_object_getattr(type_c_id, name_x_id);
    IF res_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: getattr(C,"x") after del expected NULL, got %', res_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(C,"x") after del should set AttributeError';
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ del C.x then getattr(C,"x") → AttributeError';

    -- ------------------------------------------------------------------------
    -- Test 3: Delete non-existent attribute on instance → AttributeError
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 3: DELETE_ATTR on non-existent "x" → AttributeError...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_empty_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_empty_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_empty_id);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_empty_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_x_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inst_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64006000', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    PERFORM public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: DELETE_ATTR on non-existent "x" should set exception';
    END IF;
    SELECT exc_type_id INTO got_exc_type_id FROM public.py_thread_state WHERE id = current_setting('elytra.thread_state_id')::uuid;
    IF got_exc_type_id IS DISTINCT FROM ID_ATTRIBUTE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: expected AttributeError, got exc_type_id %', got_exc_type_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ del obj.x (no x) → AttributeError';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'DELETE_ATTR integration: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
