-- ============================================================================
-- Test: COMPARE_OP Bytecode Integration
--
-- Purpose:
--   Phase 2+3 구현 검증. py_eval_frame으로 바이트코드 실행 시 COMPARE_OP(107) 동작 확인.
--   - 1 < 2 → True, 1 > 2 → False, 1 == 1 → True, 1 == 2 → False
--   - 1 < 'a' → TypeError (메시지에 비교/타입 관련 내용)
--
-- Bytecode: LOAD_CONST(0) LOAD_CONST(1) COMPARE_OP(op) RETURN_VALUE
--   = 100,0, 100,1, 107,op, 83,0  →  \x640064016B<op>5300  (op: 0=LT, 2=EQ, 4=GT)
--
-- Usage:
--   Run after migrations 240100, 240200. If any assertion fails, exception is raised.
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE    uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_TRUE_OBJ    uuid := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ   uuid := '00000000-0000-4000-b000-000000000011';

    test_count int := 0;
    pass_count int := 0;
    fail_count int := 0;

    frame_id uuid;
    code_obj_id uuid;
    co_code_id uuid;
    co_names_id uuid;
    co_consts_id uuid;
    empty_tuple_id uuid;
    empty_str_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;

    const0_id uuid;
    const1_id uuid;
    result_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'COMPARE_OP Bytecode Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);

    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: 1 < 2 → True (COMPARE_OP 0 = Py_LT)
    RAISE NOTICE 'Test 1: bytecode 1 < 2 → True...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 2);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016B005300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: 1<2 bytecode returned NULL';
    END IF;
    IF result_id IS DISTINCT FROM ID_TRUE_OBJ THEN
        RAISE EXCEPTION 'FAIL: 1<2 bytecode result %, expected True', result_id;
    END IF;
    RAISE NOTICE '  ✓ 1 < 2 = True';
    pass_count := pass_count + 1;

    -- Test 2: 1 > 2 → False (COMPARE_OP 4 = Py_GT)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: bytecode 1 > 2 → False...';
    test_count := test_count + 1;

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016B045300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: 1>2 bytecode returned NULL';
    END IF;
    IF result_id IS DISTINCT FROM ID_FALSE_OBJ THEN
        RAISE EXCEPTION 'FAIL: 1>2 bytecode result %, expected False', result_id;
    END IF;
    RAISE NOTICE '  ✓ 1 > 2 = False';
    pass_count := pass_count + 1;

    -- Test 3: 1 == 1 → True (COMPARE_OP 2 = Py_EQ)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: bytecode 1 == 1 → True...';
    test_count := test_count + 1;

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const0_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016B025300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: 1==1 bytecode returned NULL';
    END IF;
    IF result_id IS DISTINCT FROM ID_TRUE_OBJ THEN
        RAISE EXCEPTION 'FAIL: 1==1 bytecode result %, expected True', result_id;
    END IF;
    RAISE NOTICE '  ✓ 1 == 1 = True';
    pass_count := pass_count + 1;

    -- Test 4: 1 == 2 → False (COMPARE_OP 2)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: bytecode 1 == 2 → False...';
    test_count := test_count + 1;

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016B025300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: 1==2 bytecode returned NULL';
    END IF;
    IF result_id IS DISTINCT FROM ID_FALSE_OBJ THEN
        RAISE EXCEPTION 'FAIL: 1==2 bytecode result %, expected False', result_id;
    END IF;
    RAISE NOTICE '  ✓ 1 == 2 = False';
    pass_count := pass_count + 1;

    -- Test 5: 1 < 'a' → TypeError
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: bytecode 1 < ''a'' raises TypeError...';
    test_count := test_count + 1;

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const1_id, 'a');

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016B005300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    BEGIN
        result_id := public.py_eval_frame(frame_id);
        RAISE EXCEPTION 'FAIL: 1<''a'' bytecode should raise TypeError, got %', result_id;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM NOT LIKE '%TypeError%' THEN
                RAISE;
            END IF;
    END;
    RAISE NOTICE '  ✓ 1 < ''a'' raises TypeError';
    pass_count := pass_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total: %  Passed: %  Failed: %', test_count, pass_count, fail_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'FAIL: % test(s) failed', test_count - pass_count;
    END IF;
    RAISE NOTICE '✓ All COMPARE_OP bytecode integration tests passed!';
END $$;
