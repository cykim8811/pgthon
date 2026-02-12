-- ============================================================================
-- Test: bytes Slots Integration (sq_length, sq_concat, sq_repeat, tp_richcompare)
--
-- Purpose:
--   bytes 타입 시퀀스·비교 슬롯 검증. CPython 고증: bytes는 PySequenceMethods 사용.
--   - len(bytes) → py_object_size → sq_length
--   - bytes + bytes → py_object_add → sq_concat
--   - bytes * int, int * bytes → py_object_multiply → sq_repeat
--   - bytes < bytes, bytes == bytes → py_object_richcompare
--   - bytes + str → TypeError; 바이트코드 bytes+bytes, bytes*int
--
-- Usage:
--   Run after migrations. If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE    uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_TRUE_OBJ    uuid := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ   uuid := '00000000-0000-4000-b000-000000000011';

    test_count int := 0;
    pass_count int := 0;

    b1_id uuid; b2_id uuid; b_ab_id uuid;
    int_3_id uuid;
    str_id uuid;
    res_id uuid;
    res_len bigint;
    res_bytes bytea;
    cmp_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'bytes Slots Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Create bytes b'AB', b'CD', int 3, str 'x'
    b1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (b1_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (b1_id, decode('4142', 'hex'));

    b2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (b2_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (b2_id, decode('4344', 'hex'));

    int_3_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int_3_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int_3_id, 3);

    str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_id, 'x');

    RAISE NOTICE '  ✓ Test objects created (b''AB'', b''CD'', 3, ''x'')';
    RAISE NOTICE '';

    -- Test 1: len(bytes) → 2
    RAISE NOTICE 'Test 1: py_object_size(b''AB'') → 2...';
    test_count := test_count + 1;
    res_len := public.py_object_size(b1_id);
    IF res_len IS NULL OR res_len <> 2 THEN
        RAISE EXCEPTION 'FAIL: py_object_size(b''AB'') expected 2, got %', res_len;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ len(b''AB'') = 2';

    -- Test 2: bytes + bytes → b'ABCD'
    RAISE NOTICE 'Test 2: py_object_add(b''AB'', b''CD'') → b''ABCD''...';
    test_count := test_count + 1;
    res_id := public.py_object_add(b1_id, b2_id);
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: bytes+bytes returned NULL';
    END IF;
    SELECT bytes_value INTO res_bytes FROM public.py_bytes_object WHERE ob_base = res_id;
    IF res_bytes IS NULL OR res_bytes <> decode('41424344', 'hex') THEN
        RAISE EXCEPTION 'FAIL: bytes+bytes expected b''ABCD'', got %', encode(res_bytes, 'hex');
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ b''AB''+b''CD'' = b''ABCD''';

    -- Test 3: bytes * int → b'ABABAB'
    RAISE NOTICE 'Test 3: py_object_multiply(b''AB'', 3) → b''ABABAB''...';
    test_count := test_count + 1;
    res_id := public.py_object_multiply(b1_id, int_3_id);
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: bytes*3 returned NULL';
    END IF;
    SELECT bytes_value INTO res_bytes FROM public.py_bytes_object WHERE ob_base = res_id;
    IF res_bytes IS NULL OR res_bytes <> decode('414241424142', 'hex') THEN
        RAISE EXCEPTION 'FAIL: bytes*3 expected b''ABABAB'', got %', encode(res_bytes, 'hex');
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ b''AB''*3 = b''ABABAB''';

    -- Test 4: int * bytes → b'ABABAB'
    RAISE NOTICE 'Test 4: py_object_multiply(3, b''AB'') → b''ABABAB''...';
    test_count := test_count + 1;
    res_id := public.py_object_multiply(int_3_id, b1_id);
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: 3*bytes returned NULL';
    END IF;
    SELECT bytes_value INTO res_bytes FROM public.py_bytes_object WHERE ob_base = res_id;
    IF res_bytes IS NULL OR res_bytes <> decode('414241424142', 'hex') THEN
        RAISE EXCEPTION 'FAIL: 3*bytes expected b''ABABAB'', got %', encode(res_bytes, 'hex');
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ 3*b''AB'' = b''ABABAB''';

    -- Test 5: py_object_richcompare(b'AB', b'CD', Py_LT=0) → True (AB < CD lexicographic)
    RAISE NOTICE 'Test 5: py_object_richcompare(b''AB'', b''CD'', Py_LT) → True...';
    test_count := test_count + 1;
    cmp_id := public.py_object_richcompare(b1_id, b2_id, 0);
    IF cmp_id IS DISTINCT FROM ID_TRUE_OBJ THEN
        RAISE EXCEPTION 'FAIL: b''AB'' < b''CD'' expected True, got %', cmp_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ b''AB'' < b''CD'' = True';

    -- Test 6: py_object_richcompare(b'AB', b'AB', Py_EQ=2) → True
    RAISE NOTICE 'Test 6: py_object_richcompare(b''AB'', b''AB'', Py_EQ) → True...';
    test_count := test_count + 1;
    cmp_id := public.py_object_richcompare(b1_id, b1_id, 2);
    IF cmp_id IS DISTINCT FROM ID_TRUE_OBJ THEN
        RAISE EXCEPTION 'FAIL: b''AB'' == b''AB'' expected True, got %', cmp_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ b''AB'' == b''AB'' = True';

    -- Test 7: py_object_richcompare(b'CD', b'AB', Py_LT=0) → False
    RAISE NOTICE 'Test 7: py_object_richcompare(b''CD'', b''AB'', Py_LT) → False...';
    test_count := test_count + 1;
    cmp_id := public.py_object_richcompare(b2_id, b1_id, 0);
    IF cmp_id IS DISTINCT FROM ID_FALSE_OBJ THEN
        RAISE EXCEPTION 'FAIL: b''CD'' < b''AB'' expected False, got %', cmp_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ b''CD'' < b''AB'' = False';

    -- Test 8: bytes + str → TypeError
    RAISE NOTICE 'Test 8: py_object_add(bytes, str) raises TypeError...';
    test_count := test_count + 1;
    DECLARE
        exc_type_id uuid;
    BEGIN
        PERFORM public.py_err_clear();
        res_id := public.py_object_add(b1_id, str_id);
        IF res_id IS NOT NULL OR NOT public.py_err_occurred() THEN
            RAISE EXCEPTION 'FAIL: bytes+str should raise TypeError, got result_id=%', res_id;
        END IF;
        SELECT g.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() g LIMIT 1;
        IF exc_type_id IS DISTINCT FROM '00000000-0000-4000-a000-000000000022' THEN
            RAISE EXCEPTION 'FAIL: bytes+str should set TypeError, got exc_type_id %', exc_type_id;
        END IF;
        PERFORM public.py_err_clear();
    END;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ bytes+str raises TypeError';

    -- Test 9: Bytecode b'AB'+b'CD' → b'ABCD'
    RAISE NOTICE 'Test 9: bytecode b''AB''+b''CD'' → b''ABCD''...';
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
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[b1_id, b2_id]);
        co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('6400640117005300', 'hex'));
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
    END;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: bytecode b''AB''+b''CD'' returned NULL';
    END IF;
    SELECT bytes_value INTO res_bytes FROM public.py_bytes_object WHERE ob_base = res_id;
    IF res_bytes IS NULL OR res_bytes <> decode('41424344', 'hex') THEN
        RAISE EXCEPTION 'FAIL: bytecode b''AB''+b''CD'' expected b''ABCD'', got %', encode(COALESCE(res_bytes, ''::bytea), 'hex');
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ bytecode b''AB''+b''CD'' = b''ABCD''';

    -- Test 10: Bytecode b'AB'*3 → b'ABABAB'
    RAISE NOTICE 'Test 10: bytecode b''AB''*3 → b''ABABAB''...';
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
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[b1_id, int_3_id]);
        co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('6400640114005300', 'hex'));
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
    END;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: bytecode b''AB''*3 returned NULL';
    END IF;
    SELECT bytes_value INTO res_bytes FROM public.py_bytes_object WHERE ob_base = res_id;
    IF res_bytes IS NULL OR res_bytes <> decode('414241424142', 'hex') THEN
        RAISE EXCEPTION 'FAIL: bytecode b''AB''*3 expected b''ABABAB'', got %', encode(COALESCE(res_bytes, ''::bytea), 'hex');
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ bytecode b''AB''*3 = b''ABABAB''';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'bytes slots integration: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
