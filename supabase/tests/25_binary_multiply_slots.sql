-- ============================================================================
-- Test: BINARY_MULTIPLY Slots (nb_multiply, sq_repeat, py_object_multiply)
--
-- Purpose:
--   Phase 1+2+3 검증. int nb_multiply, str sq_repeat, via_nb, py_object_multiply.
--
-- Usage:
--   Run after migrations 239000, 239100, 239200.
-- ============================================================================

DO $$
DECLARE
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    ID_NOT_IMPLEMENTED uuid := '00000000-0000-4000-b000-000000000012';
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    int1_id uuid; int2_id uuid; str_a_id uuid; str_b_id uuid;
    res_id uuid;
    num_id uuid; seq_id uuid;
    nb_slot regproc;
    sq_slot regproc;
    val_num numeric;
    val_txt text;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'BINARY_MULTIPLY Slots Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Test 1: int has nb_multiply
    RAISE NOTICE 'Test 1: int has nb_multiply...';
    test_count := test_count + 1;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = ID_INT_TYPE;
    IF num_id IS NULL THEN RAISE EXCEPTION 'FAIL: int has no tp_as_number'; END IF;
    SELECT nb_multiply INTO nb_slot FROM public.py_number_methods WHERE id = num_id;
    IF nb_slot IS NULL THEN RAISE EXCEPTION 'FAIL: int has no nb_multiply'; END IF;
    RAISE NOTICE '  ✓ int has nb_multiply';
    pass_count := pass_count + 1;

    -- Test 2: str has sq_repeat
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: str has sq_repeat...';
    test_count := test_count + 1;
    SELECT tp_as_sequence INTO seq_id FROM public.py_type_object WHERE ob_base = ID_STR_TYPE;
    IF seq_id IS NULL THEN RAISE EXCEPTION 'FAIL: str has no tp_as_sequence'; END IF;
    SELECT sq_repeat INTO sq_slot FROM public.py_sequence_methods WHERE id = seq_id;
    IF sq_slot IS NULL THEN RAISE EXCEPTION 'FAIL: str has no sq_repeat'; END IF;
    RAISE NOTICE '  ✓ str has sq_repeat';
    pass_count := pass_count + 1;

    -- Test 3: py_object_multiply_via_nb(6, 7) = 42
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: py_object_multiply_via_nb(6, 7) = 42...';
    test_count := test_count + 1;
    int1_id := gen_random_uuid(); int2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int1_id, ID_INT_TYPE), (int2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int1_id, 6), (int2_id, 7);
    res_id := public.py_object_multiply_via_nb(int1_id, int2_id);
    IF res_id IS NULL OR res_id = ID_NOT_IMPLEMENTED THEN
        RAISE EXCEPTION 'FAIL: py_object_multiply_via_nb(6, 7) returned NotImplemented/NULL';
    END IF;
    SELECT long_value INTO val_num FROM public.py_long_object WHERE ob_base = res_id;
    IF val_num IS NULL OR val_num <> 42 THEN
        RAISE EXCEPTION 'FAIL: result %, expected 42', val_num;
    END IF;
    RAISE NOTICE '  ✓ py_object_multiply_via_nb(6, 7) = 42';
    pass_count := pass_count + 1;

    -- Test 4: py_object_multiply_via_nb(int, str) = NotImplemented
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: py_object_multiply_via_nb(int, str) = NotImplemented...';
    test_count := test_count + 1;
    str_a_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_a_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_a_id, 'a');
    res_id := public.py_object_multiply_via_nb(int1_id, str_a_id);
    IF res_id IS DISTINCT FROM ID_NOT_IMPLEMENTED THEN
        RAISE EXCEPTION 'FAIL: py_object_multiply_via_nb(int, str) should return NotImplemented, got %', res_id;
    END IF;
    RAISE NOTICE '  ✓ py_object_multiply_via_nb(int, str) = NotImplemented';
    pass_count := pass_count + 1;

    -- Test 5: py_object_multiply(6, 7) = 42
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: py_object_multiply(6, 7) = 42...';
    test_count := test_count + 1;
    res_id := public.py_object_multiply(int1_id, int2_id);
    IF res_id IS NULL THEN RAISE EXCEPTION 'FAIL: py_object_multiply(6, 7) returned NULL'; END IF;
    SELECT long_value INTO val_num FROM public.py_long_object WHERE ob_base = res_id;
    IF val_num IS NULL OR val_num <> 42 THEN RAISE EXCEPTION 'FAIL: result %, expected 42', val_num; END IF;
    RAISE NOTICE '  ✓ py_object_multiply(6, 7) = 42';
    pass_count := pass_count + 1;

    -- Test 6: py_object_multiply('a', 3) = 'aaa'
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: py_object_multiply(''a'', 3) = ''aaa''...';
    test_count := test_count + 1;
    int2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int2_id, 3);
    res_id := public.py_object_multiply(str_a_id, int2_id);
    IF res_id IS NULL THEN RAISE EXCEPTION 'FAIL: ''a''*3 returned NULL'; END IF;
    SELECT str_value INTO val_txt FROM public.py_unicode_object WHERE ob_base = res_id;
    IF val_txt IS NULL OR val_txt <> 'aaa' THEN RAISE EXCEPTION 'FAIL: result %, expected ''aaa''', COALESCE(val_txt, 'NULL'); END IF;
    RAISE NOTICE '  ✓ py_object_multiply(''a'', 3) = ''aaa''';
    pass_count := pass_count + 1;

    -- Test 7: py_object_multiply(3, 'a') = 'aaa'
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: py_object_multiply(3, ''a'') = ''aaa''...';
    test_count := test_count + 1;
    res_id := public.py_object_multiply(int2_id, str_a_id);
    IF res_id IS NULL THEN RAISE EXCEPTION 'FAIL: 3*''a'' returned NULL'; END IF;
    SELECT str_value INTO val_txt FROM public.py_unicode_object WHERE ob_base = res_id;
    IF val_txt IS NULL OR val_txt <> 'aaa' THEN RAISE EXCEPTION 'FAIL: result %, expected ''aaa''', COALESCE(val_txt, 'NULL'); END IF;
    RAISE NOTICE '  ✓ py_object_multiply(3, ''a'') = ''aaa''';
    pass_count := pass_count + 1;

    -- Test 8: py_object_multiply('a', 'b') → TypeError
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: py_object_multiply(''a'', ''b'') raises TypeError...';
    test_count := test_count + 1;
    str_b_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_b_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_b_id, 'b');
    BEGIN
        res_id := public.py_object_multiply(str_a_id, str_b_id);
        RAISE EXCEPTION 'FAIL: str*str should raise TypeError, got %', res_id;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM NOT LIKE '%unsupported operand type(s) for *%' THEN RAISE; END IF;
            IF SQLERRM NOT LIKE '%str%' THEN RAISE EXCEPTION 'FAIL: message should mention str: %', SQLERRM; END IF;
    END;
    RAISE NOTICE '  ✓ py_object_multiply(''a'', ''b'') raises TypeError';
    pass_count := pass_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: Total %  Passed %  Failed %', test_count, pass_count, fail_count;
    IF fail_count > 0 THEN RAISE EXCEPTION 'FAIL: % test(s) failed', fail_count; END IF;
    RAISE NOTICE '✓ All BINARY_MULTIPLY slots tests passed!';
END $$;
