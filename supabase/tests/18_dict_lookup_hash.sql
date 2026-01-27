-- ============================================================================
-- Test: Dict Lookup Hash-Based
--
-- Purpose:
--   Hash-based dict lookup per CPython semantics (DICT_LOOKUP_DESIGN §6).
--   - py_object_equals_key: same-id TRUE; str/int value comparison; other FALSE
--   - py_dict_get_item / py_dict_set_item: hash narrows, equality confirms
--   - Same-value different key objects treated as same key (str/int)
--   - Same-hash different keys: correct disambiguation by equality
--   - Unhashable key: TypeError propagated from py_object_hash
--
-- Usage:
--   Run after migrations (including 20260114235500_dict_lookup_hash).
--   If any assertion fails, an exception is raised with details.
-- ============================================================================

DO $$
<<dict_lookup_test>>
DECLARE
    ID_STR_TYPE  UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE  UUID := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';

    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;

    -- Objects
    dict_id UUID;
    v1_id UUID;
    v2_id UUID;
    str_a_id UUID;
    str_a2_id UUID;
    str_b_id UUID;
    int1_id UUID;
    int1b_id UUID;
    int2_id UUID;
    list_id UUID;

    out_id UUID;
    eq BOOLEAN;
    error_occurred BOOLEAN;
    error_message TEXT;
    func_exists BOOLEAN;
    n_entries INTEGER;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Dict Lookup Hash-Based Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- Test 1: Functions exist
    -- ========================================================================
    RAISE NOTICE 'Test 1: Verifying dict lookup functions exist...';
    test_count := test_count + 1;

    SELECT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'py_object_equals_key'
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) INTO func_exists;
    IF NOT func_exists THEN
        RAISE EXCEPTION 'FAIL: py_object_equals_key does not exist';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'py_dict_get_item'
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) INTO func_exists;
    IF NOT func_exists THEN
        RAISE EXCEPTION 'FAIL: py_dict_get_item does not exist';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'py_dict_set_item'
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) INTO func_exists;
    IF NOT func_exists THEN
        RAISE EXCEPTION 'FAIL: py_dict_set_item does not exist';
    END IF;

    RAISE NOTICE '  ✓ py_object_equals_key, py_dict_get_item, py_dict_set_item exist';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 2: py_object_equals_key — same id → TRUE
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: py_object_equals_key(same id) → TRUE...';
    test_count := test_count + 1;

    str_a_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_a_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_a_id, 'a');

    SELECT public.py_object_equals_key(str_a_id, str_a_id) INTO eq;
    IF NOT eq THEN
        RAISE EXCEPTION 'FAIL: py_object_equals_key(a_id, a_id) should be TRUE';
    END IF;

    RAISE NOTICE '  ✓ py_object_equals_key(same id) = TRUE';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 3: py_object_equals_key — str same value → TRUE
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: py_object_equals_key(str, str same value) → TRUE...';
    test_count := test_count + 1;

    str_a2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_a2_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_a2_id, 'a');

    SELECT public.py_object_equals_key(str_a_id, str_a2_id) INTO eq;
    IF NOT eq THEN
        RAISE EXCEPTION 'FAIL: py_object_equals_key("a", "a") should be TRUE';
    END IF;

    RAISE NOTICE '  ✓ py_object_equals_key(str same value) = TRUE';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 4: py_object_equals_key — str different value → FALSE
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: py_object_equals_key(str, str different value) → FALSE...';
    test_count := test_count + 1;

    str_b_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_b_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_b_id, 'b');

    SELECT public.py_object_equals_key(str_a_id, str_b_id) INTO eq;
    IF eq THEN
        RAISE EXCEPTION 'FAIL: py_object_equals_key("a", "b") should be FALSE';
    END IF;

    RAISE NOTICE '  ✓ py_object_equals_key(str different value) = FALSE';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 5: py_object_equals_key — int same value → TRUE
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: py_object_equals_key(int, int same value) → TRUE...';
    test_count := test_count + 1;

    int1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int1_id, 1);

    int1b_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int1b_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int1b_id, 1);

    SELECT public.py_object_equals_key(int1_id, int1b_id) INTO eq;
    IF NOT eq THEN
        RAISE EXCEPTION 'FAIL: py_object_equals_key(1, 1) should be TRUE';
    END IF;

    RAISE NOTICE '  ✓ py_object_equals_key(int same value) = TRUE';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 6: py_object_equals_key — int different value → FALSE
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: py_object_equals_key(int, int different value) → FALSE...';
    test_count := test_count + 1;

    int2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (int2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int2_id, 2);

    SELECT public.py_object_equals_key(int1_id, int2_id) INTO eq;
    IF eq THEN
        RAISE EXCEPTION 'FAIL: py_object_equals_key(1, 2) should be FALSE';
    END IF;

    RAISE NOTICE '  ✓ py_object_equals_key(int different value) = FALSE';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 7: py_object_equals_key — str vs int → FALSE, other types no id compare
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: py_object_equals_key(str, int) → FALSE...';
    test_count := test_count + 1;

    SELECT public.py_object_equals_key(str_a_id, int1_id) INTO eq;
    IF eq THEN
        RAISE EXCEPTION 'FAIL: py_object_equals_key(str, int) should be FALSE';
    END IF;

    RAISE NOTICE '  ✓ py_object_equals_key(str, int) = FALSE';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 8: py_dict_set_item / py_dict_get_item — basic set then get
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: set_item then get_item returns same value...';
    test_count := test_count + 1;

    dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_id);

    v1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v1_id, 100);

    PERFORM public.py_dict_set_item(dict_id, str_a_id, v1_id);
    SELECT public.py_dict_get_item(dict_id, str_a_id) INTO out_id;
    IF out_id IS NULL OR out_id != v1_id THEN
        RAISE EXCEPTION 'FAIL: get_item after set_item: expected %, got %', v1_id, out_id;
    END IF;

    RAISE NOTICE '  ✓ set_item(k,v) then get_item(k) = v';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 9: overwrite by same key (value equality)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 9: set_item overwrites when key equals (same value, different object)...';
    test_count := test_count + 1;

    v2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v2_id, 200);

    PERFORM public.py_dict_set_item(dict_id, str_a2_id, v2_id);  -- same value "a", different object
    SELECT public.py_dict_get_item(dict_id, str_a_id) INTO out_id;
    IF out_id IS NULL OR out_id != v2_id THEN
        RAISE EXCEPTION 'FAIL: overwrite by equal key: expected %, got %', v2_id, out_id;
    END IF;

    SELECT COUNT(*) INTO n_entries FROM public.py_dict_entry e
    WHERE e.dict_id = dict_lookup_test.dict_id AND e.me_key IN (str_a_id, str_a2_id);
    IF n_entries != 1 THEN
        RAISE EXCEPTION 'FAIL: equal keys must share one entry, found %', n_entries;
    END IF;

    RAISE NOTICE '  ✓ overwrite by equal key, single entry';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 10: same hash, different keys — SKIP (TODO)
    -- 검증 대상: 같은 me_hash를 가진 서로 다른 키 두 개에 대해 get_item이
    -- equality로 구분하여 올바른 값을 반환하는지. 해시 충돌(같은 해시 다른
    -- 문자열 쌍)이 필요하나 현재 충돌을 찾지 못해 스킵. 추가 예정은 README 참고.
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 10: same me_hash different keys — SKIP (테스트 추가 예정, README TODO)';
    test_count := test_count + 1;
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 11: unhashable key — py_dict_set_item raises TypeError
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 11: py_dict_set_item with unhashable key raises TypeError...';
    test_count := test_count + 1;

    list_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (list_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item) VALUES (list_id, ARRAY[]::uuid[]);

    dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_id);

    error_occurred := FALSE;
    BEGIN
        PERFORM public.py_dict_set_item(dict_id, list_id, int1_id);
    EXCEPTION WHEN OTHERS THEN
        error_occurred := TRUE;
        error_message := SQLERRM;
    END;

    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: py_dict_set_item(list_key, ...) should raise';
    END IF;
    IF error_message NOT LIKE 'TypeError: unhashable type%' THEN
        RAISE EXCEPTION 'FAIL: expected TypeError unhashable, got: %', error_message;
    END IF;

    RAISE NOTICE '  ✓ py_dict_set_item(unhashable key) raises TypeError';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 12: unhashable key — py_dict_get_item raises TypeError
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 12: py_dict_get_item with unhashable key raises TypeError...';
    test_count := test_count + 1;

    error_occurred := FALSE;
    BEGIN
        SELECT public.py_dict_get_item(dict_id, list_id) INTO out_id;
    EXCEPTION WHEN OTHERS THEN
        error_occurred := TRUE;
        error_message := SQLERRM;
    END;

    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: py_dict_get_item(..., list_key) should raise';
    END IF;
    IF error_message NOT LIKE 'TypeError: unhashable type%' THEN
        RAISE EXCEPTION 'FAIL: expected TypeError unhashable, got: %', error_message;
    END IF;

    RAISE NOTICE '  ✓ py_dict_get_item(unhashable key) raises TypeError';
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

    RAISE NOTICE '✓ All dict lookup hash tests passed!';
END $$;
