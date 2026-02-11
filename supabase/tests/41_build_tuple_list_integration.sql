-- ============================================================================
-- Test: BUILD_TUPLE / BUILD_LIST Bytecode Integration
--
-- Purpose:
--   BUILD_TUPLE(102)·BUILD_LIST(103) opcode 검증. CPython 고증: 스택에서 count개 pop,
--   TOS=마지막 원소, 새 tuple/list 생성 후 push.
--   - Bytecode (1, 2) → tuple, len=2, ob_item 순서 검증
--   - Bytecode [1, 2] → list, len=2, ob_item 순서 검증
--   - Bytecode () → 빈 tuple, len=0
--   - Bytecode [] → 빈 list, len=0
--
-- Usage:
--   Run after migrations. If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE    uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE  uuid := '00000000-0000-4000-a000-000000000007';
    ID_LIST_TYPE   uuid := '00000000-0000-4000-a000-000000000005';

    test_count int := 0;
    pass_count int := 0;

    c0_id uuid; c1_id uuid;
    res_id uuid;
    res_len bigint;
    res_item0 uuid; res_item1 uuid;
    res_val numeric;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'BUILD_TUPLE / BUILD_LIST Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Const 1, 2 for (1, 2) / [1, 2]
    c0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (c0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (c0_id, 1);

    c1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (c1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (c1_id, 2);

    RAISE NOTICE '  ✓ Test constants created (1, 2)';
    RAISE NOTICE '';

    -- Test 1: Bytecode (1, 2) → tuple, len=2, ob_item[1]=1, ob_item[2]=2
    RAISE NOTICE 'Test 1: bytecode (1, 2) → tuple, len=2, order (1,2)...';
    test_count := test_count + 1;
    DECLARE
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
        empty_tuple_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
        empty_str_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
        co_names_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);
        co_consts_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[c0_id, c1_id]);
        co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('6400640166025300', 'hex'));
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
    END;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: bytecode (1, 2) returned NULL';
    END IF;
    res_len := public.py_object_size(res_id);
    IF res_len IS NULL OR res_len <> 2 THEN
        RAISE EXCEPTION 'FAIL: len((1,2)) expected 2, got %', res_len;
    END IF;
    SELECT ob_item[1], ob_item[2] INTO res_item0, res_item1 FROM public.py_tuple_object WHERE ob_base = res_id;
    IF res_item0 IS DISTINCT FROM c0_id OR res_item1 IS DISTINCT FROM c1_id THEN
        RAISE EXCEPTION 'FAIL: (1,2) ob_item order expected (c0,c1), got (%,%)', res_item0, res_item1;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ (1, 2) = tuple len 2, order (1,2)';

    -- Test 2: Bytecode [1, 2] → list, len=2, ob_item[1]=1, ob_item[2]=2
    RAISE NOTICE 'Test 2: bytecode [1, 2] → list, len=2, order [1,2]...';
    test_count := test_count + 1;
    DECLARE
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
        empty_tuple_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
        empty_str_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
        co_names_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);
        co_consts_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[c0_id, c1_id]);
        co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('6400640167025300', 'hex'));
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
    END;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: bytecode [1, 2] returned NULL';
    END IF;
    res_len := public.py_object_size(res_id);
    IF res_len IS NULL OR res_len <> 2 THEN
        RAISE EXCEPTION 'FAIL: len([1,2]) expected 2, got %', res_len;
    END IF;
    SELECT ob_item[1], ob_item[2] INTO res_item0, res_item1 FROM public.py_list_object WHERE ob_base = res_id;
    IF res_item0 IS DISTINCT FROM c0_id OR res_item1 IS DISTINCT FROM c1_id THEN
        RAISE EXCEPTION 'FAIL: [1,2] ob_item order expected (c0,c1), got (%,%)', res_item0, res_item1;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ [1, 2] = list len 2, order [1,2]';

    -- Test 3: Bytecode () → BUILD_TUPLE(0), len=0
    RAISE NOTICE 'Test 3: bytecode () → empty tuple, len=0...';
    test_count := test_count + 1;
    DECLARE
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
        empty_tuple_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
        empty_str_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
        co_names_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);
        co_consts_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);
        co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('66005300', 'hex'));
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
    END;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: bytecode () returned NULL';
    END IF;
    res_len := public.py_object_size(res_id);
    IF res_len IS NULL OR res_len <> 0 THEN
        RAISE EXCEPTION 'FAIL: len(()) expected 0, got %', res_len;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ () = empty tuple len 0';

    -- Test 4: Bytecode [] → BUILD_LIST(0), len=0
    RAISE NOTICE 'Test 4: bytecode [] → empty list, len=0...';
    test_count := test_count + 1;
    DECLARE
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
        empty_tuple_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
        empty_str_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
        co_names_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);
        co_consts_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);
        co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('67005300', 'hex'));
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
    END;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: bytecode [] returned NULL';
    END IF;
    res_len := public.py_object_size(res_id);
    IF res_len IS NULL OR res_len <> 0 THEN
        RAISE EXCEPTION 'FAIL: len([]) expected 0, got %', res_len;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ [] = empty list len 0';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'BUILD_TUPLE/BUILD_LIST integration: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
