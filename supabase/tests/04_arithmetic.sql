-- =====================================================
-- Test 04: VM Arithmetic and Basic Operations
-- Description: Test arithmetic operations and native dispatch
-- Dependencies: Migrations 09 (vm_native_dispatch)
-- =====================================================

DO $$
DECLARE
    v_left uuid;
    v_right uuid;
    v_result uuid;
    v_val bigint;
    v_str_val text;
BEGIN
    -------------------------------------------------------
    -- 1. Test Integer Addition
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Integer Addition ===';
    
    v_left := public.vm_create_int(10);
    v_right := public.vm_create_int(20);
    v_result := public.vm_add(v_left, v_right);
    
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 30, '10 + 20 = 30');
    
    -- Larger numbers
    v_left := public.vm_create_int(100);
    v_right := public.vm_create_int(234);
    v_result := public.vm_add(v_left, v_right);
    v_val := public.vm_get_int_value(v_result);
    PERFORM public.test_assert_eq_int(v_val, 334, '100 + 234 = 334');
    
    -------------------------------------------------------
    -- 2. Test String Concatenation
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing String Concatenation ===';
    
    v_left := public.vm_create_str('Hello');
    v_right := public.vm_create_str(' World');
    v_result := public.vm_add(v_left, v_right);
    
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_result;
    PERFORM public.test_assert_eq_str(v_str_val, 'Hello World', '"Hello" + " World" = "Hello World"');
    
    -------------------------------------------------------
    -- 3. Test Native Dispatch for __add__
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Native Dispatch ===';
    
    DECLARE
        v_args uuid[];
        v_res uuid;
        v_res_val bigint;
    BEGIN
        v_args := ARRAY[public.vm_create_int(15), public.vm_create_int(27)];
        v_res := public.vm_native_dispatch('__add__', v_args);
        
        v_res_val := public.vm_get_int_value(v_res);
        PERFORM public.test_assert_eq_int(v_res_val, 42, 'Native __add__(15, 27) = 42');
    END;
    
    -------------------------------------------------------
    -- 4. Test Other Arithmetic Operations
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Other Arithmetic Operations ===';
    
    DECLARE
        v_args uuid[];
        v_res uuid;
        v_res_val bigint;
    BEGIN
        -- Subtraction
        v_args := ARRAY[public.vm_create_int(50), public.vm_create_int(20)];
        v_res := public.vm_native_dispatch('__sub__', v_args);
        v_res_val := public.vm_get_int_value(v_res);
        PERFORM public.test_assert_eq_int(v_res_val, 30, '50 - 20 = 30');
        
        -- Multiplication
        v_args := ARRAY[public.vm_create_int(6), public.vm_create_int(7)];
        v_res := public.vm_native_dispatch('__mul__', v_args);
        v_res_val := public.vm_get_int_value(v_res);
        PERFORM public.test_assert_eq_int(v_res_val, 42, '6 * 7 = 42');
        
        -- Floor Division
        v_args := ARRAY[public.vm_create_int(100), public.vm_create_int(7)];
        v_res := public.vm_native_dispatch('__floordiv__', v_args);
        v_res_val := public.vm_get_int_value(v_res);
        PERFORM public.test_assert_eq_int(v_res_val, 14, '100 // 7 = 14');
        
        -- Modulo
        v_args := ARRAY[public.vm_create_int(100), public.vm_create_int(7)];
        v_res := public.vm_native_dispatch('__mod__', v_args);
        v_res_val := public.vm_get_int_value(v_res);
        PERFORM public.test_assert_eq_int(v_res_val, 2, '100 % 7 = 2');
    END;
    
    RAISE NOTICE E'\n=== All Arithmetic Tests Passed! ===\n';
END $$;
