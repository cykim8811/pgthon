-- ============================================================================
-- Test: tp_richcompare Slot (CPython Rich Comparison Protocol)
--
-- Purpose:
--   Verifies tp_richcompare slot and dict key equality via py_object_richcompare_eq.
--   Design: docs/DICT_LOOKUP_DESIGN.md §7.
--   - tp_richcompare column and registration for str/int
--   - py_unicode_richcompare, py_long_richcompare (Py_EQ -> True/False, else NotImplemented)
--   - py_object_richcompare dispatch; no-slot type -> NotImplemented
--   - py_object_richcompare_eq (True/False/NotImplemented + reverse)
--   - dict get/set still treat equal str/int keys as same key (uses richcompare_eq)
--
-- Usage:
--   Run after migrations (tp_richcompare is in 20260114236000_tp_richcompare_slot.sql).
--   If any assertion fails, an exception is raised with details.
-- ============================================================================

DO $$
DECLARE
    -- Bootstrap IDs
    ID_STR_TYPE   UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE   UUID := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE  UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE  UUID := '00000000-0000-4000-a000-000000000006';
    ID_TRUE_OBJ   UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ  UUID := '00000000-0000-4000-b000-000000000011';
    ID_NOT_IMPLEMENTED_OBJ UUID := '00000000-0000-4000-b000-000000000012';

    Py_EQ INTEGER := 2;

    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;

    col_exists BOOLEAN;
    func_exists BOOLEAN;
    rcf regproc;
    res_id UUID;
    eq BOOLEAN;

    str_a UUID;
    str_b UUID;
    str_c UUID;
    int_x UUID;
    int_y UUID;
    int_z UUID;
    int_z2 UUID;
    list_id UUID;
    dict_id UUID;
    val_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'tp_richcompare Slot Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- Test 1: tp_richcompare column exists
    -- ========================================================================
    RAISE NOTICE 'Test 1: tp_richcompare column exists...';
    test_count := test_count + 1;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'py_type_object' AND column_name = 'tp_richcompare'
    ) INTO col_exists;
    IF NOT col_exists THEN
        RAISE EXCEPTION 'FAIL: tp_richcompare column does not exist in py_type_object';
    END IF;

    RAISE NOTICE '  ✓ tp_richcompare column exists';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 2: Richcompare functions exist
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Richcompare functions exist...';
    test_count := test_count + 1;

    SELECT (
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_unicode_richcompare' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public'))
        AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_long_richcompare' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public'))
        AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_object_richcompare' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public'))
        AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_object_richcompare_eq' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public'))
    ) INTO func_exists;
    IF NOT func_exists THEN
        RAISE EXCEPTION 'FAIL: One or more of py_unicode_richcompare, py_long_richcompare, py_object_richcompare, py_object_richcompare_eq do not exist';
    END IF;

    RAISE NOTICE '  ✓ py_unicode_richcompare, py_long_richcompare, py_object_richcompare, py_object_richcompare_eq exist';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 3: str and int have tp_richcompare registered
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: str and int have tp_richcompare registered...';
    test_count := test_count + 1;

    SELECT tp_richcompare INTO rcf FROM public.py_type_object WHERE ob_base = ID_STR_TYPE;
    IF rcf IS NULL OR rcf::text != 'py_unicode_richcompare' THEN
        RAISE EXCEPTION 'FAIL: str type tp_richcompare is %, expected py_unicode_richcompare', COALESCE(rcf::text, 'NULL');
    END IF;

    SELECT tp_richcompare INTO rcf FROM public.py_type_object WHERE ob_base = ID_INT_TYPE;
    IF rcf IS NULL OR rcf::text != 'py_long_richcompare' THEN
        RAISE EXCEPTION 'FAIL: int type tp_richcompare is %, expected py_long_richcompare', COALESCE(rcf::text, 'NULL');
    END IF;

    RAISE NOTICE '  ✓ str -> py_unicode_richcompare, int -> py_long_richcompare';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 4: py_unicode_richcompare Py_EQ same str -> True id
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: py_unicode_richcompare(str, str same value, Py_EQ) -> True id...';
    test_count := test_count + 1;

    str_a := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_a, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_a, 'x');

    str_b := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_b, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_b, 'x');

    res_id := public.py_unicode_richcompare(str_a, str_b, Py_EQ);
    IF res_id IS DISTINCT FROM ID_TRUE_OBJ THEN
        RAISE EXCEPTION 'FAIL: py_unicode_richcompare("x","x",Py_EQ) should return True id, got %', res_id;
    END IF;

    RAISE NOTICE '  ✓ py_unicode_richcompare(same str, Py_EQ) = True id';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 5: py_unicode_richcompare Py_EQ different str -> False id
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: py_unicode_richcompare(str, str different value, Py_EQ) -> False id...';
    test_count := test_count + 1;

    str_c := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_c, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_c, 'y');

    res_id := public.py_unicode_richcompare(str_a, str_c, Py_EQ);
    IF res_id IS DISTINCT FROM ID_FALSE_OBJ THEN
        RAISE EXCEPTION 'FAIL: py_unicode_richcompare("x","y",Py_EQ) should return False id, got %', res_id;
    END IF;

    RAISE NOTICE '  ✓ py_unicode_richcompare(different str, Py_EQ) = False id';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 6: py_unicode_richcompare other not str -> NotImplemented id
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: py_unicode_richcompare(str, int, Py_EQ) -> NotImplemented id...';
    test_count := test_count + 1;

    int_x := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int_x, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int_x, 1);

    res_id := public.py_unicode_richcompare(str_a, int_x, Py_EQ);
    IF res_id IS DISTINCT FROM ID_NOT_IMPLEMENTED_OBJ THEN
        RAISE EXCEPTION 'FAIL: py_unicode_richcompare(str, int, Py_EQ) should return NotImplemented id, got %', res_id;
    END IF;

    RAISE NOTICE '  ✓ py_unicode_richcompare(str, int, Py_EQ) = NotImplemented id';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 7: py_unicode_richcompare op <> Py_EQ -> NotImplemented id
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: py_unicode_richcompare(str, str, Py_LT) -> NotImplemented id...';
    test_count := test_count + 1;

    res_id := public.py_unicode_richcompare(str_a, str_b, 0);  -- Py_LT
    IF res_id IS DISTINCT FROM ID_NOT_IMPLEMENTED_OBJ THEN
        RAISE EXCEPTION 'FAIL: py_unicode_richcompare(..., Py_LT) should return NotImplemented id, got %', res_id;
    END IF;

    RAISE NOTICE '  ✓ py_unicode_richcompare(..., Py_LT) = NotImplemented id';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 8: py_long_richcompare Py_EQ same int -> True id
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: py_long_richcompare(int, int same value, Py_EQ) -> True id...';
    test_count := test_count + 1;

    int_y := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int_y, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int_y, 1);

    res_id := public.py_long_richcompare(int_x, int_y, Py_EQ);
    IF res_id IS DISTINCT FROM ID_TRUE_OBJ THEN
        RAISE EXCEPTION 'FAIL: py_long_richcompare(1, 1, Py_EQ) should return True id, got %', res_id;
    END IF;

    RAISE NOTICE '  ✓ py_long_richcompare(same int, Py_EQ) = True id';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 9: py_long_richcompare Py_EQ different int -> False id
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 9: py_long_richcompare(int, int different value, Py_EQ) -> False id...';
    test_count := test_count + 1;

    int_z := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int_z, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int_z, 2);
    res_id := public.py_long_richcompare(int_x, int_z, Py_EQ);
    IF res_id IS DISTINCT FROM ID_FALSE_OBJ THEN
        RAISE EXCEPTION 'FAIL: py_long_richcompare(1, 2, Py_EQ) should return False id, got %', res_id;
    END IF;

    RAISE NOTICE '  ✓ py_long_richcompare(different int, Py_EQ) = False id';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 10: py_object_richcompare dispatches (str eq -> True id)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 10: py_object_richcompare(str, str same, Py_EQ) -> True id...';
    test_count := test_count + 1;

    res_id := public.py_object_richcompare(str_a, str_b, Py_EQ);
    IF res_id IS DISTINCT FROM ID_TRUE_OBJ THEN
        RAISE EXCEPTION 'FAIL: py_object_richcompare(str, str same, Py_EQ) should return True id, got %', res_id;
    END IF;

    RAISE NOTICE '  ✓ py_object_richcompare dispatches to str, returns True id';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 11: py_object_richcompare type with no slot -> NotImplemented id
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 11: py_object_richcompare(list, list, Py_EQ) -> NotImplemented id...';
    test_count := test_count + 1;

    list_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (list_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item) VALUES (list_id, ARRAY[]::uuid[]);

    res_id := public.py_object_richcompare(list_id, list_id, Py_EQ);
    IF res_id IS DISTINCT FROM ID_NOT_IMPLEMENTED_OBJ THEN
        RAISE EXCEPTION 'FAIL: py_object_richcompare(list, list, Py_EQ) should return NotImplemented id (no slot), got %', res_id;
    END IF;

    RAISE NOTICE '  ✓ py_object_richcompare(no-slot type) = NotImplemented id';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 12: py_object_richcompare_eq same id -> TRUE
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 12: py_object_richcompare_eq(same id) -> TRUE...';
    test_count := test_count + 1;

    SELECT public.py_object_richcompare_eq(str_a, str_a) INTO eq;
    IF NOT eq THEN
        RAISE EXCEPTION 'FAIL: py_object_richcompare_eq(same id) should be TRUE';
    END IF;

    RAISE NOTICE '  ✓ py_object_richcompare_eq(same id) = TRUE';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 13: py_object_richcompare_eq str same value -> TRUE
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 13: py_object_richcompare_eq(str, str same value) -> TRUE...';
    test_count := test_count + 1;

    SELECT public.py_object_richcompare_eq(str_a, str_b) INTO eq;
    IF NOT eq THEN
        RAISE EXCEPTION 'FAIL: py_object_richcompare_eq("x","x") should be TRUE';
    END IF;

    RAISE NOTICE '  ✓ py_object_richcompare_eq(str same value) = TRUE';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 14: py_object_richcompare_eq str different value -> FALSE
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 14: py_object_richcompare_eq(str, str different value) -> FALSE...';
    test_count := test_count + 1;

    SELECT public.py_object_richcompare_eq(str_a, str_c) INTO eq;
    IF eq THEN
        RAISE EXCEPTION 'FAIL: py_object_richcompare_eq("x","y") should be FALSE';
    END IF;

    RAISE NOTICE '  ✓ py_object_richcompare_eq(str different value) = FALSE';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 15: py_object_richcompare_eq int same/different
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 15: py_object_richcompare_eq(int same/different)...';
    test_count := test_count + 1;

    SELECT public.py_object_richcompare_eq(int_x, int_y) INTO eq;
    IF NOT eq THEN
        RAISE EXCEPTION 'FAIL: py_object_richcompare_eq(1, 1) should be TRUE';
    END IF;

    int_z2 := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int_z2, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int_z2, 2);
    SELECT public.py_object_richcompare_eq(int_x, int_z2) INTO eq;
    IF eq THEN
        RAISE EXCEPTION 'FAIL: py_object_richcompare_eq(1, 2) should be FALSE';
    END IF;

    RAISE NOTICE '  ✓ py_object_richcompare_eq(int same/different) correct';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 16: dict get/set uses py_object_richcompare_eq (equal str keys same slot)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 16: dict get/set treats equal str keys as same (via richcompare_eq)...';
    test_count := test_count + 1;

    dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_id);

    val_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (val_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (val_id, 99);

    PERFORM public.py_dict_set_item(dict_id, str_a, val_id);
    val_id := public.py_dict_get_item(dict_id, str_b);
    IF val_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: set_item(d, str_a, v); get_item(d, str_b) should return v when str_a.str_value = str_b.str_value';
    END IF;

    RAISE NOTICE '  ✓ dict set by str_a, get by str_b (same value) returns same value';
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

    RAISE NOTICE '✓ All tp_richcompare slot tests passed!';
END $$;
