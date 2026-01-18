-- Test: For Loop Iteration
DO $$
DECLARE
    -- IDs
    v_code_id UUID := gen_random_uuid();
    v_consts_id UUID := gen_random_uuid();
    v_varnames_id UUID := gen_random_uuid();
    
    v_list_id UUID; -- To be created
    v_sum_id UUID;
    v_res BIGINT;
    
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_TUP_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    
    v_n1 UUID := gen_random_uuid(); -- "total"
    v_n2 UUID := gen_random_uuid(); -- "x"
    v_n3 UUID := gen_random_uuid(); -- "numbers"
    
    v_c1 UUID := gen_random_uuid(); -- 0 (Initial total)
    
    -- Bytecode Logic:
    -- total = 0
    -- for x in numbers:
    --    total = total + x
    -- return total
    
    -- Bytecode:
    -- 1. LOAD_CONST 0 (0)
    -- 2. STORE_FAST 0 ("total")
    -- 3. LOAD_FAST 2 ("numbers")
    -- 4. GET_ITER
    -- 5. FOR_ITER 6 (Jump to line 12 if done) (Target is relative usually? Here relative to NEXT instruction. Current PC=5. Next=6. Target=12. Delta=6)
    -- 6. STORE_FAST 1 ("x")
    -- 7. LOAD_FAST 0 ("total")
    -- 8. LOAD_FAST 1 ("x")
    -- 9. BINARY_ADD
    -- 10. STORE_FAST 0 ("total")
    -- 11. JUMP_ABSOLUTE 5 (Loop back to FOR_ITER)
    -- 12. LOAD_FAST 0 ("total")
    -- 13. RETURN_VALUE
    
    v_code_text TEXT := 
'LOAD_CONST 0
STORE_FAST 0
LOAD_FAST 2
GET_ITER
FOR_ITER 6
STORE_FAST 1
LOAD_FAST 0
LOAD_FAST 1
BINARY_ADD
STORE_FAST 0
JUMP_ABSOLUTE 5
LOAD_FAST 0
RETURN_VALUE';

BEGIN
    -- 1. Setup Varnames: ("total", "x", "numbers")
    INSERT INTO public.py_object (id, ob_type) VALUES (v_n1, ID_STR_TYPE), (v_n2, ID_STR_TYPE), (v_n3, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (v_n1, v_n1, 'total'), (v_n2, v_n2, 'x'), (v_n3, v_n3, 'numbers');
    
    INSERT INTO public.py_object (id, ob_type) VALUES (v_varnames_id, ID_TUP_TYPE);
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item) VALUES (v_varnames_id, v_varnames_id, ARRAY[v_n1, v_n2, v_n3]);

    -- 2. Setup Consts: (0)
    INSERT INTO public.py_object (id, ob_type) VALUES (v_c1, ID_INT_TYPE);
    INSERT INTO public.py_long_object (id, ob_base, long_value) VALUES (v_c1, v_c1, 0);
    
    INSERT INTO public.py_object (id, ob_type) VALUES (v_consts_id, ID_TUP_TYPE);
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item) VALUES (v_consts_id, v_consts_id, ARRAY[v_c1]);

    -- 3. Setup Code
    INSERT INTO public.py_object (id, ob_type) VALUES (v_code_id, NULL);
    INSERT INTO public.py_code_object (id, ob_base, co_name, co_code, co_consts, co_varnames)
    VALUES (v_code_id, v_code_id, 'test_loop', v_code_text, v_consts_id, v_varnames_id);

    -- 4. Create List [10, 20, 30]
    -- We assume public.vm_create_list exists or we manual create.
    -- Manual for safety as CREATE LIST helpers might be basic.
    -- Actually we used vm_create_list in previous test.
    v_list_id := public.vm_create_list();
    -- Append 10, 20, 30
    DECLARE
        v_append UUID;
        v_i1 UUID := gen_random_uuid(); v_i2 UUID := gen_random_uuid(); v_i3 UUID := gen_random_uuid();
    BEGIN
        INSERT INTO public.py_object (id, ob_type) VALUES (v_i1, ID_INT_TYPE), (v_i2, ID_INT_TYPE), (v_i3, ID_INT_TYPE);
        INSERT INTO public.py_long_object (id, ob_base, long_value) VALUES (v_i1, v_i1, 10), (v_i2, v_i2, 20), (v_i3, v_i3, 30);
        
        -- Append Logic (Manual or via VM call)
        -- Let's use vm_call on append to be rigorous, but for setup speed, direct insert into py_list_item?
        -- No, let's use append method call if possible, OR vm_list_append helper if we made one.
        -- We didn't make vm_list_append helper public.
        -- Let's use vm_call(getattr(L, "append"), [10])
        v_append := public.vm_getattr(v_list_id, 'append');
        PERFORM public.vm_call(v_append, ARRAY[v_i1]);
        PERFORM public.vm_call(v_append, ARRAY[v_i2]);
        PERFORM public.vm_call(v_append, ARRAY[v_i3]);
    END;
    
    -- 5. Run Frame
    DECLARE
        v_locals_id UUID;
        v_base_locals UUID := gen_random_uuid();
        ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    BEGIN
        v_locals_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (v_base_locals, ID_DCT_TYPE);
        INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (v_locals_id, v_base_locals, 0);
        
        -- Set 'numbers' in locals
        PERFORM public.vm_dict_set_item(v_locals_id, 'numbers', v_list_id);
        
        -- Run
        v_sum_id := public.vm_run_frame(v_code_id, v_locals_id, NULL);
        
        -- Check Result (Should be 60)
        SELECT long_value INTO v_res FROM public.py_long_object WHERE ob_base = v_sum_id;
        
        IF v_res = 60 THEN
            RAISE NOTICE 'SUCCESS: Loop works! Sum is 60.';
        ELSE
            RAISE EXCEPTION 'FAILURE: Expected 60, got %', v_res;
        END IF;
    END;
END $$;
