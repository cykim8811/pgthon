-- ============================================================================
-- Test: BINARY_ADD Slots (nb_add, sq_concat, py_object_add_via_nb, py_sequence_concat)
--
-- Purpose:
--   Phase 1+2 구현 검증. 다음을 확인한다.
--   - int/str의 tp_as_number에 nb_add가 등록되어 있는지
--   - str의 tp_as_sequence에 sq_concat이 등록되어 있는지
--   - py_object_add_via_nb: int+int → 합, str+str → 연결, int+str → NotImplemented id
--   - py_sequence_concat: str+str → 연결, int+int → NULL (시퀀스 아님)
--
-- Usage:
--   Run after migrations 238000, 238100. If any assertion fails, exception is raised.
-- ============================================================================

DO $$
DECLARE
    ID_INT_TYPE  uuid := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE  uuid := '00000000-0000-4000-a000-000000000003';
    ID_NOT_IMPLEMENTED uuid := '00000000-0000-4000-b000-000000000012';
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    -- 객체 id
    int1_id uuid; int2_id uuid; str_a_id uuid; str_b_id uuid;
    -- 결과
    res_id uuid;
    num_id uuid;
    seq_id uuid;
    nb_add_slot regproc;
    sq_concat_slot regproc;
    val_num numeric;
    val_txt text;
    exc_type_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'BINARY_ADD Slots Test (nb_add, sq_concat, dispatch)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- Test 1: int의 tp_as_number에 nb_add 등록 여부
    -- ========================================================================
    RAISE NOTICE 'Test 1: int has nb_add in tp_as_number...';
    test_count := test_count + 1;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = ID_INT_TYPE;
    IF num_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: int type has no tp_as_number';
    END IF;
    SELECT nb_add INTO nb_add_slot FROM public.py_number_methods WHERE id = num_id;
    IF nb_add_slot IS NULL THEN
        RAISE EXCEPTION 'FAIL: int tp_as_number has no nb_add';
    END IF;
    RAISE NOTICE '  ✓ int has nb_add registered';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 2: str의 tp_as_number에 nb_add 등록 여부
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: str has nb_add in tp_as_number...';
    test_count := test_count + 1;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = ID_STR_TYPE;
    IF num_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: str type has no tp_as_number';
    END IF;
    SELECT nb_add INTO nb_add_slot FROM public.py_number_methods WHERE id = num_id;
    IF nb_add_slot IS NULL THEN
        RAISE EXCEPTION 'FAIL: str tp_as_number has no nb_add';
    END IF;
    RAISE NOTICE '  ✓ str has nb_add registered';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 3: str의 tp_as_sequence에 sq_concat 등록 여부
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: str has sq_concat in tp_as_sequence...';
    test_count := test_count + 1;
    SELECT tp_as_sequence INTO seq_id FROM public.py_type_object WHERE ob_base = ID_STR_TYPE;
    IF seq_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: str type has no tp_as_sequence';
    END IF;
    SELECT sq_concat INTO sq_concat_slot FROM public.py_sequence_methods WHERE id = seq_id;
    IF sq_concat_slot IS NULL THEN
        RAISE EXCEPTION 'FAIL: str tp_as_sequence has no sq_concat';
    END IF;
    RAISE NOTICE '  ✓ str has sq_concat registered';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 4: py_object_add_via_nb(int, int) → 합
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: py_object_add_via_nb(int, int) returns sum...';
    test_count := test_count + 1;
    int1_id := gen_random_uuid();
    int2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int1_id, ID_INT_TYPE), (int2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int1_id, 10), (int2_id, 20);
    res_id := public.py_object_add_via_nb(int1_id, int2_id);
    IF res_id IS NULL OR res_id = ID_NOT_IMPLEMENTED THEN
        RAISE EXCEPTION 'FAIL: py_object_add_via_nb(10, 20) returned NotImplemented/NULL';
    END IF;
    SELECT long_value INTO val_num FROM public.py_long_object WHERE ob_base = res_id;
    IF val_num IS NULL OR val_num <> 30 THEN
        RAISE EXCEPTION 'FAIL: py_object_add_via_nb(10, 20) result value is %, expected 30', val_num;
    END IF;
    RAISE NOTICE '  ✓ py_object_add_via_nb(10, 20) = 30';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 5: py_object_add_via_nb(str, str) → 연결
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: py_object_add_via_nb(str, str) returns concatenation...';
    test_count := test_count + 1;
    str_a_id := gen_random_uuid();
    str_b_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_a_id, ID_STR_TYPE), (str_b_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_a_id, 'ab'), (str_b_id, 'cd');
    res_id := public.py_object_add_via_nb(str_a_id, str_b_id);
    IF res_id IS NULL OR res_id = ID_NOT_IMPLEMENTED THEN
        RAISE EXCEPTION 'FAIL: py_object_add_via_nb("ab", "cd") returned NotImplemented/NULL';
    END IF;
    SELECT str_value INTO val_txt FROM public.py_unicode_object WHERE ob_base = res_id;
    IF val_txt IS NULL OR val_txt <> 'abcd' THEN
        RAISE EXCEPTION 'FAIL: py_object_add_via_nb("ab", "cd") result is %, expected "abcd"', COALESCE(val_txt, 'NULL');
    END IF;
    RAISE NOTICE '  ✓ py_object_add_via_nb("ab", "cd") = "abcd"';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 6: py_object_add_via_nb(int, str) → NotImplemented id
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: py_object_add_via_nb(int, str) returns NotImplemented...';
    test_count := test_count + 1;
    res_id := public.py_object_add_via_nb(int1_id, str_a_id);
    IF res_id IS DISTINCT FROM ID_NOT_IMPLEMENTED THEN
        RAISE EXCEPTION 'FAIL: py_object_add_via_nb(int, str) should return NotImplemented id, got %', res_id;
    END IF;
    RAISE NOTICE '  ✓ py_object_add_via_nb(int, str) = NotImplemented';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 7: py_sequence_concat(str, str) → 연결
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: py_sequence_concat(str, str) returns concatenation...';
    test_count := test_count + 1;
    res_id := public.py_sequence_concat(str_a_id, str_b_id);
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_sequence_concat("ab", "cd") returned NULL';
    END IF;
    SELECT str_value INTO val_txt FROM public.py_unicode_object WHERE ob_base = res_id;
    IF val_txt IS NULL OR val_txt <> 'abcd' THEN
        RAISE EXCEPTION 'FAIL: py_sequence_concat("ab", "cd") result is %, expected "abcd"', COALESCE(val_txt, 'NULL');
    END IF;
    RAISE NOTICE '  ✓ py_sequence_concat("ab", "cd") = "abcd"';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 8: py_sequence_concat(int, int) → NULL (int는 sq_concat 없음)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: py_sequence_concat(int, int) returns NULL...';
    test_count := test_count + 1;
    res_id := public.py_sequence_concat(int1_id, int2_id);
    IF res_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: py_sequence_concat(int, int) should return NULL (no sq_concat), got %', res_id;
    END IF;
    RAISE NOTICE '  ✓ py_sequence_concat(int, int) = NULL';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 9: py_object_add(int, int) → 합 (Phase 3)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 9: py_object_add(int, int) returns sum...';
    test_count := test_count + 1;
    res_id := public.py_object_add(int1_id, int2_id);
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_object_add(10, 20) returned NULL';
    END IF;
    SELECT long_value INTO val_num FROM public.py_long_object WHERE ob_base = res_id;
    IF val_num IS NULL OR val_num <> 30 THEN
        RAISE EXCEPTION 'FAIL: py_object_add(10, 20) result value is %, expected 30', val_num;
    END IF;
    RAISE NOTICE '  ✓ py_object_add(10, 20) = 30';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 10: py_object_add(str, str) → 연결 (Phase 3)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 10: py_object_add(str, str) returns concatenation...';
    test_count := test_count + 1;
    res_id := public.py_object_add(str_a_id, str_b_id);
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_object_add("ab", "cd") returned NULL';
    END IF;
    SELECT str_value INTO val_txt FROM public.py_unicode_object WHERE ob_base = res_id;
    IF val_txt IS NULL OR val_txt <> 'abcd' THEN
        RAISE EXCEPTION 'FAIL: py_object_add("ab", "cd") result is %, expected "abcd"', COALESCE(val_txt, 'NULL');
    END IF;
    RAISE NOTICE '  ✓ py_object_add("ab", "cd") = "abcd"';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 11: py_object_add(int, str) → TypeError (Phase 3)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 11: py_object_add(int, str) raises TypeError...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();
    res_id := public.py_object_add(int1_id, str_a_id);
    IF res_id IS NOT NULL OR NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: py_object_add(int, str) should raise TypeError, got res_id=%', res_id;
    END IF;
    SELECT g.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() g LIMIT 1;
    IF exc_type_id IS DISTINCT FROM '00000000-0000-4000-a000-000000000022' THEN
        RAISE EXCEPTION 'FAIL: py_object_add(int, str) should set TypeError, got exc_type_id %', exc_type_id;
    END IF;
    PERFORM public.py_err_clear();
    RAISE NOTICE '  ✓ py_object_add(int, str) raises TypeError';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Summary
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total tests: %', test_count;
    RAISE NOTICE 'Passed: %', pass_count;
    RAISE NOTICE 'Failed: %', fail_count;
    RAISE NOTICE '';

    IF fail_count > 0 THEN
        RAISE EXCEPTION 'FAIL: % test(s) failed', fail_count;
    END IF;

    RAISE NOTICE '✓ All BINARY_ADD slots tests passed!';
END $$;
