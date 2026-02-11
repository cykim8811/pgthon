-- ============================================================================
-- Test: VM LOAD_METHOD(160) Opcode (CPython 3.11)
--
-- Purpose:
--   LOAD_METHOD: pop obj, getattr(obj, co_names[namei]). If bound method → push 1 value;
--   else → push NULL, push callable (2 values). CALL then pops NULL if present.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_TYPE_TYPE   uuid := '00000000-0000-4000-a000-000000000002';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_LEN_FUNCTION uuid := '00000000-0000-4000-b000-000000000003';
    ID_NULL_OBJ    uuid := '00000000-0000-4000-b000-000000000030';

    test_count int := 0;
    pass_count int := 0;

    bases_tuple_id uuid;
    dict_t_id uuid;
    type_t_id uuid;
    inst_id uuid;
    dict_inst_id uuid;
    name_f_id uuid;

    co_names_id uuid;
    co_consts_id uuid;
    co_code_id uuid;
    code_obj_id uuid;
    frame_id uuid;
    empty_tuple_id uuid;
    empty_str_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;

    res_id uuid;
    got_im_self uuid;
    got_im_func uuid;
    stack uuid[];
    stack_len int;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM LOAD_METHOD(160) Opcode Test (CPython 3.11)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    name_f_id := public.py_str_from_text('f');
    SELECT tp_bases INTO bases_tuple_id FROM public.py_type_object WHERE ob_base = (SELECT ob_base FROM public.py_type_object WHERE tp_name = 'int' LIMIT 1) LIMIT 1;
    IF bases_tuple_id IS NULL THEN
        SELECT ob_base INTO bases_tuple_id FROM public.py_type_object WHERE tp_name = 'object' LIMIT 1;
    END IF;

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_f_id, ID_LEN_FUNCTION);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);

    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    empty_str_id := public.py_str_from_text('');

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: py_opcode_LOAD_METHOD exists
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_load_method' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_LOAD_METHOD does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_LOAD_METHOD exists';
    pass_count := pass_count + 1;

    -- Test 2: Bound method case — LOAD_CONST(inst), LOAD_METHOD(0), RETURN → result is bound method
    test_count := test_count + 1;
    PERFORM public.py_err_clear();
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_f_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inst_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('6400a0005300', 'hex'));
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
        RAISE EXCEPTION 'FAIL: LOAD_METHOD(inst, "f") raised exception';
    END IF;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: LOAD_METHOD(inst, "f") returned NULL';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_method_object WHERE ob_base = res_id) THEN
        RAISE EXCEPTION 'FAIL: LOAD_METHOD(inst, "f") did not return py_method_object';
    END IF;
    SELECT im_self, im_func INTO got_im_self, got_im_func FROM public.py_method_object WHERE ob_base = res_id;
    IF got_im_self IS DISTINCT FROM inst_id OR got_im_func IS DISTINCT FROM ID_LEN_FUNCTION THEN
        RAISE EXCEPTION 'FAIL: LOAD_METHOD bound method im_self/im_func mismatch';
    END IF;
    RAISE NOTICE '  ✓ LOAD_METHOD(instance, "f") → 1 value (bound method)';
    pass_count := pass_count + 1;

    -- Test 3: Slot case — LOAD_CONST(Type), LOAD_METHOD(0) → stack has 2 values (NULL, callable)
    test_count := test_count + 1;
    PERFORM public.py_err_clear();
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[type_t_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('6400a000', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: LOAD_METHOD(Type, "f") raised exception';
    END IF;
    SELECT f_valuestack INTO stack FROM public.py_frame_object WHERE ob_base = frame_id;
    stack_len := array_length(stack, 1);
    IF stack_len IS NULL OR stack_len != 2 THEN
        RAISE EXCEPTION 'FAIL: LOAD_METHOD(Type, "f") expected stack length 2, got %', stack_len;
    END IF;
    IF stack[1] IS DISTINCT FROM ID_NULL_OBJ OR stack[2] IS DISTINCT FROM ID_LEN_FUNCTION THEN
        RAISE EXCEPTION 'FAIL: LOAD_METHOD(Type, "f") expected stack [NULL, len], got [%, %]', stack[1], stack[2];
    END IF;
    RAISE NOTICE '  ✓ LOAD_METHOD(Type, "f") → 2 values (NULL, callable)';
    pass_count := pass_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE '✅ All LOAD_METHOD(160) opcode tests passed!';
END $$;
