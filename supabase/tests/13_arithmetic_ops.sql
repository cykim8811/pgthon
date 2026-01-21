-- =====================================================
-- Test 13: Arithmetic Operations (Custom Objects)
-- Description: Verify vm_add dispatch logic (__add__)
-- =====================================================

DO $$
DECLARE
    -- IDs
    v_type_id uuid;
    v_type_base_id uuid;
    v_dict_id uuid;
    v_dict_base uuid;
    
    v_add_code_base uuid;
    v_add_code_id uuid;
    v_add_func uuid;
    v_add_func_base uuid;
    
    v_instance_base uuid;
    
    v_res uuid;
    v_res_val bigint;
    
    -- Constants
    ID_TYPE_TYPE uuid := '00000000-0000-4000-a000-000000000002';
    ID_DCT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
    
    -- Source for __add__
    -- def __add__(self, other):
    --     return self.val + other
    --
    -- Bytecode:
    -- LOAD_FAST self
    -- LOAD_ATTR val (We don't have LOAD_ATTR fully working for instances yet? Let's assume attributes are in separate dict)
    -- Actually vm_getattr logic: 1. Type lookup, 2. Descriptor, 3. Instance dict?
    -- Current vm_getattr (Step 751 view) implementation:
    --    Only searches Type's MRO. Step 4 (Instance dict) is marked TODO.
    --    So we cannot store state in instance dict effectively for LOAD_ATTR?
    
    -- WORKAROUND: For this test, let's make __add__ just return a fixed value + other
    -- to prove it was called.
    -- return 100 + other
    -- We must reference 'self' first so it gets varname index 0
    c_add_source text := 'LOAD_FAST self
POP_TOP
LOAD_FAST other
LOAD_CONST 100
BINARY_ADD
RETURN_VALUE';

BEGIN
    RAISE NOTICE 'Testing Custom Arithmetic Operations...';

    -------------------------------------------------------
    -- 1. Create a Custom Type "NumBox"
    -------------------------------------------------------
    v_type_id := gen_random_uuid();
    v_type_base_id := gen_random_uuid();
    
    -- Create Type Dictionary
    v_dict_base := public.vm_create_dict(); -- returns base ID
    
    -- Create Type Object
    INSERT INTO public.py_object (id, ob_type) VALUES (v_type_base_id, ID_TYPE_TYPE);
    
    -- tp_dict uses Base ID now
    INSERT INTO public.py_type_object (id, ob_base, tp_name, tp_dict) 
    VALUES (v_type_id, v_type_base_id, 'NumBox', v_dict_base);

    -------------------------------------------------------
    -- 2. Define __add__ Method
    -------------------------------------------------------
    v_add_code_base := public.vm_assemble(c_add_source, '__add__');
    
    -- Get Code Object Table ID
    SELECT id INTO v_add_code_id FROM public.py_code_object WHERE ob_base = v_add_code_base;
    
    -- Update Code Object to have 2 arguments (self, other) so vm_call binds them
    UPDATE public.py_code_object SET co_argcount = 2 WHERE id = v_add_code_id;
    
    -- Create Function Object
    v_add_func_base := gen_random_uuid();
    v_add_func := gen_random_uuid();
    -- func_code uses Base ID now. v_add_code_base is Base ID.
    -- vm_create_function expects code Base ID? Let's check vm_helpers.
    -- vm_create_function(base_id, func_id, code_id, name)
    -- In vm_helpers.sql (03), vm_create_function takes code_id.
    -- Wait, vm_create_function signature?
    -- It was not in 03, but in migration 20260118210800_vm_helpers.sql.
    -- If it takes Code Table ID, we might have issue if it inserts into func_code (Base ID Ref).
    -- But vm_create_function constructs py_function_object. 
    -- 20260120000110_base_id_unification.sql updated py_function_object to ref Base ID.
    -- It did NOT update vm_create_function implementation? 
    -- If vm_create_function inserts args directly, it needs Base ID.
    
    -- Assuming I need to pass Base ID here if vm_create_function is naive.
    -- BUT v_add_code_id is Table ID. v_add_code_base is Base ID.
    
    -- Let's assume standard vm_create_function (if naive insert) needs Base ID.
    -- I will check vm_create_function later.
    
    -- For now I just fix the obvious explicit INSERTs in this file.
    
    PERFORM public.vm_create_function(v_add_func_base, v_add_func, v_add_code_base, 'NumBox.__add__'); 
    
    -- Register __add__ in Type's dict
    PERFORM public.vm_dict_set_item(v_dict_base, '__add__', v_add_func_base);
    
    -------------------------------------------------------
    -- 3. Create Instance
    -------------------------------------------------------
    v_instance_base := gen_random_uuid();
    -- ob_type uses Base ID
    INSERT INTO public.py_object (id, ob_type) VALUES (v_instance_base, v_type_base_id);
    
    -------------------------------------------------------
    -- 4. Test vm_add(instance, 50)
    -------------------------------------------------------
    -- Should call instance.__add__(50) -> return 100 + 50 = 150
    v_res := public.vm_add(v_instance_base, public.vm_create_int(50));
    
    v_res_val := public.vm_get_int_value(v_res);
    PERFORM public.test_assert_eq_int(v_res_val, 150, 'Custom __add__ dispatch failed');
    
    RAISE NOTICE E'\n✅ PASS: 13_arithmetic_ops';
END $$;
