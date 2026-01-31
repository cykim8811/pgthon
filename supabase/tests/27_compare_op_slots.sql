-- ============================================================================
-- Test: COMPARE_OP — py_object_richcompare reflected op (Phase 1)
--
-- Purpose:
--   Phase 1(240000) 이후 py_object_richcompare가 NotImplemented 시 other 쪽
--   tp_richcompare(reflected_op)를 시도하는지 검증. 기존 20번 테스트와 호환되며,
--   int/str 혼합 비교 시 양쪽 순서 모두 NotImplemented 반환 확인.
--
-- Usage:
--   Run after migration 20260114240000_compare_op_phase1_richcompare_reflected.sql.
-- ============================================================================

DO $$
DECLARE
    ID_STR_TYPE   UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE   UUID := '00000000-0000-4000-a000-000000000004';
    ID_TRUE_OBJ   UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ  UUID := '00000000-0000-4000-b000-000000000011';
    ID_NOT_IMPLEMENTED_OBJ UUID := '00000000-0000-4000-b000-000000000012';

    Py_LT INTEGER := 0;
    Py_EQ INTEGER := 2;
    Py_GT INTEGER := 4;

    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    str_id uuid;
    int_id uuid;
    res_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'COMPARE_OP Slots (reflected op) Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- str instance
    str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_id, 'a');

    -- int instance
    int_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int_id, 1);

    -- Test 1: py_object_richcompare(int, str, Py_LT) -> NotImplemented (int then str reflected)
    RAISE NOTICE 'Test 1: py_object_richcompare(int, str, Py_LT) -> NotImplemented...';
    test_count := test_count + 1;
    res_id := public.py_object_richcompare(int_id, str_id, Py_LT);
    IF res_id IS DISTINCT FROM ID_NOT_IMPLEMENTED_OBJ THEN
        RAISE EXCEPTION 'FAIL: py_object_richcompare(int, str, Py_LT) should return NotImplemented, got %', res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ int, str Py_LT -> NotImplemented';

    -- Test 2: py_object_richcompare(str, int, Py_GT) -> NotImplemented (str then int reflected Py_LT)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: py_object_richcompare(str, int, Py_GT) -> NotImplemented...';
    test_count := test_count + 1;
    res_id := public.py_object_richcompare(str_id, int_id, Py_GT);
    IF res_id IS DISTINCT FROM ID_NOT_IMPLEMENTED_OBJ THEN
        RAISE EXCEPTION 'FAIL: py_object_richcompare(str, int, Py_GT) should return NotImplemented, got %', res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ str, int Py_GT -> NotImplemented';

    -- Test 3: py_object_richcompare(int, int, Py_EQ) -> True (unchanged)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: py_object_richcompare(int, int same, Py_EQ) -> True...';
    test_count := test_count + 1;
    res_id := public.py_object_richcompare(int_id, int_id, Py_EQ);
    IF res_id IS DISTINCT FROM ID_TRUE_OBJ THEN
        RAISE EXCEPTION 'FAIL: py_object_richcompare(int, int, Py_EQ) should return True, got %', res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ int, int Py_EQ -> True';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total: %  Passed: %', test_count, pass_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'FAIL: % test(s) failed', test_count - pass_count;
    END IF;
    RAISE NOTICE '✓ All COMPARE_OP slots (reflected) tests passed!';
END $$;
