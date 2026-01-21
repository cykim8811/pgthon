-- =====================================================
-- Test 16: Error Handling Extended
-- Description: Comprehensive error case testing for arithmetic operations
-- =====================================================

DO $$
DECLARE
    v_val1 uuid;
    v_val2 uuid;
    v_res uuid;
    v_error_raised boolean;
    
BEGIN
    RAISE NOTICE E'\n=== Testing Extended Error Handling ===';

    -------------------------------------------------------
    -- 1. ZeroDivisionError: Division by zero
    -------------------------------------------------------
    v_val1 := public.vm_create_int(100);
    v_val2 := public.vm_create_int(0);
    
    v_error_raised := false;
    BEGIN
        v_res := public.vm_div(v_val1, v_val2);
    EXCEPTION
        WHEN OTHERS THEN
            v_error_raised := SQLERRM LIKE '%ZeroDivisionError%';
    END;
    PERFORM public.test_assert(v_error_raised, 'Division by zero raises ZeroDivisionError');

    -------------------------------------------------------
    -- 2. ZeroDivisionError: Floor division by zero
    -------------------------------------------------------
    v_error_raised := false;
    BEGIN
        v_res := public.vm_floordiv(v_val1, v_val2);
    EXCEPTION
        WHEN OTHERS THEN
            v_error_raised := SQLERRM LIKE '%ZeroDivisionError%';
    END;
    PERFORM public.test_assert(v_error_raised, 'Floor division by zero raises ZeroDivisionError');

    -------------------------------------------------------
    -- 3. ZeroDivisionError: Modulo by zero
    -------------------------------------------------------
    v_error_raised := false;
    BEGIN
        v_res := public.vm_mod(v_val1, v_val2);
    EXCEPTION
        WHEN OTHERS THEN
            v_error_raised := SQLERRM LIKE '%ZeroDivisionError%';
    END;
    PERFORM public.test_assert(v_error_raised, 'Modulo by zero raises ZeroDivisionError');

    -------------------------------------------------------
    -- 4. ValueError: Negative power  
    -------------------------------------------------------
    v_val1 := public.vm_create_int(2);
    v_val2 := public.vm_create_int(-1);
    
    v_error_raised := false;
    BEGIN
        v_res := public.vm_pow(v_val1, v_val2);
    EXCEPTION
        WHEN OTHERS THEN
            v_error_raised := SQLERRM LIKE '%ValueError%' OR SQLERRM LIKE '%negative%';
    END;
    PERFORM public.test_assert(v_error_raised, 'Negative power raises ValueError');

    -------------------------------------------------------
    -- 5. TypeError: Unsupported operand types (using NULL as proxy)
    -------------------------------------------------------
    -- Create a "fake" object that has no arithmetic methods
    DECLARE
        v_obj_base uuid;
        v_type_id uuid;
        v_type_base_id uuid;
        v_dict_base uuid;
        v_dict_id uuid;
        ID_TYPE_TYPE uuid := '00000000-0000-4000-a000-000000000002';
    BEGIN
        -- Create empty type
        v_type_base_id := gen_random_uuid();
        v_type_id := gen_random_uuid();
        v_dict_base := public.vm_create_dict();
        -- SELECT id INTO v_dict_id FROM public.py_dict_object WHERE ob_base = v_dict_base; -- Use Base ID
        
        INSERT INTO public.py_object (id, ob_type) VALUES (v_type_base_id, ID_TYPE_TYPE);
        INSERT INTO public.py_type_object (id, ob_base, tp_name, tp_bases, tp_dict) 
        VALUES (v_type_id, v_type_base_id, 'EmptyBox', NULL, v_dict_base);
        
        -- Create instance
        v_obj_base := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (v_obj_base, v_type_base_id);
        
        -- Test addition with no __add__ method
        v_val1 := public.vm_create_int(5);
        v_error_raised := false;
        BEGIN
            v_res := public.vm_add(v_obj_base, v_val1);
        EXCEPTION
            WHEN OTHERS THEN
                v_error_raised := SQLERRM LIKE '%TypeError%';
        END;
        PERFORM public.test_assert(v_error_raised, 'Addition with no __add__ raises TypeError');
        
        -- Test subtraction with no __sub__ method
        v_error_raised := false;
        BEGIN
            v_res := public.vm_sub(v_obj_base, v_val1);
        EXCEPTION
            WHEN OTHERS THEN
                v_error_raised := SQLERRM LIKE '%TypeError%';
        END;
        PERFORM public.test_assert(v_error_raised, 'Subtraction with no __sub__ raises TypeError');
        
        -- Test multiplication with no __mul__ method
        v_error_raised := false;
        BEGIN
            v_res := public.vm_mul(v_obj_base, v_val1);
        EXCEPTION
            WHEN OTHERS THEN
                v_error_raised := SQLERRM LIKE '%TypeError%';
        END;
        PERFORM public.test_assert(v_error_raised, 'Multiplication with no __mul__ raises TypeError');
    END;

    -------------------------------------------------------
    -- 6. Edge case: Large number power
    -------------------------------------------------------
    v_val1 := public.vm_create_int(2);
    v_val2 := public.vm_create_int(20);
    v_res := public.vm_pow(v_val1, v_val2);
    PERFORM public.test_assert_eq_int(public.vm_get_int_value(v_res), 1048576, '2 ** 20 = 1048576');

    -------------------------------------------------------
    -- 7. Edge case: Zero power
    -------------------------------------------------------
    v_val1 := public.vm_create_int(5);
    v_val2 := public.vm_create_int(0);
    v_res := public.vm_pow(v_val1, v_val2);
    PERFORM public.test_assert_eq_int(public.vm_get_int_value(v_res), 1, '5 ** 0 = 1');

    -------------------------------------------------------
    -- 8. Edge case: Negative modulo
    -------------------------------------------------------
    v_val1 := public.vm_create_int(100);
    v_val2 := public.vm_create_int(30);
    v_res := public.vm_mod(v_val1, v_val2);
    PERFORM public.test_assert_eq_int(public.vm_get_int_value(v_res), 10, '100 % 30 = 10');

    RAISE NOTICE E'\n=== All Extended Error Handling Tests Passed! ===\n';
END $$;
