-- ============================================================================
-- Test: float Slots Integration (nb_add, nb_subtract, nb_multiply, tp_hash, tp_richcompare)
--
-- Purpose:
--   float 타입 슬롯 구현 검증. CPython 고증: float±int coercion, 비교·해시.
--   - float+float, float+int, int+float → float
--   - float-float, float-int, int-float; float*float, float*int, int*float
--   - py_object_hash(float); py_object_richcompare(float, float/int)
--   - 바이트코드: 1.5+2 → 3.5, 1.0<2.0 → True
--
-- Usage:
--   Run after migrations. If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE    uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_FLOAT_TYPE  uuid := '00000000-0000-4000-a000-000000000009';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_TRUE_OBJ    uuid := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ   uuid := '00000000-0000-4000-b000-000000000011';

    test_count int := 0;
    pass_count int := 0;

    fa uuid; fb uuid; ia uuid; ib uuid;
    res_id uuid;
    res_fval double precision;
    res_ival numeric;
    h bigint;
    cmp_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'float Slots Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Create float/int test objects: 1.5, 2.0, 2, 3
    fa := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (fa, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (fa, 1.5);

    fb := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (fb, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (fb, 2.0);

    ia := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (ia, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (ia, 2);

    ib := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (ib, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (ib, 3);

    RAISE NOTICE '  ✓ Test objects created (float 1.5, 2.0; int 2, 3)';
    RAISE NOTICE '';

    -- Test 1: float + float → float
    RAISE NOTICE 'Test 1: float + float (1.5 + 2.0) → 3.5...';
    test_count := test_count + 1;
    res_id := public.py_object_add(fa, fb);
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: float+float returned NULL';
    END IF;
    SELECT ob_fval INTO res_fval FROM public.py_float_object WHERE ob_base = res_id;
    IF res_fval IS NULL OR abs(res_fval - 3.5) > 1e-9 THEN
        RAISE EXCEPTION 'FAIL: expected 3.5, got %', res_fval;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ float+float = 3.5';

    -- Test 2: float + int → float (coercion)
    RAISE NOTICE 'Test 2: float + int (1.5 + 2) → 3.5...';
    test_count := test_count + 1;
    res_id := public.py_object_add(fa, ia);
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: float+int returned NULL';
    END IF;
    SELECT ob_fval INTO res_fval FROM public.py_float_object WHERE ob_base = res_id;
    IF res_fval IS NULL OR abs(res_fval - 3.5) > 1e-9 THEN
        RAISE EXCEPTION 'FAIL: expected 3.5, got %', res_fval;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ float+int = 3.5';

    -- Test 3: int + float → float (reflected)
    RAISE NOTICE 'Test 3: int + float (2 + 1.5) → 3.5...';
    test_count := test_count + 1;
    res_id := public.py_object_add(ia, fa);
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: int+float returned NULL';
    END IF;
    SELECT ob_fval INTO res_fval FROM public.py_float_object WHERE ob_base = res_id;
    IF res_fval IS NULL OR abs(res_fval - 3.5) > 1e-9 THEN
        RAISE EXCEPTION 'FAIL: expected 3.5, got %', res_fval;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ int+float = 3.5';

    -- Test 4: float - float, float - int
    RAISE NOTICE 'Test 4: float - float (2.0-1.5), float - int (2.0-2)...';
    test_count := test_count + 1;
    res_id := public.py_object_subtract(fb, fa);
    SELECT ob_fval INTO res_fval FROM public.py_float_object WHERE ob_base = res_id;
    IF res_fval IS NULL OR abs(res_fval - 0.5) > 1e-9 THEN
        RAISE EXCEPTION 'FAIL: 2.0-1.5 expected 0.5, got %', res_fval;
    END IF;
    res_id := public.py_object_subtract(fb, ia);
    SELECT ob_fval INTO res_fval FROM public.py_float_object WHERE ob_base = res_id;
    IF res_fval IS NULL OR abs(res_fval - 0.0) > 1e-9 THEN
        RAISE EXCEPTION 'FAIL: 2.0-2 expected 0.0, got %', res_fval;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ float subtract OK';

    -- Test 5: float * float, float * int
    RAISE NOTICE 'Test 5: float * float (1.5*2.0), float * int (1.5*2)...';
    test_count := test_count + 1;
    res_id := public.py_object_multiply(fa, fb);
    SELECT ob_fval INTO res_fval FROM public.py_float_object WHERE ob_base = res_id;
    IF res_fval IS NULL OR abs(res_fval - 3.0) > 1e-9 THEN
        RAISE EXCEPTION 'FAIL: 1.5*2.0 expected 3.0, got %', res_fval;
    END IF;
    res_id := public.py_object_multiply(fa, ia);
    SELECT ob_fval INTO res_fval FROM public.py_float_object WHERE ob_base = res_id;
    IF res_fval IS NULL OR abs(res_fval - 3.0) > 1e-9 THEN
        RAISE EXCEPTION 'FAIL: 1.5*2 expected 3.0, got %', res_fval;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ float multiply OK';

    -- Test 6: py_object_hash(float)
    RAISE NOTICE 'Test 6: py_object_hash(float)...';
    test_count := test_count + 1;
    h := public.py_object_hash(fa);
    IF h IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_object_hash(float) returned NULL';
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ float hash OK';

    -- Test 7: py_object_richcompare(float, float) — 1.5 < 2.0 → True, 1.5 == 2.0 → False
    RAISE NOTICE 'Test 7: py_object_richcompare(float, float)...';
    test_count := test_count + 1;
    cmp_id := public.py_object_richcompare(fa, fb, 0);
    IF cmp_id IS DISTINCT FROM ID_TRUE_OBJ THEN
        RAISE EXCEPTION 'FAIL: 1.5 < 2.0 expected True, got %', cmp_id;
    END IF;
    cmp_id := public.py_object_richcompare(fa, fb, 2);
    IF cmp_id IS DISTINCT FROM ID_FALSE_OBJ THEN
        RAISE EXCEPTION 'FAIL: 1.5 == 2.0 expected False, got %', cmp_id;
    END IF;
    cmp_id := public.py_object_richcompare(fa, ia, 2);
    IF cmp_id IS DISTINCT FROM ID_FALSE_OBJ THEN
        RAISE EXCEPTION 'FAIL: 1.5 == 2 (int) expected False, got %', cmp_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ float richcompare OK';

    -- Test 8: Bytecode 1.5+2 → 3.5 (LOAD_CONST 0 float, LOAD_CONST 1 int, BINARY_ADD, RETURN_VALUE)
    RAISE NOTICE 'Test 8: bytecode 1.5+2 → 3.5...';
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
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[fa, ia]);
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
        RAISE EXCEPTION 'FAIL: bytecode 1.5+2 returned NULL';
    END IF;
    SELECT ob_fval INTO res_fval FROM public.py_float_object WHERE ob_base = res_id;
    IF res_fval IS NULL OR abs(res_fval - 3.5) > 1e-9 THEN
        RAISE EXCEPTION 'FAIL: bytecode 1.5+2 expected 3.5, got %', res_fval;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ bytecode 1.5+2 = 3.5';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'float slots integration: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
