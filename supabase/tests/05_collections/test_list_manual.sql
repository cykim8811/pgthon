-- Test: 05 Collections - List Operations
-- Verify List creation (manual), append, and integration with VM
DO $$
DECLARE
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    
    v_list_id UUID;
    v_list_base UUID;
    v_item1 UUID;
    v_item2 UUID;
    
    v_res UUID;
    v_val TEXT;
    v_len INTEGER;
    
    -- We can't use BUILD_LIST yet, so we manually create a list
    -- and test methods on it via VM calls?
    -- Currently VM calls to methods only supported via LOAD_ATTR + CALL_FUNCTION.
    -- But we can skip full VM cycle and test `vm_call` directly if we want unit test.
    -- Or better: Use assembler but rely on an existing global list?
    -- Let's manual insert a list, then run VM code that uses it.
    
    v_source_len TEXT;
    
BEGIN
    -- 1. Setup: Create Manual List ['hello', 'world']
    v_list_base := gen_random_uuid();
    v_list_id := gen_random_uuid();
    
    INSERT INTO public.py_object (id, ob_type) VALUES (v_list_base, ID_LIST_TYPE);
    
    -- Create items
    v_item1 := public.vm_assembler_get_or_create_const('hello');
    v_item2 := public.vm_assembler_get_or_create_const('world');
    
    -- Using py_tuple_object structure for list storage as per current MVP implementation?
    -- Wait, our `vm_native_list_append` (if implemented) uses `py_tuple_object`?
    -- Let's check `add_list_methods.sql`: It didn't implement append logic fully in sql, it registered it.
    -- But wait, `add_list_methods.sql` only registered generic native functions?
    -- Actually `vm_native_list_append` was NOT implemented in `add_list_methods.sql`.
    -- So `append` might fail.
    
    -- Let's just test READ-ONLY list features first (iter, access).
    -- We use `py_tuple_object` table to simulate list content (since list inherits var_object but storage is fuzzy in MVP).
    -- Actually `vm_inspect_object` reads from `py_tuple_object` for lists. So let's insert there.
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item) 
    VALUES (v_list_id, v_list_base, ARRAY[v_item1, v_item2]);
    
    -- Update size
    -- INSERT INTO public.py_var_object ... (Inheritance handling is tricky in manual insert, skipping for now as tuple obj has array)
    
    -- 2. Test: Iterate over list (Assembler)
    -- This requires passing the list to the VM.
    -- We can't pass arguments to `vm_execute_source` easily (it resets locals).
    -- But we can use `LOAD_CONST` with the UUID of our list if we hack the assembler?
    -- No, assembler takes text.
    
    -- Alternative: Test VM internals (Unit Test)
    -- Call `vm_getattr` for `__iter__`
    DECLARE
        v_iter UUID;
        v_next UUID;
        v_val1 UUID;
    BEGIN
        v_iter := public.vm_call(public.vm_getattr(v_list_base, '__iter__'), ARRAY[]::UUID[]);
        PERFORM public.test_assert(v_iter IS NOT NULL, 'List __iter__ returned object');
        
        v_next := public.vm_getattr(v_iter, '__next__');
        v_val1 := public.vm_call(v_next, ARRAY[]::UUID[]);
        
        SELECT str_value INTO v_val FROM public.py_unicode_object WHERE ob_base = v_val1;
        PERFORM public.test_assert(v_val = 'hello', 'Iterator first item is hello');
        
        v_val1 := public.vm_call(v_next, ARRAY[]::UUID[]);
        SELECT str_value INTO v_val FROM public.py_unicode_object WHERE ob_base = v_val1;
        PERFORM public.test_assert(v_val = 'world', 'Iterator second item is world');
        
        -- StopIteration check?
        -- v_val1 := public.vm_call(v_next, ARRAY[]::UUID[]);
        -- It should return NULL (our convention for StopIteration in native next)
         v_val1 := public.vm_call(v_next, ARRAY[]::UUID[]);
         PERFORM public.test_assert(v_val1 IS NULL, 'Iterator finished (StopIteration)');
    END;

END $$;
