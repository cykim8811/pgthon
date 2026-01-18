-- =====================================================
-- Test 01: Python Object Model
-- Description: Test core object tables and type system
-- Dependencies: Migrations 01-03 (object_model, bootstrap, singletons)
-- =====================================================

DO $$
DECLARE
    -- Fixed Type IDs
    ID_OBJ_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_TYP_TYPE uuid := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    ID_LST_TYPE uuid := '00000000-0000-4000-a000-000000000005';
    ID_DCT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
    ID_TUP_TYPE uuid := '00000000-0000-4000-a000-000000000007';
    ID_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000008';
    ID_NONE_TYPE uuid := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE uuid := '00000000-0000-4000-a000-000000000010';
    
    -- Singletons
    ID_NONE_OBJ uuid := '00000000-0000-4000-b000-000000000001';
    ID_TRUE_OBJ uuid := '00000000-0000-4000-b000-000000000002';
    ID_FALSE_OBJ uuid := '00000000-0000-4000-b000-000000000003';
    
    v_type_name text;
    v_count integer;
    v_true_val bigint;
    v_false_val bigint;
BEGIN
    -------------------------------------------------------
    -- 1. Test Core Types Exist
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Core Type System ===';
    
    -- Count types (should be 13: object, type, str, int, list, dict, tuple, function, NoneType, bool, code, builtin_function_or_method, method)
    SELECT COUNT(*) INTO v_count FROM public.py_type_object;
    PERFORM public.test_assert(v_count >= 13, format('Expected at least 13 types, found %s', v_count));
    
    -- Verify key type names
    SELECT tp_name INTO v_type_name FROM public.py_type_object WHERE id = ID_OBJ_TYPE;
    PERFORM public.test_assert_eq_str(v_type_name, 'object', 'object type name');
    
    SELECT tp_name INTO v_type_name FROM public.py_type_object WHERE id = ID_TYP_TYPE;
    PERFORM public.test_assert_eq_str(v_type_name, 'type', 'type type name');
    
    SELECT tp_name INTO v_type_name FROM public.py_type_object WHERE id = ID_STR_TYPE;
    PERFORM public.test_assert_eq_str(v_type_name, 'str', 'str type name');
    
    SELECT tp_name INTO v_type_name FROM public.py_type_object WHERE id = ID_INT_TYPE;
    PERFORM public.test_assert_eq_str(v_type_name, 'int', 'int type name');
    
    SELECT tp_name INTO v_type_name FROM public.py_type_object WHERE id = ID_LST_TYPE;
    PERFORM public.test_assert_eq_str(v_type_name, 'list', 'list type name');
    
    SELECT tp_name INTO v_type_name FROM public.py_type_object WHERE id = ID_DCT_TYPE;
    PERFORM public.test_assert_eq_str(v_type_name, 'dict', 'dict type name');
    
    -------------------------------------------------------
    -- 2. Test Singletons
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Python Singletons ===';
    
    -- None exists
    SELECT COUNT(*) INTO v_count FROM public.py_object WHERE id = ID_NONE_OBJ;
    PERFORM public.test_assert(v_count = 1, 'None singleton exists');
    
    -- True exists and has value 1
    SELECT long_value INTO v_true_val FROM public.py_long_object WHERE ob_base = ID_TRUE_OBJ;
    PERFORM public.test_assert_eq_int(v_true_val, 1, 'True has value 1');
    
    -- False exists and has value 0
    SELECT long_value INTO v_false_val FROM public.py_long_object WHERE ob_base = ID_FALSE_OBJ;
    PERFORM public.test_assert_eq_int(v_false_val, 0, 'False has value 0');
    
    -------------------------------------------------------
    -- 3. Test Type Hierarchy
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Type Hierarchy ===';
    
    -- bool inherits from int
    DECLARE
        v_bool_bases uuid;
        v_int_base uuid;
        v_bases_tuple uuid[];
    BEGIN
        SELECT tp_bases INTO v_bool_bases FROM public.py_type_object WHERE id = ID_BOOL_TYPE;
        PERFORM public.test_assert_not_null(v_bool_bases, 'bool has tp_bases');
        
        SELECT ob_item INTO v_bases_tuple FROM public.py_tuple_object WHERE ob_base = v_bool_bases;
        PERFORM public.test_assert(array_length(v_bases_tuple, 1) = 1, 'bool has exactly 1 base');
        
        -- Get int type's base object
        SELECT ob_base INTO v_int_base FROM public.py_type_object WHERE id = ID_INT_TYPE;
        PERFORM public.test_assert(v_bases_tuple[1] = v_int_base, 'bool inherits from int');
    END;
    
    RAISE NOTICE E'\n=== All Object Model Tests Passed! ===\n';
END $$;
