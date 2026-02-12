-- ============================================================================
-- Test: BINARY_SUBTRACT Slots (nb_subtract, py_object_subtract_via_nb, py_object_subtract)
--
-- Purpose:
--   Phase 1+2+3 구현 검증.
--   - int의 tp_as_number에 nb_subtract 등록 여부
--   - py_object_subtract_via_nb(int, int) → 차
--   - py_object_subtract_via_nb(int, str) → NotImplemented id
--   - py_object_subtract(int, int) → 차
--   - py_object_subtract(int, str) → TypeError
--
-- Usage:
--   Run after migrations 238500, 238600, 238700. If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_INT_TYPE  uuid := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE  uuid := '00000000-0000-4000-a000-000000000003';
    ID_NOT_IMPLEMENTED uuid := '00000000-0000-4000-b000-000000000012';
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    int1_id uuid; int2_id uuid; str_a_id uuid;
    res_id uuid;
    num_id uuid;
    nb_subtract_slot regproc;
    val_num numeric;
    exc_type_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'BINARY_SUBTRACT Slots Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Test 1: int의 tp_as_number에 nb_subtract 등록 여부
    RAISE NOTICE 'Test 1: int has nb_subtract in tp_as_number...';
    test_count := test_count + 1;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = ID_INT_TYPE;
    IF num_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: int type has no tp_as_number';
    END IF;
    SELECT nb_subtract INTO nb_subtract_slot FROM public.py_number_methods WHERE id = num_id;
    IF nb_subtract_slot IS NULL THEN
        RAISE EXCEPTION 'FAIL: int tp_as_number has no nb_subtract';
    END IF;
    RAISE NOTICE '  ✓ int has nb_subtract registered';
    pass_count := pass_count + 1;

    -- Test 2: py_object_subtract_via_nb(int, int) → 차
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: py_object_subtract_via_nb(10, 3) returns 7...';
    test_count := test_count + 1;
    int1_id := gen_random_uuid();
    int2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int1_id, ID_INT_TYPE), (int2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int1_id, 10), (int2_id, 3);
    res_id := public.py_object_subtract_via_nb(int1_id, int2_id);
    IF res_id IS NULL OR res_id = ID_NOT_IMPLEMENTED THEN
        RAISE EXCEPTION 'FAIL: py_object_subtract_via_nb(10, 3) returned NotImplemented/NULL';
    END IF;
    SELECT long_value INTO val_num FROM public.py_long_object WHERE ob_base = res_id;
    IF val_num IS NULL OR val_num <> 7 THEN
        RAISE EXCEPTION 'FAIL: py_object_subtract_via_nb(10, 3) result %, expected 7', val_num;
    END IF;
    RAISE NOTICE '  ✓ py_object_subtract_via_nb(10, 3) = 7';
    pass_count := pass_count + 1;

    -- Test 3: py_object_subtract_via_nb(int, str) → NotImplemented
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: py_object_subtract_via_nb(int, str) returns NotImplemented...';
    test_count := test_count + 1;
    str_a_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_a_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_a_id, 'a');
    res_id := public.py_object_subtract_via_nb(int1_id, str_a_id);
    IF res_id IS DISTINCT FROM ID_NOT_IMPLEMENTED THEN
        RAISE EXCEPTION 'FAIL: py_object_subtract_via_nb(int, str) should return NotImplemented id, got %', res_id;
    END IF;
    RAISE NOTICE '  ✓ py_object_subtract_via_nb(int, str) = NotImplemented';
    pass_count := pass_count + 1;

    -- Test 4: py_object_subtract(int, int) → 차
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: py_object_subtract(10, 3) returns 7...';
    test_count := test_count + 1;
    res_id := public.py_object_subtract(int1_id, int2_id);
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_object_subtract(10, 3) returned NULL';
    END IF;
    SELECT long_value INTO val_num FROM public.py_long_object WHERE ob_base = res_id;
    IF val_num IS NULL OR val_num <> 7 THEN
        RAISE EXCEPTION 'FAIL: py_object_subtract(10, 3) result %, expected 7', val_num;
    END IF;
    RAISE NOTICE '  ✓ py_object_subtract(10, 3) = 7';
    pass_count := pass_count + 1;

    -- Test 5: py_object_subtract(int, str) → TypeError
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: py_object_subtract(int, str) raises TypeError...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();
    res_id := public.py_object_subtract(int1_id, str_a_id);
    IF res_id IS NOT NULL OR NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: py_object_subtract(int, str) should raise TypeError, got res_id=%', res_id;
    END IF;
    SELECT g.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() g LIMIT 1;
    IF exc_type_id IS DISTINCT FROM '00000000-0000-4000-a000-000000000022' THEN
        RAISE EXCEPTION 'FAIL: py_object_subtract(int, str) should set TypeError, got exc_type_id %', exc_type_id;
    END IF;
    PERFORM public.py_err_clear();
    RAISE NOTICE '  ✓ py_object_subtract(int, str) raises TypeError';
    pass_count := pass_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: Total %  Passed %  Failed %', test_count, pass_count, fail_count;
    IF fail_count > 0 THEN
        RAISE EXCEPTION 'FAIL: % test(s) failed', fail_count;
    END IF;
    RAISE NOTICE '✓ All BINARY_SUBTRACT slots tests passed!';
END $$;
