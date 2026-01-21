-- =====================================================
-- Test 15: Arithmetic Extended (Custom Methods)
-- Description: Comprehensive tests for all arithmetic operator custom methods
-- =====================================================

DO $$
DECLARE
    -- Type IDs
    v_type_id uuid;
    v_type_base_id uuid;
    v_dict_base uuid;
    v_dict_id uuid;
    
    -- Code objects
    v_div_code_id uuid;
    v_div_code_base uuid;
    v_floordiv_code_id uuid;
    v_floordiv_code_base uuid;
    v_mod_code_id uuid;
    v_mod_code_base uuid;
    v_pow_code_id uuid;
    v_pow_code_base uuid;
    
    -- Function objects
    v_div_func uuid;
    v_div_func_base uuid;
    v_floordiv_func uuid;
    v_floordiv_func_base uuid;
    v_mod_func uuid;
    v_mod_func_base uuid;
    v_pow_func uuid;
    v_pow_func_base uuid;
    
    -- Test objects
    v_obj_base uuid;
    v_val1 uuid;
    v_val2 uuid;
    v_res uuid;
    
    -- Constants
    ID_TYPE_TYPE uuid := '00000000-0000-4000-a000-000000000002';
    
BEGIN
    RAISE NOTICE E'\n=== Testing Extended Arithmetic Operations ===';

    -------------------------------------------------------
    -- 1. Create MathBox Type
    -------------------------------------------------------
    v_type_base_id := gen_random_uuid();
    v_type_id := gen_random_uuid();
    
    v_dict_base := public.vm_create_dict();
    -- SELECT id INTO v_dict_id FROM public.py_dict_object WHERE ob_base = v_dict_base; -- Not needed
    
    INSERT INTO public.py_object (id, ob_type) VALUES (v_type_base_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (id, ob_base, tp_name, tp_bases, tp_dict) 
    VALUES (v_type_id, v_type_base_id, 'MathBox', NULL, v_dict_base);

    -------------------------------------------------------
    -- 2. Define __truediv__ (returns 100 / other)
    -------------------------------------------------------
    v_div_code_base := public.vm_assemble('LOAD_FAST self
POP_TOP
LOAD_CONST 100
LOAD_FAST other
BINARY_TRUE_DIVIDE
RETURN_VALUE', '__truediv__');
    
    SELECT id INTO v_div_code_id FROM public.py_code_object WHERE ob_base = v_div_code_base;
    UPDATE public.py_code_object SET co_argcount = 2 WHERE id = v_div_code_id;
    
    v_div_func_base := gen_random_uuid();
    v_div_func := gen_random_uuid();
    PERFORM public.vm_create_function(v_div_func_base, v_div_func, v_div_code_base, 'MathBox.__truediv__');
    PERFORM public.vm_dict_set_item(v_dict_base, '__truediv__', v_div_func_base);

    -------------------------------------------------------
    -- 3. Define __floordiv__ (returns 100 // other)
    -------------------------------------------------------
    v_floordiv_code_base := public.vm_assemble('LOAD_FAST self
POP_TOP
LOAD_CONST 100
LOAD_FAST other
BINARY_FLOOR_DIVIDE
RETURN_VALUE', '__floordiv__');
    
    SELECT id INTO v_floordiv_code_id FROM public.py_code_object WHERE ob_base = v_floordiv_code_base;
    UPDATE public.py_code_object SET co_argcount = 2 WHERE id = v_floordiv_code_id;
    
    v_floordiv_func_base := gen_random_uuid();
    v_floordiv_func := gen_random_uuid();
    PERFORM public.vm_create_function(v_floordiv_func_base, v_floordiv_func, v_floordiv_code_base, 'MathBox.__floordiv__');
    PERFORM public.vm_dict_set_item(v_dict_base, '__floordiv__', v_floordiv_func_base);

    -------------------------------------------------------
    -- 4. Define __mod__ (returns 100 % other)
    -------------------------------------------------------
    v_mod_code_base := public.vm_assemble('LOAD_FAST self
POP_TOP
LOAD_CONST 100
LOAD_FAST other
BINARY_MODULO
RETURN_VALUE', '__mod__');
    
    SELECT id INTO v_mod_code_id FROM public.py_code_object WHERE ob_base = v_mod_code_base;
    UPDATE public.py_code_object SET co_argcount = 2 WHERE id = v_mod_code_id;
    
    v_mod_func_base := gen_random_uuid();
    v_mod_func := gen_random_uuid();
    PERFORM public.vm_create_function(v_mod_func_base, v_mod_func, v_mod_code_base, 'MathBox.__mod__');
    PERFORM public.vm_dict_set_item(v_dict_base, '__mod__', v_mod_func_base);

    -------------------------------------------------------
    -- 5. Define __pow__ (returns 10 ** other)
    -------------------------------------------------------
    v_pow_code_base := public.vm_assemble('LOAD_FAST self
POP_TOP
LOAD_CONST 10
LOAD_FAST other
BINARY_POWER
RETURN_VALUE', '__pow__');
    
    SELECT id INTO v_pow_code_id FROM public.py_code_object WHERE ob_base = v_pow_code_base;
    UPDATE public.py_code_object SET co_argcount = 2 WHERE id = v_pow_code_id;
    
    v_pow_func_base := gen_random_uuid();
    v_pow_func := gen_random_uuid();
    PERFORM public.vm_create_function(v_pow_func_base, v_pow_func, v_pow_code_base, 'MathBox.__pow__');
    PERFORM public.vm_dict_set_item(v_dict_base, '__pow__', v_pow_func_base);

    -------------------------------------------------------
    -- 6. Instantiate MathBox
    -------------------------------------------------------
    v_obj_base := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_obj_base, v_type_base_id);

    -------------------------------------------------------
    -- 7. Test __truediv__
    -------------------------------------------------------
    v_val2 := public.vm_create_int(4);
    v_res := public.vm_div(v_obj_base, v_val2);
    PERFORM public.test_assert_eq_int(public.vm_get_int_value(v_res), 25, 'MathBox() / 4 = 25');

    -------------------------------------------------------
    -- 8. Test __floordiv__
    -------------------------------------------------------
    v_val2 := public.vm_create_int(7);
    v_res := public.vm_floordiv(v_obj_base, v_val2);
    PERFORM public.test_assert_eq_int(public.vm_get_int_value(v_res), 14, 'MathBox() // 7 = 14');

    -------------------------------------------------------
    -- 9. Test __mod__
    -------------------------------------------------------
    v_val2 := public.vm_create_int(30);
    v_res := public.vm_mod(v_obj_base, v_val2);
    PERFORM public.test_assert_eq_int(public.vm_get_int_value(v_res), 10, 'MathBox() % 30 = 10');

    -------------------------------------------------------
    -- 10. Test __pow__
    -------------------------------------------------------
    v_val2 := public.vm_create_int(3);
    v_res := public.vm_pow(v_obj_base, v_val2);
    PERFORM public.test_assert_eq_int(public.vm_get_int_value(v_res), 1000, 'MathBox() ** 3 = 1000');

    RAISE NOTICE E'\n=== All Extended Arithmetic Tests Passed! ===\n';
END $$;
