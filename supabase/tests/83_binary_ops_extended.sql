-- ============================================================================
-- Test: Extended Binary/Unary Ops (/, //, %, **, &, |, ^, <<, >>, ~, inplace)
--
-- Tests all newly-implemented BINARY_OP sub-opcodes and UNARY_INVERT.
-- Bytecode pattern: LOAD_CONST(0) LOAD_CONST(1) BINARY_OP(oparg) RETURN_VALUE
--   = 0x6400 6401 7aXX 5300
-- UNARY_INVERT: LOAD_CONST(0) UNARY_INVERT(15) RETURN_VALUE
--   = 0x6400 0f00 5300
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE   uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE   uuid := '00000000-0000-4000-a000-000000000004';
    ID_FLOAT_TYPE uuid := '00000000-0000-4000-a000-000000000009';
    ID_DICT_TYPE  uuid := '00000000-0000-4000-a000-000000000006';
    ID_TYPE_ERROR uuid := '00000000-0000-4000-a000-000000000022';
    ID_ZERO_DIVISION_ERROR uuid := '00000000-0000-4000-a000-00000000002b';

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
    result_int numeric;
    result_float double precision;
    exc_type_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Extended Binary/Unary Ops Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup shared test infrastructure
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
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
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

    -- =========================================================================
    -- Test 1: 7 / 2 → 3.5 (true divide int → float)
    -- BINARY_OP(11) = 0x640064017a0b5300
    -- =========================================================================
    RAISE NOTICE 'Test 1: 7 / 2 → 3.5 (true divide int→float)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 7);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 2);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a0b5300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 7/2 returned NULL'; END IF;
    SELECT ob_fval INTO result_float FROM public.py_float_object WHERE ob_base = result_id;
    IF result_float IS NULL OR result_float <> 3.5 THEN
        RAISE EXCEPTION 'FAIL: 7/2 = %, expected 3.5', result_float;
    END IF;
    RAISE NOTICE '  ✓ 7 / 2 = 3.5 (float)';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 2: 7 // 2 → 3 (floor divide int)
    -- BINARY_OP(2) = 0x640064017a025300
    -- =========================================================================
    RAISE NOTICE 'Test 2: 7 // 2 → 3 (floor divide int)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 7);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 2);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a025300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 7//2 returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int IS NULL OR result_int <> 3 THEN
        RAISE EXCEPTION 'FAIL: 7//2 = %, expected 3', result_int;
    END IF;
    RAISE NOTICE '  ✓ 7 // 2 = 3';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 3: 7 % 3 → 1 (remainder int)
    -- BINARY_OP(6) = 0x640064017a065300
    -- =========================================================================
    RAISE NOTICE 'Test 3: 7 %% 3 → 1 (remainder int)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 7);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 3);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a065300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 7%%3 returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int IS NULL OR result_int <> 1 THEN
        RAISE EXCEPTION 'FAIL: 7%%3 = %, expected 1', result_int;
    END IF;
    RAISE NOTICE '  ✓ 7 %% 3 = 1';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 4: 2 ** 10 → 1024 (power int)
    -- BINARY_OP(8) = 0x640064017a085300
    -- =========================================================================
    RAISE NOTICE 'Test 4: 2 ** 10 → 1024 (power int)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 2);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 10);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a085300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 2**10 returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int IS NULL OR result_int <> 1024 THEN
        RAISE EXCEPTION 'FAIL: 2**10 = %, expected 1024', result_int;
    END IF;
    RAISE NOTICE '  ✓ 2 ** 10 = 1024';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 5: 5 & 3 → 1 (bitwise AND)
    -- BINARY_OP(1) = 0x640064017a015300
    -- =========================================================================
    RAISE NOTICE 'Test 5: 5 & 3 → 1 (bitwise AND)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 5);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 3);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 5&3 returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int IS NULL OR result_int <> 1 THEN
        RAISE EXCEPTION 'FAIL: 5&3 = %, expected 1', result_int;
    END IF;
    RAISE NOTICE '  ✓ 5 & 3 = 1';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 6: 5 | 3 → 7 (bitwise OR)
    -- BINARY_OP(7) = 0x640064017a075300
    -- =========================================================================
    RAISE NOTICE 'Test 6: 5 | 3 → 7 (bitwise OR)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 5);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 3);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a075300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 5|3 returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int IS NULL OR result_int <> 7 THEN
        RAISE EXCEPTION 'FAIL: 5|3 = %, expected 7', result_int;
    END IF;
    RAISE NOTICE '  ✓ 5 | 3 = 7';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 7: 5 ^ 3 → 6 (bitwise XOR)
    -- BINARY_OP(12) = 0x640064017a0c5300
    -- =========================================================================
    RAISE NOTICE 'Test 7: 5 ^ 3 → 6 (bitwise XOR)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 5);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 3);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a0c5300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 5^3 returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int IS NULL OR result_int <> 6 THEN
        RAISE EXCEPTION 'FAIL: 5^3 = %, expected 6', result_int;
    END IF;
    RAISE NOTICE '  ✓ 5 ^ 3 = 6';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 8: 1 << 4 → 16 (left shift)
    -- BINARY_OP(3) = 0x640064017a035300
    -- =========================================================================
    RAISE NOTICE 'Test 8: 1 << 4 → 16 (left shift)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 4);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a035300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 1<<4 returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int IS NULL OR result_int <> 16 THEN
        RAISE EXCEPTION 'FAIL: 1<<4 = %, expected 16', result_int;
    END IF;
    RAISE NOTICE '  ✓ 1 << 4 = 16';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 9: 16 >> 2 → 4 (right shift)
    -- BINARY_OP(9) = 0x640064017a095300
    -- =========================================================================
    RAISE NOTICE 'Test 9: 16 >> 2 → 4 (right shift)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 16);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 2);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a095300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 16>>2 returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int IS NULL OR result_int <> 4 THEN
        RAISE EXCEPTION 'FAIL: 16>>2 = %, expected 4', result_int;
    END IF;
    RAISE NOTICE '  ✓ 16 >> 2 = 4';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 10: ~5 → -6 (unary invert)
    -- LOAD_CONST(0) UNARY_INVERT(15,0) RETURN_VALUE(83,0)
    -- = 0x6400 0f00 5300
    -- =========================================================================
    RAISE NOTICE 'Test 10: ~5 → -6 (unary invert)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 5);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64000f005300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: ~5 returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int IS NULL OR result_int <> -6 THEN
        RAISE EXCEPTION 'FAIL: ~5 = %, expected -6', result_int;
    END IF;
    RAISE NOTICE '  ✓ ~5 = -6';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 11: 7.5 / 2.5 → 3.0 (true divide float)
    -- BINARY_OP(11) = 0x640064017a0b5300
    -- =========================================================================
    RAISE NOTICE 'Test 11: 7.5 / 2.5 → 3.0 (true divide float)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (const0_id, 7.5);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (const1_id, 2.5);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a0b5300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 7.5/2.5 returned NULL'; END IF;
    SELECT ob_fval INTO result_float FROM public.py_float_object WHERE ob_base = result_id;
    IF result_float IS NULL OR result_float <> 3.0 THEN
        RAISE EXCEPTION 'FAIL: 7.5/2.5 = %, expected 3.0', result_float;
    END IF;
    RAISE NOTICE '  ✓ 7.5 / 2.5 = 3.0';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 12: 7.5 // 2.5 → 3.0 (floor divide float)
    -- Python: 7.5 // 2.5 = 3.0
    -- BINARY_OP(2)
    -- =========================================================================
    RAISE NOTICE 'Test 12: 7.5 // 2.5 → 3.0 (floor divide float)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (const0_id, 7.5);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (const1_id, 2.5);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a025300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 7.5//2.5 returned NULL'; END IF;
    SELECT ob_fval INTO result_float FROM public.py_float_object WHERE ob_base = result_id;
    IF result_float IS NULL OR result_float <> 3.0 THEN
        RAISE EXCEPTION 'FAIL: 7.5//2.5 = %, expected 3.0', result_float;
    END IF;
    RAISE NOTICE '  ✓ 7.5 // 2.5 = 3.0';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 13: 7.5 % 2.5 → 0.0 (remainder float)
    -- Python: 7.5 % 2.5 = 0.0
    -- BINARY_OP(6)
    -- =========================================================================
    RAISE NOTICE 'Test 13: 7.5 %% 2.5 → 0.0 (remainder float)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (const0_id, 7.5);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (const1_id, 2.5);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a065300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 7.5%%2.5 returned NULL'; END IF;
    SELECT ob_fval INTO result_float FROM public.py_float_object WHERE ob_base = result_id;
    IF result_float IS NULL OR result_float <> 0.0 THEN
        RAISE EXCEPTION 'FAIL: 7.5%%2.5 = %, expected 0.0', result_float;
    END IF;
    RAISE NOTICE '  ✓ 7.5 %% 2.5 = 0.0';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 14: 2.0 ** 3.0 → 8.0 (power float)
    -- BINARY_OP(8)
    -- =========================================================================
    RAISE NOTICE 'Test 14: 2.0 ** 3.0 → 8.0 (power float)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (const0_id, 2.0);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (const1_id, 3.0);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a085300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 2.0**3.0 returned NULL'; END IF;
    SELECT ob_fval INTO result_float FROM public.py_float_object WHERE ob_base = result_id;
    IF result_float IS NULL OR result_float <> 8.0 THEN
        RAISE EXCEPTION 'FAIL: 2.0**3.0 = %, expected 8.0', result_float;
    END IF;
    RAISE NOTICE '  ✓ 2.0 ** 3.0 = 8.0';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 15: 1 / 0 → ZeroDivisionError
    -- BINARY_OP(11)
    -- =========================================================================
    RAISE NOTICE 'Test 15: 1 / 0 → ZeroDivisionError...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 0);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a0b5300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL OR NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: 1/0 should raise ZeroDivisionError, got result_id=%', result_id;
    END IF;
    SELECT g.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() g LIMIT 1;
    IF exc_type_id IS DISTINCT FROM ID_ZERO_DIVISION_ERROR THEN
        RAISE EXCEPTION 'FAIL: 1/0 should set ZeroDivisionError, got exc_type_id %', exc_type_id;
    END IF;
    PERFORM public.py_err_clear();
    RAISE NOTICE '  ✓ 1 / 0 → ZeroDivisionError';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 16: NB_INPLACE_ADD(13): 3 += 4 → 7 (delegates to py_object_add)
    -- BINARY_OP(13) = 0x640064017a0d5300
    -- =========================================================================
    RAISE NOTICE 'Test 16: INPLACE_ADD 3+=4 → 7...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 3);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 4);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064017a0d5300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: 3+=4 returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int IS NULL OR result_int <> 7 THEN
        RAISE EXCEPTION 'FAIL: 3+=4 = %, expected 7', result_int;
    END IF;
    RAISE NOTICE '  ✓ INPLACE_ADD 3+=4 = 7';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Summary
    -- =========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total: %  Passed: %', test_count, pass_count;
    RAISE NOTICE '';

    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'FAIL: % of % tests passed', pass_count, test_count;
    END IF;

    RAISE NOTICE '✓ All extended binary/unary ops tests passed!';
END $$;
