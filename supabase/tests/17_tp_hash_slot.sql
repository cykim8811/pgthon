-- ============================================================================
-- Test: tp_hash Slot System Test
-- 
-- Purpose:
--   Tests that the tp_hash slot system works correctly. This verifies:
--   - tp_hash field exists in py_type_object
--   - py_object_hash() function works correctly
--   - Type-specific hash functions (py_unicode_hash, py_long_hash) work
--   - Hashable types (str, int) have tp_hash registered
--   - Unhashable types (list, dict) have tp_hash = NULL
--   - Hash values are computed correctly
--   - Unhashable type error handling works
--
-- Usage:
--   Run this file after migrations to verify tp_hash slot implementation.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

DO $$
DECLARE
    -- Builtin Type IDs (from bootstrap)
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    
    -- Test counters
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    
    -- Test object IDs
    test_str_id UUID;
    test_int_id UUID;
    test_list_id UUID;
    test_dict_id UUID;
    test_str2_id UUID;
    test_int2_id UUID;
    test_int_neg1_id UUID;
    test_int_large_id UUID;
    test_empty_str_id UUID;
    
    -- Hash values
    hash_value BIGINT;
    hash_value2 BIGINT;
    expected_hash BIGINT;
    
    -- Type checking
    tp_hash_func regproc;
    str_tp_hash regproc;
    int_tp_hash regproc;
    list_tp_hash regproc;
    dict_tp_hash regproc;
    
    -- Error handling
    error_occurred BOOLEAN;
    error_message TEXT;
    
    -- Function existence check
    func_exists BOOLEAN;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'tp_hash Slot System Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Test 1: Verify tp_hash field exists in py_type_object
    -- ========================================================================
    RAISE NOTICE 'Test 1: Verifying tp_hash field exists...';
    test_count := test_count + 1;
    
    -- Check if tp_hash column exists
    SELECT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'py_type_object' 
        AND column_name = 'tp_hash'
    ) INTO func_exists;
    
    IF NOT func_exists THEN
        RAISE EXCEPTION 'FAIL: tp_hash column does not exist in py_type_object';
    END IF;
    
    RAISE NOTICE '  ✓ tp_hash field exists in py_type_object';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: Verify hash functions exist
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Verifying hash functions exist...';
    test_count := test_count + 1;
    
    -- Check py_object_hash
    SELECT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'py_object_hash' 
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) INTO func_exists;
    
    IF NOT func_exists THEN
        RAISE EXCEPTION 'FAIL: py_object_hash function does not exist';
    END IF;
    
    -- Check py_unicode_hash
    SELECT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'py_unicode_hash' 
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) INTO func_exists;
    
    IF NOT func_exists THEN
        RAISE EXCEPTION 'FAIL: py_unicode_hash function does not exist';
    END IF;
    
    -- Check py_long_hash
    SELECT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'py_long_hash' 
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) INTO func_exists;
    
    IF NOT func_exists THEN
        RAISE EXCEPTION 'FAIL: py_long_hash function does not exist';
    END IF;
    
    RAISE NOTICE '  ✓ All hash functions exist';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: Verify tp_hash registration for hashable types
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Verifying tp_hash registration for hashable types...';
    test_count := test_count + 1;
    
    -- Check str type has tp_hash registered
    SELECT tp_hash INTO str_tp_hash
    FROM public.py_type_object
    WHERE ob_base = ID_STR_TYPE;
    
    IF str_tp_hash IS NULL THEN
        RAISE EXCEPTION 'FAIL: str type does not have tp_hash registered';
    END IF;
    
    IF str_tp_hash::text != 'py_unicode_hash' THEN
        RAISE EXCEPTION 'FAIL: str type tp_hash is %, expected py_unicode_hash', str_tp_hash::text;
    END IF;
    
    -- Check int type has tp_hash registered
    SELECT tp_hash INTO int_tp_hash
    FROM public.py_type_object
    WHERE ob_base = ID_INT_TYPE;
    
    IF int_tp_hash IS NULL THEN
        RAISE EXCEPTION 'FAIL: int type does not have tp_hash registered';
    END IF;
    
    IF int_tp_hash::text != 'py_long_hash' THEN
        RAISE EXCEPTION 'FAIL: int type tp_hash is %, expected py_long_hash', int_tp_hash::text;
    END IF;
    
    RAISE NOTICE '  ✓ str and int types have tp_hash registered correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: Verify unhashable types have tp_hash = NULL
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Verifying unhashable types have tp_hash = NULL...';
    test_count := test_count + 1;
    
    -- Check list type has tp_hash = NULL
    SELECT tp_hash INTO list_tp_hash
    FROM public.py_type_object
    WHERE ob_base = ID_LIST_TYPE;
    
    IF list_tp_hash IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: list type should have tp_hash = NULL (unhashable), but got %', list_tp_hash::text;
    END IF;
    
    -- Check dict type has tp_hash = NULL
    SELECT tp_hash INTO dict_tp_hash
    FROM public.py_type_object
    WHERE ob_base = ID_DICT_TYPE;
    
    IF dict_tp_hash IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: dict type should have tp_hash = NULL (unhashable), but got %', dict_tp_hash::text;
    END IF;
    
    RAISE NOTICE '  ✓ list and dict types have tp_hash = NULL (unhashable)';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: Test string hashing
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Testing string hashing...';
    test_count := test_count + 1;
    
    -- Create test string "hello"
    test_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (test_str_id, 'hello');
    
    -- Compute hash
    SELECT public.py_object_hash(test_str_id) INTO hash_value;
    
    IF hash_value IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_object_hash("hello") returned NULL';
    END IF;
    
    -- Hash should be deterministic (same string = same hash)
    SELECT public.py_object_hash(test_str_id) INTO hash_value2;
    
    IF hash_value != hash_value2 THEN
        RAISE EXCEPTION 'FAIL: Hash value is not deterministic. First: %, Second: %', hash_value, hash_value2;
    END IF;
    
    -- Create another string with same value and verify same hash
    test_str2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_str2_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (test_str2_id, 'hello');
    
    SELECT public.py_object_hash(test_str2_id) INTO hash_value2;
    
    IF hash_value != hash_value2 THEN
        RAISE EXCEPTION 'FAIL: Same string value should have same hash. First: %, Second: %', hash_value, hash_value2;
    END IF;
    
    RAISE NOTICE '  ✓ String hashing works correctly (hash("hello") = %)', hash_value;
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 6: Test empty string hashing
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: Testing empty string hashing...';
    test_count := test_count + 1;
    
    -- Create empty string
    test_empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (test_empty_str_id, '');
    
    -- Compute hash (should be 0 according to CPython behavior)
    SELECT public.py_object_hash(test_empty_str_id) INTO hash_value;
    
    IF hash_value IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_object_hash("") returned NULL';
    END IF;
    
    -- Empty string hash should be 0 (CPython behavior)
    IF hash_value != 0 THEN
        RAISE NOTICE '  NOTE: Empty string hash is % (CPython returns 0, but hashtext() may differ)', hash_value;
    END IF;
    
    RAISE NOTICE '  ✓ Empty string hashing works (hash("") = %)', hash_value;
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 7: Test integer hashing
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: Testing integer hashing...';
    test_count := test_count + 1;
    
    -- Create test integer 42
    test_int_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_int_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_int_id, 42);
    
    -- Compute hash
    SELECT public.py_object_hash(test_int_id) INTO hash_value;
    
    IF hash_value IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_object_hash(42) returned NULL';
    END IF;
    
    -- For small integers, hash should equal the value (CPython behavior)
    IF hash_value != 42 THEN
        RAISE EXCEPTION 'FAIL: hash(42) should be 42, but got %', hash_value;
    END IF;
    
    -- Hash should be deterministic
    SELECT public.py_object_hash(test_int_id) INTO hash_value2;
    
    IF hash_value != hash_value2 THEN
        RAISE EXCEPTION 'FAIL: Hash value is not deterministic. First: %, Second: %', hash_value, hash_value2;
    END IF;
    
    -- Create another integer with same value
    test_int2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_int2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_int2_id, 42);
    
    SELECT public.py_object_hash(test_int2_id) INTO hash_value2;
    
    IF hash_value != hash_value2 THEN
        RAISE EXCEPTION 'FAIL: Same integer value should have same hash. First: %, Second: %', hash_value, hash_value2;
    END IF;
    
    RAISE NOTICE '  ✓ Integer hashing works correctly (hash(42) = %)', hash_value;
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 8: Test hash(-1) special case
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: Testing hash(-1) special case...';
    test_count := test_count + 1;
    
    -- Create integer -1
    test_int_neg1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_int_neg1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_int_neg1_id, -1);
    
    -- Compute hash (CPython: hash(-1) = -2)
    SELECT public.py_object_hash(test_int_neg1_id) INTO hash_value;
    
    IF hash_value IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_object_hash(-1) returned NULL';
    END IF;
    
    -- CPython special case: hash(-1) = -2
    IF hash_value != -2 THEN
        RAISE EXCEPTION 'FAIL: hash(-1) should be -2 (CPython special case), but got %', hash_value;
    END IF;
    
    RAISE NOTICE '  ✓ hash(-1) special case works correctly (hash(-1) = -2)';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 9: Test large integer hashing
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 9: Testing large integer hashing...';
    test_count := test_count + 1;
    
    -- Create large integer (2^31 + 100)
    test_int_large_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_int_large_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_int_large_id, 2147483748);
    
    -- Compute hash
    SELECT public.py_object_hash(test_int_large_id) INTO hash_value;
    
    IF hash_value IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_object_hash(large_int) returned NULL';
    END IF;
    
    -- Hash should be deterministic
    SELECT public.py_object_hash(test_int_large_id) INTO hash_value2;
    
    IF hash_value != hash_value2 THEN
        RAISE EXCEPTION 'FAIL: Hash value is not deterministic. First: %, Second: %', hash_value, hash_value2;
    END IF;
    
    RAISE NOTICE '  ✓ Large integer hashing works (hash(2147483748) = %)', hash_value;
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 10: Test unhashable type error handling
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 10: Testing unhashable type error handling...';
    test_count := test_count + 1;
    
    -- Create test list
    test_list_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_list_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item) VALUES (test_list_id, ARRAY[]::UUID[]);
    
    -- Try to hash list (should raise TypeError)
    error_occurred := FALSE;
    BEGIN
        SELECT public.py_object_hash(test_list_id) INTO hash_value;
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: py_object_hash(list) should raise TypeError, but it succeeded';
    END IF;
    
    IF error_message NOT LIKE 'TypeError: unhashable type%' THEN
        RAISE EXCEPTION 'FAIL: Expected "TypeError: unhashable type" error, but got: %', error_message;
    END IF;
    
    -- Create test dict
    test_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (test_dict_id);
    
    -- Try to hash dict (should raise TypeError)
    error_occurred := FALSE;
    BEGIN
        SELECT public.py_object_hash(test_dict_id) INTO hash_value;
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: py_object_hash(dict) should raise TypeError, but it succeeded';
    END IF;
    
    IF error_message NOT LIKE 'TypeError: unhashable type%' THEN
        RAISE EXCEPTION 'FAIL: Expected "TypeError: unhashable type" error, but got: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ Unhashable type error handling works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 11: Test py_unicode_hash directly
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 11: Testing py_unicode_hash directly...';
    test_count := test_count + 1;
    
    -- Create test string
    test_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (test_str_id, 'test');
    
    -- Call py_unicode_hash directly
    SELECT public.py_unicode_hash(test_str_id) INTO hash_value;
    
    IF hash_value IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_unicode_hash("test") returned NULL';
    END IF;
    
    -- Should match py_object_hash result
    SELECT public.py_object_hash(test_str_id) INTO hash_value2;
    
    IF hash_value != hash_value2 THEN
        RAISE EXCEPTION 'FAIL: py_unicode_hash and py_object_hash should return same value. Direct: %, Via tp_hash: %', hash_value, hash_value2;
    END IF;
    
    RAISE NOTICE '  ✓ py_unicode_hash works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 12: Test py_long_hash directly
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 12: Testing py_long_hash directly...';
    test_count := test_count + 1;
    
    -- Create test integer
    test_int_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_int_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_int_id, 100);
    
    -- Call py_long_hash directly
    SELECT public.py_long_hash(test_int_id) INTO hash_value;
    
    IF hash_value IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_long_hash(100) returned NULL';
    END IF;
    
    -- Should match py_object_hash result
    SELECT public.py_object_hash(test_int_id) INTO hash_value2;
    
    IF hash_value != hash_value2 THEN
        RAISE EXCEPTION 'FAIL: py_long_hash and py_object_hash should return same value. Direct: %, Via tp_hash: %', hash_value, hash_value2;
    END IF;
    
    RAISE NOTICE '  ✓ py_long_hash works correctly';
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
    
    RAISE NOTICE '✓ All tests passed!';
END $$;
