-- ============================================================================
-- Test: VM UNARY_NOT(12) Opcode (CPython 3.11)
--
-- Purpose:
--   UNARY_NOT: pop TOS, push True if not PyObject_IsTrue(TOS) else False.
--
-- Usage:
--   Run after migrations. If any assertion fails, an exception is raised.
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_TRUE_OBJ UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000011';

    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;

    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_consts_id UUID;
    empty_tuple_id UUID;
    empty_str_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    locals_dict_id UUID;

    result_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM UNARY_NOT(12) Opcode Test (CPython 3.11)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );

    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: py_opcode_UNARY_NOT exists
    RAISE NOTICE 'Test 1: py_opcode_UNARY_NOT exists...';
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_unary_not' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_UNARY_NOT does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_UNARY_NOT exists';
    pass_count := pass_count + 1;

    -- Test 2: UNARY_NOT(False) → True
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: UNARY_NOT(False) → True...';
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[ID_FALSE_OBJ] WHERE ob_base = co_consts_id;
    UPDATE public.py_code_object SET co_consts = co_consts_id WHERE ob_base = code_obj_id;
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- LOAD_CONST 0, UNARY_NOT, RETURN_VALUE = 100,0 12,0 83,0 = \x64\x00\x0c\x00\x53\x00
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64000c005300'::bytea);
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );
    UPDATE public.py_frame_object SET f_code = code_obj_id, f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: UNARY_NOT(False) returned NULL'; END IF;
    IF result_id != ID_TRUE_OBJ THEN RAISE EXCEPTION 'FAIL: Expected True (not False), got %', result_id; END IF;
    RAISE NOTICE '  ✓ UNARY_NOT(False) → True';
    pass_count := pass_count + 1;

    -- Test 3: UNARY_NOT(True) → False
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: UNARY_NOT(True) → False...';
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[ID_TRUE_OBJ] WHERE ob_base = co_consts_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: UNARY_NOT(True) returned NULL'; END IF;
    IF result_id != ID_FALSE_OBJ THEN RAISE EXCEPTION 'FAIL: Expected False (not True), got %', result_id; END IF;
    RAISE NOTICE '  ✓ UNARY_NOT(True) → False';
    pass_count := pass_count + 1;

    -- Summary
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total tests: %', test_count;
    RAISE NOTICE 'Passed: %', pass_count;
    RAISE NOTICE 'Failed: %', fail_count;
    RAISE NOTICE '';

    IF fail_count > 0 THEN
        RAISE EXCEPTION 'Some tests failed. See details above.';
    END IF;

    RAISE NOTICE '✅ All UNARY_NOT(12) opcode tests passed!';

END $$;
