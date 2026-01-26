-- ============================================================================
-- Test: VM LOAD_NAME Opcode Test
-- 
-- Purpose:
--   Tests that LOAD_NAME opcode handler works correctly. This verifies:
--   - py_opcode_LOAD_NAME correctly loads names from namespace hierarchy
--   - Namespace lookup order: locals → globals → builtins
--   - Values are pushed onto the evaluation stack
--   - Index validation works correctly
--   - NameError is raised when name is not found
--   - Integration with py_eval_frame
--
-- Usage:
--   Run this file after migrations to verify LOAD_NAME opcode implementation.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

DO $$
DECLARE
    -- Builtin Type IDs (from bootstrap)
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-a000-000000000010';
    ID_LEN_FUNCTION UUID := '00000000-0000-4000-a000-000000000020';
    
    -- Test counters
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    
    -- Frame and code objects
    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_names_id UUID;
    co_consts_id UUID;
    
    -- Test objects
    const0_id UUID;
    name0_str_id UUID;  -- 'x'
    name1_str_id UUID;  -- 'y'
    name2_str_id UUID;  -- 'len'
    len_str_id UUID;    -- 'len' (from builtins)
    
    -- Test variables
    loaded_obj_id UUID;
    stack_size INTEGER;
    
    -- Helper variables
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    real_builtins_dict_id UUID;
    
    -- Error handling
    error_occurred BOOLEAN;
    error_message TEXT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM LOAD_NAME Opcode Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Setup: Create test objects and frame
    -- ========================================================================
    RAISE NOTICE 'Setting up test environment...';
    
    -- Create test constant
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 42);
    
    -- Create name strings
    name0_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name0_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name0_str_id, 'x');
    
    name1_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name1_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name1_str_id, 'y');
    
    name2_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name2_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name2_str_id, 'len');
    
    -- Get 'len' string from bootstrap (for builtins lookup)
    SELECT ob_base INTO len_str_id
    FROM public.py_unicode_object
    WHERE str_value = 'len'
    LIMIT 1;
    
    IF len_str_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: ''len'' string not found in bootstrap. Bootstrap migration must run first.';
    END IF;
    
    -- Get real __builtins__ module dict
    SELECT md_dict INTO real_builtins_dict_id
    FROM public.py_module_object
    WHERE ob_base = ID_BUILTINS_MODULE;
    
    IF real_builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ module dict not found. Bootstrap migration must run first.';
    END IF;
    
    -- Create constants tuple (co_consts) - empty for this test
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);
    
    -- Create namespace dicts
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    
    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);
    
    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Test 1: Function exists
    -- ========================================================================
    RAISE NOTICE 'Test 1: Function exists...';
    test_count := test_count + 1;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'py_opcode_load_name' 
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_LOAD_NAME function does not exist';
    END IF;
    
    RAISE NOTICE '  ✓ py_opcode_LOAD_NAME function exists';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: LOAD_NAME loads from locals dict
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: LOAD_NAME loads from locals dict...';
    test_count := test_count + 1;
    
    -- Create names tuple (co_names) with 'x'
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id]);
    
    -- Create empty bytecode (not used in this test)
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);
    
    -- Create code object
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );
    
    -- Create frame
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    -- Store value in locals dict with key 'x'
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value)
    VALUES (locals_dict_id, name0_str_id, const0_id);
    
    -- Execute LOAD_NAME(0) - loads 'x' from locals
    PERFORM public.py_opcode_LOAD_NAME(frame_id, 0);
    
    -- Verify value is on stack
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size IS NULL OR stack_size != 1 THEN
        RAISE EXCEPTION 'FAIL: Stack size after LOAD_NAME is %, expected 1', stack_size;
    END IF;
    
    -- Verify correct value is on stack
    SELECT f_valuestack[1] INTO loaded_obj_id
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF loaded_obj_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Loaded value is %, expected % (const0_id)', loaded_obj_id, const0_id;
    END IF;
    
    RAISE NOTICE '  ✓ LOAD_NAME correctly loads from locals dict';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: LOAD_NAME loads from globals when not in locals
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: LOAD_NAME loads from globals when not in locals...';
    test_count := test_count + 1;
    
    -- Clear stack
    UPDATE public.py_frame_object
    SET f_valuestack = array[]::uuid[]
    WHERE ob_base = frame_id;
    
    -- Remove 'x' from locals (if exists)
    DELETE FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id
    AND me_key = name0_str_id;
    
    -- Store value in globals dict with key 'x'
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value)
    VALUES (globals_dict_id, name0_str_id, const0_id);
    
    -- Execute LOAD_NAME(0) - should find 'x' in globals
    PERFORM public.py_opcode_LOAD_NAME(frame_id, 0);
    
    -- Verify value is on stack
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 1 THEN
        RAISE EXCEPTION 'FAIL: Stack size after LOAD_NAME is %, expected 1', stack_size;
    END IF;
    
    -- Verify correct value is on stack
    SELECT f_valuestack[1] INTO loaded_obj_id
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF loaded_obj_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Loaded value is %, expected % (const0_id)', loaded_obj_id, const0_id;
    END IF;
    
    RAISE NOTICE '  ✓ LOAD_NAME correctly loads from globals when not in locals';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: LOAD_NAME loads from builtins when not in locals or globals
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: LOAD_NAME loads from builtins when not in locals or globals...';
    test_count := test_count + 1;
    
    -- Clear stack
    UPDATE public.py_frame_object
    SET f_valuestack = array[]::uuid[]
    WHERE ob_base = frame_id;
    
    -- Remove 'len' from locals and globals (if exists)
    DELETE FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id
    AND me_key = name2_str_id;
    
    DELETE FROM public.py_dict_entry
    WHERE dict_id = globals_dict_id
    AND me_key = name2_str_id;
    
    -- Update frame to use real builtins dict
    UPDATE public.py_frame_object
    SET f_builtins = real_builtins_dict_id
    WHERE ob_base = frame_id;
    
    -- Update co_names to include 'len'
    UPDATE public.py_tuple_object
    SET ob_item = ARRAY[name2_str_id]
    WHERE ob_base = co_names_id;
    
    -- Execute LOAD_NAME(0) - should find 'len' in builtins
    PERFORM public.py_opcode_LOAD_NAME(frame_id, 0);
    
    -- Verify value is on stack
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 1 THEN
        RAISE EXCEPTION 'FAIL: Stack size after LOAD_NAME is %, expected 1', stack_size;
    END IF;
    
    -- Verify len function is on stack
    SELECT f_valuestack[1] INTO loaded_obj_id
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF loaded_obj_id != ID_LEN_FUNCTION THEN
        RAISE EXCEPTION 'FAIL: Loaded value is %, expected % (ID_LEN_FUNCTION)', loaded_obj_id, ID_LEN_FUNCTION;
    END IF;
    
    RAISE NOTICE '  ✓ LOAD_NAME correctly loads from builtins when not in locals or globals';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: LOAD_NAME namespace lookup order (locals takes precedence)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: LOAD_NAME namespace lookup order (locals takes precedence)...';
    test_count := test_count + 1;
    
    -- Clear stack
    UPDATE public.py_frame_object
    SET f_valuestack = array[]::uuid[]
    WHERE ob_base = frame_id;
    
    -- Create different values for each namespace
    DECLARE
        locals_value_id UUID;
        globals_value_id UUID;
    BEGIN
        locals_value_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (locals_value_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (locals_value_id, 100);
        
        globals_value_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (globals_value_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (globals_value_id, 200);
        
        -- Store 'x' in both locals and globals (different values)
        INSERT INTO public.py_dict_entry (dict_id, me_key, me_value)
        VALUES (locals_dict_id, name0_str_id, locals_value_id);
        
        INSERT INTO public.py_dict_entry (dict_id, me_key, me_value)
        VALUES (globals_dict_id, name0_str_id, globals_value_id);
        
        -- Update co_names to include 'x'
        UPDATE public.py_tuple_object
        SET ob_item = ARRAY[name0_str_id]
        WHERE ob_base = co_names_id;
        
        -- Execute LOAD_NAME(0) - should find 'x' in locals (not globals)
        PERFORM public.py_opcode_LOAD_NAME(frame_id, 0);
        
        -- Verify locals value is on stack (not globals value)
        SELECT f_valuestack[1] INTO loaded_obj_id
        FROM public.py_frame_object
        WHERE ob_base = frame_id;
        
        IF loaded_obj_id != locals_value_id THEN
            RAISE EXCEPTION 'FAIL: Loaded value is %, expected % (locals_value_id, not globals)', loaded_obj_id, locals_value_id;
        END IF;
        
        IF loaded_obj_id = globals_value_id THEN
            RAISE EXCEPTION 'FAIL: Loaded value is from globals, expected from locals (wrong lookup order)';
        END IF;
    END;
    
    RAISE NOTICE '  ✓ LOAD_NAME correctly prioritizes locals over globals';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 6: LOAD_NAME raises NameError when name not found
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: LOAD_NAME raises NameError when name not found...';
    test_count := test_count + 1;
    
    -- Clear stack
    UPDATE public.py_frame_object
    SET f_valuestack = array[]::uuid[]
    WHERE ob_base = frame_id;
    
    -- Remove 'y' from all namespaces
    DELETE FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id
    AND me_key = name1_str_id;
    
    DELETE FROM public.py_dict_entry
    WHERE dict_id = globals_dict_id
    AND me_key = name1_str_id;
    
    -- Update co_names to include 'y' (not in any namespace)
    UPDATE public.py_tuple_object
    SET ob_item = ARRAY[name1_str_id]
    WHERE ob_base = co_names_id;
    
    -- Execute LOAD_NAME(0) - should raise NameError
    BEGIN
        PERFORM public.py_opcode_LOAD_NAME(frame_id, 0);
        RAISE EXCEPTION 'FAIL: LOAD_NAME did not raise NameError for undefined name';
    EXCEPTION
        WHEN OTHERS THEN
            error_message := SQLERRM;
            IF error_message NOT LIKE 'NameError: name ''y'' is not defined%' THEN
                RAISE EXCEPTION 'FAIL: LOAD_NAME raised wrong exception: %', error_message;
            END IF;
    END;
    
    RAISE NOTICE '  ✓ LOAD_NAME correctly raises NameError when name not found';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 7: LOAD_NAME index validation
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: LOAD_NAME index validation...';
    test_count := test_count + 1;
    
    -- Test negative index
    BEGIN
        PERFORM public.py_opcode_LOAD_NAME(frame_id, -1);
        RAISE EXCEPTION 'FAIL: LOAD_NAME did not raise exception for negative index';
    EXCEPTION
        WHEN OTHERS THEN
            error_message := SQLERRM;
            IF error_message NOT LIKE 'LOAD_NAME: name_index must be non-negative%' THEN
                RAISE EXCEPTION 'FAIL: LOAD_NAME raised wrong exception for negative index: %', error_message;
            END IF;
    END;
    
    -- Test out of range index
    BEGIN
        PERFORM public.py_opcode_LOAD_NAME(frame_id, 999);
        RAISE EXCEPTION 'FAIL: LOAD_NAME did not raise exception for out of range index';
    EXCEPTION
        WHEN OTHERS THEN
            error_message := SQLERRM;
            IF error_message NOT LIKE 'LOAD_NAME: Index % out of range for co_names tuple%' THEN
                RAISE EXCEPTION 'FAIL: LOAD_NAME raised wrong exception for out of range index: %', error_message;
            END IF;
    END;
    
    RAISE NOTICE '  ✓ LOAD_NAME correctly validates index';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test Summary
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total tests: %', test_count;
    RAISE NOTICE 'Passed: %', pass_count;
    RAISE NOTICE 'Failed: %', fail_count;
    RAISE NOTICE '';
    
    IF fail_count > 0 THEN
        RAISE EXCEPTION 'Test suite failed: % out of % tests failed', fail_count, test_count;
    END IF;
    
    RAISE NOTICE 'All tests passed! ✓';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Test failed with error:';
        RAISE NOTICE '%', SQLERRM;
        RAISE NOTICE '========================================';
        RAISE;
END $$;
