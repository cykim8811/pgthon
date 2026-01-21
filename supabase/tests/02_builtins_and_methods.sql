-- =====================================================
-- Test 02: Built-ins and Type Methods
-- Description: Test __builtins__ dict and type method registration
-- Dependencies: Migrations 04-06 (builtin_functions, builtins_dict, type_methods)
-- =====================================================

DO $$
DECLARE
    ID_DCT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    ID_LST_TYPE uuid := '00000000-0000-4000-a000-000000000005';
    
    ID_DICT_BUILTINS uuid := '00000000-0000-4000-c000-000000000002';
    
    v_count integer;
    v_value_id uuid;
    v_dict_id uuid;
    v_method_id uuid;
BEGIN
    -------------------------------------------------------
    -- 1. Test __builtins__ Dictionary
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing __builtins__ Dictionary ===';
    
    -- __builtins__ dict exists
    SELECT COUNT(*) INTO v_count FROM public.py_dict_object WHERE id = ID_DICT_BUILTINS;
    PERFORM public.test_assert(v_count = 1, '__builtins__ dictionary exists');
    
    -- Check __builtins__ has entries
    SELECT ma_used INTO v_count FROM public.py_dict_object WHERE id = ID_DICT_BUILTINS;
    PERFORM public.test_assert(v_count > 0, format('__builtins__ has %s entries', v_count));
    
    -- Verify specific built-ins exist
    
    -- Get Builtins Base ID
    DECLARE
        v_builtins_base uuid;
    BEGIN
        SELECT ob_base INTO v_builtins_base FROM public.py_dict_object WHERE id = ID_DICT_BUILTINS;
    
        SELECT e.me_value INTO v_value_id
        FROM public.py_dict_entry e
        JOIN public.py_unicode_object u ON u.ob_base = e.me_key
        WHERE e.dict_id = v_builtins_base AND u.str_value = 'int'
        LIMIT 1;
        PERFORM public.test_assert_not_null(v_value_id, 'int is in __builtins__');
        
        SELECT e.me_value INTO v_value_id
        FROM public.py_dict_entry e
        JOIN public.py_unicode_object u ON u.ob_base = e.me_key
        WHERE e.dict_id = v_builtins_base AND u.str_value = 'str'
        LIMIT 1;
        PERFORM public.test_assert_not_null(v_value_id, 'str is in __builtins__');
        
        SELECT e.me_value INTO v_value_id
        FROM public.py_dict_entry e
        JOIN public.py_unicode_object u ON u.ob_base = e.me_key
        WHERE e.dict_id = v_builtins_base AND u.str_value = 'list'
        LIMIT 1;
        PERFORM public.test_assert_not_null(v_value_id, 'list is in __builtins__');
    END;
    
    -------------------------------------------------------
    -- 2. Test Type Methods Registration
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Type Methods ===';
    
    -- str has methods
    SELECT tp_dict INTO v_dict_id FROM public.py_type_object WHERE id = ID_STR_TYPE;
    PERFORM public.test_assert_not_null(v_dict_id, 'str has tp_dict');
    
    SELECT ma_used INTO v_count FROM public.py_dict_object WHERE id = v_dict_id;
    PERFORM public.test_assert(v_count > 0, format('str has %s methods', v_count));
    
    -- Check for specific str methods
    SELECT e.me_value INTO v_method_id
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = v_dict_id AND u.str_value = 'upper'
    LIMIT 1;
    PERFORM public.test_assert_not_null(v_method_id, 'str has upper() method');
    
    -- int has methods
    SELECT tp_dict INTO v_dict_id FROM public.py_type_object WHERE id = ID_INT_TYPE;
    SELECT ma_used INTO v_count FROM public.py_dict_object WHERE id = v_dict_id;
    PERFORM public.test_assert(v_count > 0, format('int has %s methods', v_count));
    
    -- Check for __add__ magic method
    SELECT e.me_value INTO v_method_id
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = v_dict_id AND u.str_value = '__add__'
    LIMIT 1;
    PERFORM public.test_assert_not_null(v_method_id, 'int has __add__() method');
    
    -- list has methods
    SELECT tp_dict INTO v_dict_id FROM public.py_type_object WHERE id = ID_LST_TYPE;
    SELECT ma_used INTO v_count FROM public.py_dict_object WHERE id = v_dict_id;
    PERFORM public.test_assert(v_count > 0, format('list has %s methods', v_count));
    
    -- Check for append method
    SELECT e.me_value INTO v_method_id
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = v_dict_id AND u.str_value = 'append'
    LIMIT 1;
    PERFORM public.test_assert_not_null(v_method_id, 'list has append() method');
    
    RAISE NOTICE E'\n=== All Built-in Tests Passed! ===\n';
END $$;
