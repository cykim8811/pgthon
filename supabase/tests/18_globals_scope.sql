-- =====================================================
-- Test 18: Global Scope Scope Check
-- Description: Verify that functions can access global variables
-- =====================================================

DO $$
DECLARE
    -- IDs
    v_dict_base uuid;
    v_dict_id uuid;
    
    v_code_base uuid;
    v_code_id uuid;
    
    v_func_base uuid;
    v_func_id uuid;
    
    v_res uuid;
    v_res_val bigint;
    
    -- "GLOBAL_VAR"
    c_source text := 'LOAD_GLOBAL GLOBAL_VAR
RETURN_VALUE';

BEGIN
    RAISE NOTICE E'\n=== Testing Global Scope Access ===';
    
    -------------------------------------------------------
    -- 1. Create Globals Dictionary (Module Dict)
    -------------------------------------------------------
    v_dict_base := public.vm_create_dict(); -- returns Base ID
    -- Using Base ID for dict operations is standard now.
    
    -- Set Global Variable: GLOBAL_VAR = 999
    PERFORM public.vm_dict_set_item(v_dict_base, 'GLOBAL_VAR', public.vm_create_int(999));
    
    -------------------------------------------------------
    -- 2. Create Function using implicit globals
    -------------------------------------------------------
    -- Assemble code
    v_code_base := public.vm_assemble(c_source, 'test_global');
    
    -- Create Function Object, explicitly passing our globals dict
    v_func_base := gen_random_uuid();
    v_func_id := gen_random_uuid();
    
    -- Note: We updated vm_create_function signature in '20260121000030'.
    -- vm_create_function(p_id, p_func_id, p_code_base_id, p_name, p_globals)
    PERFORM public.vm_create_function(v_func_base, v_func_id, v_code_base, 'test_global', v_dict_base);
    
    -------------------------------------------------------
    -- 3. Execute Function
    -------------------------------------------------------
    -- Calling the function. 
    -- Internally, vm_call should pluck 'globals' from the function object 
    -- and pass it to vm_create_frame / vm_run_frame.
    
    BEGIN
        v_res := public.vm_call(v_func_base, ARRAY[]::uuid[]);
        
        -- Check result
        v_res_val := public.vm_get_int_value(v_res);
        PERFORM public.test_assert_eq_int(v_res_val, 999, 'Function should access global variable');
        
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Caught Error: %', SQLERRM;
        PERFORM public.test_assert(false, 'Failed to access global variable: ' || SQLERRM);
    END;

    RAISE NOTICE E'\n✅ PASS: 18_globals_scope';
END $$;
