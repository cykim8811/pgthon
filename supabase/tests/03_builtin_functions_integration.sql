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
    ID_FLOAT_TYPE UUID := '00000000-0000-4000-a000-000000000009';
    
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
    ID_ABS_FUNCTION UUID := '00000000-0000-4000-b000-000000000004';
    builtins_dict_id UUID;
    len_function_id UUID;
    len_ml_meth TEXT;
    len_name_str_id UUID;
    abs_function_id UUID;
    abs_ml_meth TEXT;
    abs_name_str_id UUID;
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
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash) VALUES
    (test_dict_id, key1_id, val1_id, public.py_object_hash(key1_id)),
    (test_dict_id, key2_id, val2_id, public.py_object_hash(key2_id));
    
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
    
    -- Look up "len" in __builtins__ via hash-based dict API (CPython semantics)
    SELECT public.py_dict_get_item(builtins_dict_id, u.ob_base) INTO len_function_id
    FROM public.py_unicode_object u
    WHERE u.str_value = 'len'
    LIMIT 1;
    
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
    -- Test 9: Method slot system - py_object_size() function
    -- ========================================================================
    RAISE NOTICE 'Test 9: Testing py_object_size() function (method slot system)...';
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
    
    RAISE NOTICE '  ✓ py_object_size() works correctly via method slots';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 10: Method slot registration verification
    -- ========================================================================
    RAISE NOTICE 'Test 10: Testing method slot registration...';
    test_count := test_count + 1;
    
    -- Check that method slots are registered correctly (CPython structure fidelity)
    -- This verifies the pointer chain: type->tp_as_sequence->sq_length
    DECLARE
        str_sequence_methods_id UUID;
        list_sequence_methods_id UUID;
        tuple_sequence_methods_id UUID;
        dict_mapping_methods_id UUID;
        str_sq_length regproc;
        list_sq_length regproc;
        tuple_sq_length regproc;
        dict_mp_length regproc;
    BEGIN
        -- Check str type: type->tp_as_sequence->sq_length
        SELECT tp_as_sequence INTO str_sequence_methods_id
        FROM public.py_type_object
        WHERE ob_base = ID_STR_TYPE;
        
        IF str_sequence_methods_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: str type does not have tp_as_sequence pointer';
        END IF;
        
        SELECT sq_length INTO str_sq_length
        FROM public.py_sequence_methods
        WHERE id = str_sequence_methods_id;
        
        IF str_sq_length IS NULL OR str_sq_length::text != 'py_unicode_sq_length' THEN
            RAISE EXCEPTION 'FAIL: str type sequence methods do not have sq_length registered correctly';
        END IF;
        
        -- Check list type: type->tp_as_sequence->sq_length
        SELECT tp_as_sequence INTO list_sequence_methods_id
        FROM public.py_type_object
        WHERE ob_base = ID_LIST_TYPE;
        
        IF list_sequence_methods_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: list type does not have tp_as_sequence pointer';
        END IF;
        
        SELECT sq_length INTO list_sq_length
        FROM public.py_sequence_methods
        WHERE id = list_sequence_methods_id;
        
        IF list_sq_length IS NULL OR list_sq_length::text != 'py_list_sq_length' THEN
            RAISE EXCEPTION 'FAIL: list type sequence methods do not have sq_length registered correctly';
        END IF;
        
        -- Check tuple type: type->tp_as_sequence->sq_length
        SELECT tp_as_sequence INTO tuple_sequence_methods_id
        FROM public.py_type_object
        WHERE ob_base = ID_TUPLE_TYPE;
        
        IF tuple_sequence_methods_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: tuple type does not have tp_as_sequence pointer';
        END IF;
        
        SELECT sq_length INTO tuple_sq_length
        FROM public.py_sequence_methods
        WHERE id = tuple_sequence_methods_id;
        
        IF tuple_sq_length IS NULL OR tuple_sq_length::text != 'py_tuple_sq_length' THEN
            RAISE EXCEPTION 'FAIL: tuple type sequence methods do not have sq_length registered correctly';
        END IF;
        
        -- Check dict type: type->tp_as_mapping->mp_length
        SELECT tp_as_mapping INTO dict_mapping_methods_id
        FROM public.py_type_object
        WHERE ob_base = ID_DICT_TYPE;
        
        IF dict_mapping_methods_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: dict type does not have tp_as_mapping pointer';
        END IF;
        
        SELECT mp_length INTO dict_mp_length
        FROM public.py_mapping_methods
        WHERE id = dict_mapping_methods_id;
        
        IF dict_mp_length IS NULL OR dict_mp_length::text != 'py_dict_mp_length' THEN
            RAISE EXCEPTION 'FAIL: dict type mapping methods do not have mp_length registered correctly';
        END IF;
    END;
    
    RAISE NOTICE '  ✓ Method slots are correctly registered for all builtin types';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 11: Type-specific length calculation functions (direct calls)
    -- ========================================================================
    RAISE NOTICE 'Test 11: Testing type-specific length calculation functions...';
    test_count := test_count + 1;
    
    -- Test py_unicode_sq_length directly
    SELECT public.py_unicode_sq_length(test_str_id) INTO result_value;
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL: py_unicode_sq_length("hello") returned %, expected 5', result_value;
    END IF;
    
    -- Test py_list_sq_length directly
    SELECT public.py_list_sq_length(test_list_id) INTO result_value;
    IF result_value != 3 THEN
        RAISE EXCEPTION 'FAIL: py_list_sq_length([1,2,3]) returned %, expected 3', result_value;
    END IF;
    
    -- Test py_tuple_sq_length directly
    SELECT public.py_tuple_sq_length(test_tuple_id) INTO result_value;
    IF result_value != 2 THEN
        RAISE EXCEPTION 'FAIL: py_tuple_sq_length((1,2)) returned %, expected 2', result_value;
    END IF;
    
    -- Test py_dict_mp_length directly
    SELECT public.py_dict_mp_length(test_dict_id) INTO result_value;
    IF result_value != 2 THEN
        RAISE EXCEPTION 'FAIL: py_dict_mp_length({"a":1,"b":2}) returned %, expected 2', result_value;
    END IF;
    
    -- Test empty list
    SELECT public.py_list_sq_length(test_empty_list_id) INTO result_value;
    IF result_value != 0 THEN
        RAISE EXCEPTION 'FAIL: py_list_sq_length([]) returned %, expected 0', result_value;
    END IF;
    
    -- Test empty string
    SELECT public.py_unicode_sq_length(test_empty_str_id) INTO result_value;
    IF result_value != 0 THEN
        RAISE EXCEPTION 'FAIL: py_unicode_sq_length("") returned %, expected 0', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ All type-specific length functions work correctly';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 12: PyObject_Size pointer chain traversal (CPython structure fidelity)
    -- ========================================================================
    RAISE NOTICE 'Test 12: Testing PyObject_Size pointer chain traversal...';
    test_count := test_count + 1;
    
    -- Test that PyObject_Size correctly follows the pointer chain
    -- type->tp_as_sequence->sq_length for sequences
    SELECT public.py_object_size(test_str_id) INTO result_value;
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL: PyObject_Size pointer chain failed for str';
    END IF;
    
    SELECT public.py_object_size(test_list_id) INTO result_value;
    IF result_value != 3 THEN
        RAISE EXCEPTION 'FAIL: PyObject_Size pointer chain failed for list';
    END IF;
    
    -- Test that PyObject_Size correctly follows the pointer chain
    -- type->tp_as_mapping->mp_length for mappings
    SELECT public.py_object_size(test_dict_id) INTO result_value;
    IF result_value != 2 THEN
        RAISE EXCEPTION 'FAIL: PyObject_Size pointer chain failed for dict';
    END IF;
    
    RAISE NOTICE '  ✓ PyObject_Size correctly traverses pointer chain';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 13: PyObject_Size error handling (unsupported types)
    -- ========================================================================
    RAISE NOTICE 'Test 13: Testing PyObject_Size error handling...';
    test_count := test_count + 1;
    
    -- Test that PyObject_Size raises TypeError for types without length
    error_occurred := FALSE;
    BEGIN
        SELECT public.py_object_size(test_int_id) INTO result_value;
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: PyObject_Size(42) should raise TypeError, but it did not';
    END IF;
    
    IF error_message NOT LIKE '%TypeError%' AND error_message NOT LIKE '%has no len()%' THEN
        RAISE EXCEPTION 'FAIL: PyObject_Size(42) raised error but message is incorrect: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ PyObject_Size correctly raises TypeError for unsupported types';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 14: Method slot structure integrity (NULL pointer checks)
    -- ========================================================================
    RAISE NOTICE 'Test 14: Testing method slot structure integrity...';
    test_count := test_count + 1;
    
    -- Verify that types without sequence/mapping methods have NULL pointers
    -- (This matches CPython: if tp_as_sequence is NULL, it's not a sequence)
    DECLARE
        int_sequence_methods_id UUID;
        int_mapping_methods_id UUID;
        float_sequence_methods_id UUID;
    BEGIN
        -- int type should not have sequence or mapping methods
        SELECT tp_as_sequence, tp_as_mapping 
        INTO int_sequence_methods_id, int_mapping_methods_id
        FROM public.py_type_object
        WHERE ob_base = ID_INT_TYPE;
        
        IF int_sequence_methods_id IS NOT NULL THEN
            RAISE EXCEPTION 'FAIL: int type should not have tp_as_sequence pointer';
        END IF;
        
        IF int_mapping_methods_id IS NOT NULL THEN
            RAISE EXCEPTION 'FAIL: int type should not have tp_as_mapping pointer';
        END IF;
        
        -- float type should not have sequence or mapping methods
        DECLARE
            ID_FLOAT_TYPE UUID := '00000000-0000-4000-a000-000000000009';
            float_sequence_methods_id UUID;
            float_mapping_methods_id UUID;
        BEGIN
            SELECT tp_as_sequence, tp_as_mapping 
            INTO float_sequence_methods_id, float_mapping_methods_id
            FROM public.py_type_object
            WHERE ob_base = ID_FLOAT_TYPE;
            
            IF float_sequence_methods_id IS NOT NULL THEN
                RAISE EXCEPTION 'FAIL: float type should not have tp_as_sequence pointer';
            END IF;
            
            IF float_mapping_methods_id IS NOT NULL THEN
                RAISE EXCEPTION 'FAIL: float type should not have tp_as_mapping pointer';
            END IF;
        END;
    END;
    
    RAISE NOTICE '  ✓ Method slot structure integrity verified (NULL pointers correct)';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 15: len() function calls PyObject_Size (CPython compatibility)
    -- ========================================================================
    RAISE NOTICE 'Test 15: Testing len() function calls PyObject_Size...';
    test_count := test_count + 1;
    
    -- Verify that py_builtin_len calls py_object_size
    -- This is the CPython pattern: builtin_len() -> PyObject_Size()
    SELECT public.py_builtin_len(test_str_id) INTO result_id;
    SELECT long_value INTO result_value
    FROM public.py_long_object
    WHERE ob_base = result_id;
    
    IF result_value != 5 THEN
        RAISE EXCEPTION 'FAIL: len("hello") via py_builtin_len returned %, expected 5', result_value;
    END IF;
    
    -- Verify it works for all types
    SELECT public.py_builtin_len(test_list_id) INTO result_id;
    SELECT long_value INTO result_value
    FROM public.py_long_object
    WHERE ob_base = result_id;
    
    IF result_value != 3 THEN
        RAISE EXCEPTION 'FAIL: len([1,2,3]) via py_builtin_len returned %, expected 3', result_value;
    END IF;
    
    SELECT public.py_builtin_len(test_dict_id) INTO result_id;
    SELECT long_value INTO result_value
    FROM public.py_long_object
    WHERE ob_base = result_id;
    
    IF result_value != 2 THEN
        RAISE EXCEPTION 'FAIL: len({"a":1,"b":2}) via py_builtin_len returned %, expected 2', result_value;
    END IF;
    
    RAISE NOTICE '  ✓ len() function correctly calls PyObject_Size for all types';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 16: abs() on positive int
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 16: Testing abs() on positive int...';
    test_count := test_count + 1;
    
    -- Create test int: 42
    DECLARE
        test_int_id UUID;
        result_id UUID;
        result_value NUMERIC;
    BEGIN
        test_int_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (test_int_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_int_id, 42);
        
        -- Call abs function
        SELECT public.py_builtin_abs(test_int_id) INTO result_id;
        
        -- Verify result
        IF result_id IS NULL THEN
            RAISE EXCEPTION 'FAIL: abs(42) returned NULL';
        END IF;
        
        -- Get result value
        SELECT long_value INTO result_value
        FROM public.py_long_object
        WHERE ob_base = result_id;
        
        IF result_value != 42 THEN
            RAISE EXCEPTION 'FAIL: abs(42) returned %, expected 42', result_value;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ abs(42) = 42';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 17: abs() on negative int
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 17: Testing abs() on negative int...';
    test_count := test_count + 1;
    
    -- Create test int: -42
    DECLARE
        test_int_id UUID;
        result_id UUID;
        result_value NUMERIC;
    BEGIN
        test_int_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (test_int_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_int_id, -42);
        
        -- Call abs function
        SELECT public.py_builtin_abs(test_int_id) INTO result_id;
        
        -- Get result value
        SELECT long_value INTO result_value
        FROM public.py_long_object
        WHERE ob_base = result_id;
        
        IF result_value != 42 THEN
            RAISE EXCEPTION 'FAIL: abs(-42) returned %, expected 42', result_value;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ abs(-42) = 42';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 18: abs() on positive float
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 18: Testing abs() on positive float...';
    test_count := test_count + 1;
    
    -- Create test float: 3.14
    DECLARE
        test_float_id UUID;
        result_id UUID;
        result_value DOUBLE PRECISION;
    BEGIN
        test_float_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (test_float_id, ID_FLOAT_TYPE);
        INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (test_float_id, 3.14);
        
        -- Call abs function
        SELECT public.py_builtin_abs(test_float_id) INTO result_id;
        
        -- Get result value
        SELECT ob_fval INTO result_value
        FROM public.py_float_object
        WHERE ob_base = result_id;
        
        IF ABS(result_value - 3.14) > 0.0001 THEN
            RAISE EXCEPTION 'FAIL: abs(3.14) returned %, expected 3.14', result_value;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ abs(3.14) = 3.14';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 19: abs() on negative float
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 19: Testing abs() on negative float...';
    test_count := test_count + 1;
    
    -- Create test float: -3.14
    DECLARE
        test_float_id UUID;
        result_id UUID;
        result_value DOUBLE PRECISION;
    BEGIN
        test_float_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (test_float_id, ID_FLOAT_TYPE);
        INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (test_float_id, -3.14);
        
        -- Call abs function
        SELECT public.py_builtin_abs(test_float_id) INTO result_id;
        
        -- Get result value
        SELECT ob_fval INTO result_value
        FROM public.py_float_object
        WHERE ob_base = result_id;
        
        IF ABS(result_value - 3.14) > 0.0001 THEN
            RAISE EXCEPTION 'FAIL: abs(-3.14) returned %, expected 3.14', result_value;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ abs(-3.14) = 3.14';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 20: abs() raises TypeError for unsupported types
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 20: Testing abs() raises TypeError for unsupported types...';
    test_count := test_count + 1;
    
    -- Create test string (not a number)
    DECLARE
        test_str_id UUID;
        result_id UUID;
    BEGIN
        test_str_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (test_str_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (test_str_id, 'hello');
        
        -- Call abs function - should raise TypeError
        BEGIN
            SELECT public.py_builtin_abs(test_str_id) INTO result_id;
            RAISE EXCEPTION 'FAIL: abs() did not raise TypeError for string';
        EXCEPTION
            WHEN OTHERS THEN
                error_message := SQLERRM;
                IF error_message NOT LIKE 'TypeError: bad operand type for abs(): ''str''%' THEN
                    RAISE EXCEPTION 'FAIL: abs() raised wrong exception: %', error_message;
                END IF;
        END;
    END;
    
    RAISE NOTICE '  ✓ abs() correctly raises TypeError for unsupported types';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 21: abs function is registered in __builtins__
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 21: Testing abs function is registered in __builtins__...';
    test_count := test_count + 1;
    
    -- Get __builtins__ module dict
    SELECT md_dict INTO builtins_dict_id
    FROM public.py_module_object
    WHERE ob_base = ID_BUILTINS_MODULE;
    
    IF builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ module dict not found';
    END IF;
    
    -- Look up "abs" in __builtins__ via hash-based dict API (CPython semantics)
    SELECT public.py_dict_get_item(builtins_dict_id, u.ob_base) INTO abs_function_id
    FROM public.py_unicode_object u
    WHERE u.str_value = 'abs'
    LIMIT 1;
    
    IF abs_function_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: abs function not found in __builtins__ dict';
    END IF;
    
    -- Verify it's the correct abs function
    IF abs_function_id != ID_ABS_FUNCTION THEN
        RAISE EXCEPTION 'FAIL: Found function ID % does not match expected abs function ID %', abs_function_id, ID_ABS_FUNCTION;
    END IF;
    
    -- Get m_ml_meth (function identifier) from abs function object
    SELECT m_ml_meth::text INTO abs_ml_meth
    FROM public.py_cfunction_object
    WHERE ob_base = abs_function_id;
    
    IF abs_ml_meth IS NULL OR abs_ml_meth != 'py_builtin_abs' THEN
        RAISE EXCEPTION 'FAIL: abs function m_ml_meth is "%", expected "py_builtin_abs"', abs_ml_meth;
    END IF;
    
    RAISE NOTICE '  ✓ abs function is correctly registered in __builtins__';
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
