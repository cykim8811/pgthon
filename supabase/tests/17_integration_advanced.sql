-- =====================================================
-- Test 17: Integration Advanced
-- Description: Test complex expressions and nested operations
-- =====================================================

DO $$
DECLARE
    -- IDs
    v_type_id uuid;
    v_type_base_id uuid;
    v_dict_base uuid;
    v_dict_id uuid;
    
    v_calc_code_base uuid;
    v_calc_code_id uuid;
    v_calc_func_base uuid;
    v_calc_func uuid;
    
    v_obj_base uuid;
    v_val1 uuid;
    v_val2 uuid;
    v_val3 uuid;
    v_res uuid;
    
    -- Constants
    ID_TYPE_TYPE uuid := '00000000-0000-4000-a000-000000000002';
    
BEGIN
    RAISE NOTICE E'\n=== Testing Advanced Integration ===';

    -------------------------------------------------------
    -- 1. Create Wrapper Type (returns fixed values for arithmetic)
    -------------------------------------------------------
    v_type_base_id := gen_random_uuid();
    v_type_id := gen_random_uuid();
    v_dict_base := public.vm_create_dict();
    SELECT id INTO v_dict_id FROM public.py_dict_object WHERE ob_base = v_dict_base;
    
    INSERT INTO public.py_object (id, ob_type) VALUES (v_type_base_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (id, ob_base, tp_name, tp_bases, tp_dict) 
    VALUES (v_type_id, v_type_base_id, 'Wrapper', NULL, v_dict_id);

    -- Define __add__: returns 50
    PERFORM public.vm_dict_set_item(v_dict_base, '__add__', 
        (SELECT ob_base FROM (
            SELECT public.vm_create_function(gen_random_uuid(), gen_random_uuid(), 
                (SELECT id FROM public.py_code_object WHERE ob_base = public.vm_assemble('LOAD_CONST 50' || E'\n' || 'RETURN_VALUE', '__add__')), 
                'Wrapper.__add__') as ob_base
        ) t)
    );
    -- Fix co_argcount for the newly created __add__
    UPDATE public.py_code_object SET co_argcount = 2 
    WHERE id = (SELECT func_code FROM public.py_function_object WHERE func_name = 'Wrapper.__add__' LIMIT 1);

    -------------------------------------------------------
    -- 2. Complex Expression Test: (a + b) * c
    -------------------------------------------------------
    -- def calc(a, b, c): return (a + b) * c
    v_calc_code_base := public.vm_assemble('LOAD_FAST a
LOAD_FAST b
BINARY_ADD
LOAD_FAST c
BINARY_MULTIPLY
RETURN_VALUE', 'calc');
    
    SELECT id INTO v_calc_code_id FROM public.py_code_object WHERE ob_base = v_calc_code_base;
    UPDATE public.py_code_object SET co_argcount = 3 WHERE id = v_calc_code_id;
    
    v_calc_func_base := gen_random_uuid();
    v_calc_func := gen_random_uuid();
    PERFORM public.vm_create_function(v_calc_func_base, v_calc_func, v_calc_code_id, 'calc');

    -- Test: (10 + 20) * 3 = 90
    v_res := public.vm_call(v_calc_func_base, ARRAY[
        public.vm_create_int(10),
        public.vm_create_int(20),
        public.vm_create_int(3)
    ]);
    PERFORM public.test_assert_eq_int(public.vm_get_int_value(v_res), 90, '(10 + 20) * 3 = 90');

    -------------------------------------------------------
    -- 3. Expression with Custom Object: (Wrapper() + 10) * 2
    -------------------------------------------------------
    -- Wrapper() + 10 returns 50 (from custom __add__)
    -- 50 * 2 = 100
    v_obj_base := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_obj_base, v_type_id);

    v_res := public.vm_call(v_calc_func_base, ARRAY[
        v_obj_base,
        public.vm_create_int(10),
        public.vm_create_int(2)
    ]);
    PERFORM public.test_assert_eq_int(public.vm_get_int_value(v_res), 100, '(Wrapper() + 10) * 2 = 100');

    -------------------------------------------------------
    -- 4. Nested Power and Modulo: (2 ** 10) % 1000
    -------------------------------------------------------
    -- def nested_math(a, b, c): return (a ** b) % c
    v_calc_code_base := public.vm_assemble('LOAD_FAST a
LOAD_FAST b
BINARY_POWER
LOAD_FAST c
BINARY_MODULO
RETURN_VALUE', 'nested_math');
    
    SELECT id INTO v_calc_code_id FROM public.py_code_object WHERE ob_base = v_calc_code_base;
    UPDATE public.py_code_object SET co_argcount = 3 WHERE id = v_calc_code_id;
    
    v_calc_func_base := gen_random_uuid();
    v_calc_func := gen_random_uuid();
    PERFORM public.vm_create_function(v_calc_func_base, v_calc_func, v_calc_code_id, 'nested_math');

    -- Test: (2 ** 10) % 1000 = 1024 % 1000 = 24
    v_res := public.vm_call(v_calc_func_base, ARRAY[
        public.vm_create_int(2),
        public.vm_create_int(10),
        public.vm_create_int(1000)
    ]);
    PERFORM public.test_assert_eq_int(public.vm_get_int_value(v_res), 24, '(2 ** 10) % 1000 = 24');

    -------------------------------------------------------
    -- 5. Deeply Nested Arithmetic: a - (b // c)
    -------------------------------------------------------
    -- def deep_nest(a, b, c): return a - (b // c)
    v_calc_code_base := public.vm_assemble('LOAD_FAST a
LOAD_FAST b
LOAD_FAST c
BINARY_FLOOR_DIVIDE
BINARY_SUBTRACT
RETURN_VALUE', 'deep_nest');
    
    SELECT id INTO v_calc_code_id FROM public.py_code_object WHERE ob_base = v_calc_code_base;
    UPDATE public.py_code_object SET co_argcount = 3 WHERE id = v_calc_code_id;
    
    v_calc_func_base := gen_random_uuid();
    v_calc_func := gen_random_uuid();
    PERFORM public.vm_create_function(v_calc_func_base, v_calc_func, v_calc_code_id, 'deep_nest');

    -- Test: 100 - (30 // 7) = 100 - 4 = 96
    v_res := public.vm_call(v_calc_func_base, ARRAY[
        public.vm_create_int(100),
        public.vm_create_int(30),
        public.vm_create_int(7)
    ]);
    PERFORM public.test_assert_eq_int(public.vm_get_int_value(v_res), 96, '100 - (30 // 7) = 96');

    RAISE NOTICE E'\n=== All Advanced Integration Tests Passed! ===\n';
END $$;
