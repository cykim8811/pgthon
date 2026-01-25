-- ============================================================================
-- Test: Builtin Functions Integration Test
-- 
-- Purpose:
--   Tests that builtin functions actually work by creating test objects and
--   calling the functions. This verifies:
--   - Functions can be called correctly
--   - Functions return correct results
--   - Error handling works properly
--   - Type checking works correctly
--
-- Usage:
--   Run this file after migrations to verify builtin function implementations.
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
    ID_NONE_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    
    -- Test counters
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    
    -- Test object IDs
    test_str_id UUID;
    test_list_id UUID;
    test_tuple_id UUID;
    test_dict_id UUID;
    test_empty_list_id UUID;
    test_empty_str_id UUID;
    
    -- Result IDs
    result_id UUID;
    result_value NUMERIC;
    expected_length INTEGER;
    
    -- Error handling
    error_occurred BOOLEAN;
    error_message TEXT;
    
    -- Temporary variables for nested blocks
    result_type_id UUID;
    
    -- Builtin function lookup
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_LEN_FUNCTION UUID := '00000000-0000-4000-b000-000000000003';
    builtins_dict_id UUID;
    len_function_id UUID;
    len_ml_meth TEXT;
    len_name_str_id UUID;
    elem1_id UUID;
    elem2_id UUID;
    elem3_id UUID;
    tup_elem1_id UUID;
    tup_elem2_id UUID;
    key1_id UUID;
    key2_id UUID;
    val1_id UUID;
    val2_id UUID;
    test_int_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Builtin Functions Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- Test 1: len() on string object
    -- ========================================================================
    RAISE NOTICE 'Test 1: Testing len() on string object...';
    test_count := test_count + 1;
    
    -- Create test string "hello"
    test_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (test_str_id, 'hello');
    
    -- Call len function
    SELECT public.py_builtin_len(test_str_id) INTO result_id;
    
    -- Verify result
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: len("hello") returned NULL';
    END IF;
    
    -- Check result type
    SELECT ob_type INTO result_type_id FROM public.py_object WHERE id = result_id;
    IF result_type_id != ID_INT_TYPE THEN
        RAISE EXCEPTION 'FAIL: len() result type is not int';
    END IF;
    
    -- Get the actual result value
    SELECT lo.long_value INTO result_value
    FROM public.py_long_object lo
    WHERE lo.ob_base = result_id;
    
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL: len("hello") returned %, expected 5', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ len("hello") = 5';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 2: len() on empty string
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Testing len() on empty string...';
    test_count := test_count + 1;
    
    -- Create empty string
    test_empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (test_empty_str_id, '');
    
    -- Call len function
    SELECT public.py_builtin_len(test_empty_str_id) INTO result_id;
    
    -- Get result value
    SELECT lo.long_value INTO result_value
    FROM public.py_long_object lo
    WHERE lo.ob_base = result_id;
    
    IF result_value != 0 THEN
        RAISE EXCEPTION 'FAIL: len("") returned %, expected 0', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ len("") = 0';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 3: len() on list object
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Testing len() on list object...';
    test_count := test_count + 1;
    
    -- Create test list with 3 elements
    test_list_id := gen_random_uuid();
    elem1_id := gen_random_uuid();
    elem2_id := gen_random_uuid();
    elem3_id := gen_random_uuid();
    
    -- Create placeholder elements (just PyObjects, type doesn't matter for length)
    INSERT INTO public.py_object (id, ob_type) VALUES
    (elem1_id, ID_INT_TYPE),
    (elem2_id, ID_INT_TYPE),
    (elem3_id, ID_INT_TYPE);
    
    -- Create list object
    INSERT INTO public.py_object (id, ob_type) VALUES (test_list_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item)
    VALUES (test_list_id, ARRAY[elem1_id, elem2_id, elem3_id]);
    
    -- Call len function
    SELECT public.py_builtin_len(test_list_id) INTO result_id;
    
    -- Get result value
    SELECT lo.long_value INTO result_value
    FROM public.py_long_object lo
    WHERE lo.ob_base = result_id;
    
    IF result_value != 3 THEN
        RAISE EXCEPTION 'FAIL: len([1,2,3]) returned %, expected 3', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ len([1,2,3]) = 3';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 4: len() on empty list
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Testing len() on empty list...';
    test_count := test_count + 1;
    
    -- Create empty list
    test_empty_list_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_empty_list_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item)
    VALUES (test_empty_list_id, ARRAY[]::uuid[]);
    
    -- Call len function
    SELECT public.py_builtin_len(test_empty_list_id) INTO result_id;
    
    -- Get result value
    SELECT lo.long_value INTO result_value
    FROM public.py_long_object lo
    WHERE lo.ob_base = result_id;
    
    IF result_value != 0 THEN
        RAISE EXCEPTION 'FAIL: len([]) returned %, expected 0', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ len([]) = 0';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 5: len() on tuple object
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Testing len() on tuple object...';
    test_count := test_count + 1;
    
    -- Create test tuple with 2 elements
    test_tuple_id := gen_random_uuid();
    tup_elem1_id := gen_random_uuid();
    tup_elem2_id := gen_random_uuid();
    
    -- Create placeholder elements
    INSERT INTO public.py_object (id, ob_type) VALUES
    (tup_elem1_id, ID_INT_TYPE),
    (tup_elem2_id, ID_INT_TYPE);
    
    -- Create tuple object
    INSERT INTO public.py_object (id, ob_type) VALUES (test_tuple_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item)
    VALUES (test_tuple_id, ARRAY[tup_elem1_id, tup_elem2_id]);
    
    -- Call len function
    SELECT public.py_builtin_len(test_tuple_id) INTO result_id;
    
    -- Get result value
    SELECT lo.long_value INTO result_value
    FROM public.py_long_object lo
    WHERE lo.ob_base = result_id;
    
    IF result_value != 2 THEN
        RAISE EXCEPTION 'FAIL: len((1,2)) returned %, expected 2', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ len((1,2)) = 2';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 6: len() on dict object
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: Testing len() on dict object...';
    test_count := test_count + 1;
    
    -- Create test dict with 2 entries
    test_dict_id := gen_random_uuid();
    key1_id := gen_random_uuid();
    key2_id := gen_random_uuid();
    val1_id := gen_random_uuid();
    val2_id := gen_random_uuid();
    
    -- Create dict object
    INSERT INTO public.py_object (id, ob_type) VALUES (test_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (test_dict_id);
    
    -- Create key and value objects
    INSERT INTO public.py_object (id, ob_type) VALUES
    (key1_id, ID_STR_TYPE),
    (key2_id, ID_STR_TYPE),
    (val1_id, ID_INT_TYPE),
    (val2_id, ID_INT_TYPE);
    
    -- Create string values for keys
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES
    (key1_id, 'a'),
    (key2_id, 'b');
    
    -- Create dict entries (test_dict_id is the dict_id due to shared-PK)
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value) VALUES
    (test_dict_id, key1_id, val1_id),
    (test_dict_id, key2_id, val2_id);
    
    -- Call len function
    SELECT public.py_builtin_len(test_dict_id) INTO result_id;
    
    -- Get result value
    SELECT lo.long_value INTO result_value
    FROM public.py_long_object lo
    WHERE lo.ob_base = result_id;
    
    IF result_value != 2 THEN
        RAISE EXCEPTION 'FAIL: len({"a":1,"b":2}) returned %, expected 2', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ len({"a":1,"b":2}) = 2';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 7: len() error handling - unsupported type
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: Testing len() error handling (unsupported type)...';
    test_count := test_count + 1;
    
    -- Create an int object (doesn't support len)
    test_int_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_int_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_int_id, 42);
    
    -- Try to call len on int (should fail)
    error_occurred := FALSE;
    BEGIN
        SELECT public.py_builtin_len(test_int_id) INTO result_id;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: len(42) should raise TypeError, but it did not';
    END IF;
    
    IF error_message NOT LIKE '%TypeError%' AND error_message NOT LIKE '%has no len()%' THEN
        RAISE EXCEPTION 'FAIL: len(42) raised error but message is incorrect: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ len(42) correctly raises TypeError';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 8: len() via __builtins__ lookup (CPython-style invocation)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: Testing len() via __builtins__ lookup...';
    test_count := test_count + 1;
    
    -- Get __builtins__ module dict
    SELECT md_dict INTO builtins_dict_id
    FROM public.py_module_object
    WHERE ob_base = ID_BUILTINS_MODULE;
    
    IF builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ module dict not found';
    END IF;
    
    -- Find "len" string object in __builtins__ dict
    SELECT me_value INTO len_function_id
    FROM public.py_dict_entry de
    WHERE de.dict_id = builtins_dict_id
    AND de.me_key IN (
        SELECT ob_base FROM public.py_unicode_object WHERE str_value = 'len'
    );
    
    IF len_function_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: len function not found in __builtins__ dict';
    END IF;
    
    -- Verify it's the correct len function
    IF len_function_id != ID_LEN_FUNCTION THEN
        RAISE EXCEPTION 'FAIL: Found function ID % does not match expected len function ID %', len_function_id, ID_LEN_FUNCTION;
    END IF;
    
    -- Get m_ml_meth (function identifier) from len function object
    -- regproc type stores function identifier, convert to text for dynamic call
    SELECT m_ml_meth::text INTO len_ml_meth
    FROM public.py_cfunction_object
    WHERE ob_base = len_function_id;
    
    IF len_ml_meth IS NULL OR len_ml_meth != 'py_builtin_len' THEN
        RAISE EXCEPTION 'FAIL: len function m_ml_meth is "%", expected "py_builtin_len"', len_ml_meth;
    END IF;
    
    -- Create a test string object
    test_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (test_str_id, 'world');
    
    -- Call len function dynamically using m_ml_meth
    -- This simulates CPython's function call mechanism
    -- regproc is converted to text for use in format()
    EXECUTE format('SELECT %I($1)', len_ml_meth) USING test_str_id INTO result_id;
    
    -- Verify result
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: len("world") via __builtins__ lookup returned NULL';
    END IF;
    
    -- Get result value
    SELECT lo.long_value INTO result_value
    FROM public.py_long_object lo
    WHERE lo.ob_base = result_id;
    
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL: len("world") via __builtins__ lookup returned %, expected 5', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ len("world") via __builtins__ lookup = 5';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 9: tp_dict __len__ system - py_object_size() function
    -- ========================================================================
    RAISE NOTICE 'Test 9: Testing py_object_size() function (tp_dict __len__ lookup)...';
    test_count := test_count + 1;
    
    -- Test py_object_size on string
    SELECT public.py_object_size(test_str_id) INTO result_value;
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL: py_object_size("hello") returned %, expected 5', result_value;
    END IF;
    
    -- Test py_object_size on list
    SELECT public.py_object_size(test_list_id) INTO result_value;
    IF result_value != 3 THEN
        RAISE EXCEPTION 'FAIL: py_object_size([1,2,3]) returned %, expected 3', result_value;
    END IF;
    
    -- Test py_object_size on dict
    SELECT public.py_object_size(test_dict_id) INTO result_value;
    IF result_value != 2 THEN
        RAISE EXCEPTION 'FAIL: py_object_size({"a":1,"b":2}) returned %, expected 2', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ py_object_size() works correctly via tp_dict __len__ lookup';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 10: __len__ method registration in tp_dict verification
    -- ========================================================================
    RAISE NOTICE 'Test 10: Testing __len__ method registration in tp_dict...';
    test_count := test_count + 1;
    
    -- Check that __len__ methods are registered in tp_dict
    DECLARE
        str_tp_dict_id UUID;
        list_tp_dict_id UUID;
        tuple_tp_dict_id UUID;
        dict_tp_dict_id UUID;
        len_name_str_id UUID;
        str_len_method_id UUID;
        list_len_method_id UUID;
        tuple_len_method_id UUID;
        dict_len_method_id UUID;
    BEGIN
        -- Get tp_dict IDs
        SELECT tp_dict INTO str_tp_dict_id FROM public.py_type_object WHERE ob_base = ID_STR_TYPE;
        SELECT tp_dict INTO list_tp_dict_id FROM public.py_type_object WHERE ob_base = ID_LIST_TYPE;
        SELECT tp_dict INTO tuple_tp_dict_id FROM public.py_type_object WHERE ob_base = ID_TUPLE_TYPE;
        SELECT tp_dict INTO dict_tp_dict_id FROM public.py_type_object WHERE ob_base = ID_DICT_TYPE;
        
        -- Find "__len__" string object
        SELECT ob_base INTO len_name_str_id
        FROM public.py_unicode_object
        WHERE str_value = '__len__'
        LIMIT 1;
        
        IF len_name_str_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: "__len__" string object not found';
        END IF;
        
        -- Check str.__len__
        SELECT me_value INTO str_len_method_id
        FROM public.py_dict_entry
        WHERE dict_id = str_tp_dict_id AND me_key = len_name_str_id;
        
        IF str_len_method_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: str type does not have __len__ in tp_dict';
        END IF;
        
        -- Check list.__len__
        SELECT me_value INTO list_len_method_id
        FROM public.py_dict_entry
        WHERE dict_id = list_tp_dict_id AND me_key = len_name_str_id;
        
        IF list_len_method_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: list type does not have __len__ in tp_dict';
        END IF;
        
        -- Check tuple.__len__
        SELECT me_value INTO tuple_len_method_id
        FROM public.py_dict_entry
        WHERE dict_id = tuple_tp_dict_id AND me_key = len_name_str_id;
        
        IF tuple_len_method_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: tuple type does not have __len__ in tp_dict';
        END IF;
        
        -- Check dict.__len__
        SELECT me_value INTO dict_len_method_id
        FROM public.py_dict_entry
        WHERE dict_id = dict_tp_dict_id AND me_key = len_name_str_id;
        
        IF dict_len_method_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: dict type does not have __len__ in tp_dict';
        END IF;
    END;
    
    RAISE NOTICE '  ✓ __len__ methods are correctly registered in tp_dict for all builtin types';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test Summary
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total tests: %', test_count;
    RAISE NOTICE 'Passed: %', pass_count;
    RAISE NOTICE 'Failed: %', fail_count;
    RAISE NOTICE '';
    
    IF fail_count = 0 THEN
        RAISE NOTICE '✓ All tests passed! Builtin functions work correctly.';
    ELSE
        RAISE EXCEPTION '✗ % test(s) failed. Builtin function integration test failed.', fail_count;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Test Failed';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Error: %', SQLERRM;
        RAISE NOTICE '';
        RAISE NOTICE 'Tests completed: %', test_count;
        RAISE NOTICE 'Passed: %', pass_count;
        RAISE NOTICE 'Failed: %', fail_count;
        RAISE;
END $$;
