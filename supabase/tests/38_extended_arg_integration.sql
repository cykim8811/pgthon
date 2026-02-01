-- ============================================================================
-- Test: EXTENDED_ARG Bytecode Integration
--
-- Purpose:
--   CPython EXTENDED_ARG(144) 고증. py_eval_frame에서 EXTENDED_ARG 연쇄를
--   읽어 다음 opcode의 operand를 (extended << 8) | arg 로 확장하는지 검증.
--
--   - EXTENDED_ARG 0 + LOAD_CONST 1 → effective arg = 1 → co_consts[1] push
--   - RETURN_VALUE → 해당 상수 반환
--
-- Bytecode (hex):
--   144, 0 (EXTENDED_ARG 0); 100, 1 (LOAD_CONST 1); 83, 0 (RETURN_VALUE)
--   = 90 00 64 01 53 00
--
-- Usage:
--   Run after migrations. If any assertion fails, exception is raised.
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE    uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';

    test_count int := 0;
    pass_count int := 0;

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
    result_num numeric;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'EXTENDED_ARG Bytecode Integration Test';
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

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 10);

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 20);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- EXTENDED_ARG 0 (144,0); LOAD_CONST 1 (100,1); RETURN_VALUE (83,0)
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('900064015300', 'hex'));

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

    -- Test 1: EXTENDED_ARG 0 + LOAD_CONST 1 → effective arg 1 → push consts[1], RETURN → 20
    RAISE NOTICE 'Test 1: EXTENDED_ARG 0 + LOAD_CONST 1 returns consts[1] (20)...';
    test_count := test_count + 1;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: EXTENDED_ARG bytecode returned NULL';
    END IF;
    IF result_id IS DISTINCT FROM const1_id THEN
        RAISE EXCEPTION 'FAIL: expected const1 (20), got %', result_id;
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 20 THEN
        RAISE EXCEPTION 'FAIL: expected value 20, got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ EXTENDED_ARG + LOAD_CONST 1 returns 20';
    pass_count := pass_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'EXTENDED_ARG integration: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
