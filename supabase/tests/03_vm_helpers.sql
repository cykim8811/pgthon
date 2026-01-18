-- =====================================================
-- Test 03: VM Object Creation and Helpers
-- Description: Test VM helper functions for object creation
-- Dependencies: Migrations 07-08 (vm_object_protocol, vm_helpers)
-- =====================================================

DO $$
DECLARE
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    ID_NONE_OBJ uuid := '00000000-0000-4000-b000-000000000001';
    ID_TRUE_OBJ uuid := '00000000-0000-4000-b000-000000000002';
    ID_FALSE_OBJ uuid := '00000000-0000-4000-b000-000000000003';
    
    v_int_id uuid;
    v_str_id uuid;
    v_none_id uuid;
    v_type_id uuid;
    v_val bigint;
    v_str_val text;
    v_result boolean;
BEGIN
    -------------------------------------------------------
    -- 1. Test Object Creation
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Object Creation ===';
    
    -- Create integer
    v_int_id := public.vm_create_int(42);
    PERFORM public.test_assert_not_null(v_int_id, 'vm_create_int returns object');
    
    v_type_id := public.vm_get_type(v_int_id);
    PERFORM public.test_assert(v_type_id = ID_INT_TYPE, 'Created object has int type');
    
    v_val := public.vm_get_int_value(v_int_id);
    PERFORM public.test_assert_eq_int(v_val, 42, 'Integer value is 42');
    
    -- Create string
    v_str_id := public.vm_create_str('hello world');
    PERFORM public.test_assert_not_null(v_str_id, 'vm_create_str returns object');
    
    v_type_id := public.vm_get_type(v_str_id);
    PERFORM public.test_assert(v_type_id = ID_STR_TYPE, 'Created object has str type');
    
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_str_id;
    PERFORM public.test_assert_eq_str(v_str_val, 'hello world', 'String value correct');
    
    -- Get None
    v_none_id := public.vm_get_none();
    PERFORM public.test_assert(v_none_id = ID_NONE_OBJ, 'vm_get_none returns None singleton');
    
    -------------------------------------------------------
    -- 2. Test Assembler Const Creation
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Assembler Const Creation ===';
    
    -- Integer from string
    v_int_id := public.vm_assembler_get_or_create_const('123');
    v_type_id := public.vm_get_type(v_int_id);
    PERFORM public.test_assert(v_type_id = ID_INT_TYPE, 'Assembler creates int from "123"');
    
    v_val := public.vm_get_int_value(v_int_id);
    PERFORM public.test_assert_eq_int(v_val, 123, 'Assembler int value is 123');
    
    -- String from non-numeric text
    v_str_id := public.vm_assembler_get_or_create_const('hello');
    v_type_id := public.vm_get_type(v_str_id);
    PERFORM public.test_assert(v_type_id = ID_STR_TYPE, 'Assembler creates str from "hello"');
    
    -------------------------------------------------------
    -- 3. Test Truth Value Testing
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Truth Value Testing ===';
    
    -- True is true
    v_result := public.vm_is_true(ID_TRUE_OBJ);
    PERFORM public.test_assert(v_result = true, 'True is truthy');
    
    -- False is false
    v_result := public.vm_is_true(ID_FALSE_OBJ);
    PERFORM public.test_assert(v_result = false, 'False is falsy');
    
    -- None is false
    v_result := public.vm_is_true(ID_NONE_OBJ);
    PERFORM public.test_assert(v_result = false, 'None is falsy');
    
    -- 0 is false
    v_int_id := public.vm_create_int(0);
    v_result := public.vm_is_true(v_int_id);
    PERFORM public.test_assert(v_result = false, '0 is falsy');
    
    -- Non-zero is true
    v_int_id := public.vm_create_int(42);
    v_result := public.vm_is_true(v_int_id);
    PERFORM public.test_assert(v_result = true, '42 is truthy');
    
    -------------------------------------------------------
    -- 4. Test Comparison Operations
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Comparison Operations ===';
    
    DECLARE
        v_left uuid := public.vm_create_int(10);
        v_right uuid := public.vm_create_int(20);
        v_res_id uuid;
        v_res_bool boolean;
    BEGIN
        -- 10 < 20 (op_idx 0)
        v_res_id := public.vm_compare(v_left, v_right, 0);
        v_res_bool := public.vm_is_true(v_res_id);
        PERFORM public.test_assert(v_res_bool = true, '10 < 20 is True');
        
        -- 10 > 20 (op_idx 4)
        v_res_id := public.vm_compare(v_left, v_right, 4);
        v_res_bool := public.vm_is_true(v_res_id);
        PERFORM public.test_assert(v_res_bool = false, '10 > 20 is False');
        
        -- 10 == 10 (op_idx 2)
        v_res_id := public.vm_compare(v_left, v_left, 2);
        v_res_bool := public.vm_is_true(v_res_id);
        PERFORM public.test_assert(v_res_bool = true, '10 == 10 is True');
        
        -- 10 != 20 (op_idx 3)
        v_res_id := public.vm_compare(v_left, v_right, 3);
        v_res_bool := public.vm_is_true(v_res_id);
        PERFORM public.test_assert(v_res_bool = true, '10 != 20 is True');
    END;
    
    RAISE NOTICE E'\n=== All VM Helper Tests Passed! ===\n';
END $$;
