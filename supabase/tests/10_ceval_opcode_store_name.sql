-- ============================================================================
-- Test: VM STORE_NAME Opcode Test
-- 
-- Purpose:
--   Tests that STORE_NAME opcode handler works correctly. This verifies:
--   - py_opcode_STORE_NAME correctly stores values from stack into locals dict
--   - Values are stored with correct keys from co_names
--   - Existing entries are updated correctly
--   - Stack is popped correctly
--   - Index validation works correctly
--   - Integration with py_eval_frame
--
-- Usage:
--   Run this file after migrations to verify STORE_NAME opcode implementation.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    -- Builtin Type IDs (from bootstrap)
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    
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
    name0_str_id UUID;
    name1_str_id UUID;
    
    -- Test variables
    stored_value_id UUID;
    stack_size INTEGER;
    entry_count INTEGER;
    
    -- Helper variables
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    
    -- Error handling
    error_occurred BOOLEAN;
    error_message TEXT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM STORE_NAME Opcode Test';
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
    
    -- Create empty tuple for various tuple fields
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    
    -- Create empty string
    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
    
    -- Create names tuple (co_names) with test names
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id, name1_str_id]);
    
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
        WHERE proname = 'py_opcode_store_name' 
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_STORE_NAME function does not exist';
    END IF;
    
    RAISE NOTICE '  ✓ py_opcode_STORE_NAME function exists';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: STORE_NAME stores value from stack into locals dict
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: STORE_NAME stores value from stack into locals dict...';
    test_count := test_count + 1;
    
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
    
    -- Push value onto stack
    PERFORM public.py_stack_push(frame_id, const0_id);
    
    -- Execute STORE_NAME(0) - stores value with name 'x' (name0_str_id)
    PERFORM public.py_opcode_STORE_NAME(frame_id, 0);
    
    -- Verify stack is empty after STORE_NAME
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size IS NOT NULL AND stack_size != 0 THEN
        RAISE EXCEPTION 'FAIL: Stack size after STORE_NAME is %, expected 0 (empty)', stack_size;
    END IF;
    
    -- Verify value is stored in locals dict
    SELECT me_value INTO stored_value_id
    FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id
    AND me_key = name0_str_id;
    
    IF stored_value_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: Value not stored in locals dict for name ''x''';
    END IF;
    
    IF stored_value_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Stored value is %, expected % (const0_id)', stored_value_id, const0_id;
    END IF;
    
    RAISE NOTICE '  ✓ STORE_NAME correctly stores value from stack into locals dict';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: STORE_NAME updates existing entry
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: STORE_NAME updates existing entry...';
    test_count := test_count + 1;
    
    -- Create new constant
    DECLARE
        const1_id UUID;
    BEGIN
        const1_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 100);
        
        -- Push new value onto stack
        PERFORM public.py_stack_push(frame_id, const1_id);
        
        -- Execute STORE_NAME(0) again - should update existing entry
        PERFORM public.py_opcode_STORE_NAME(frame_id, 0);
        
        -- Verify value is updated
        SELECT me_value INTO stored_value_id
        FROM public.py_dict_entry
        WHERE dict_id = locals_dict_id
        AND me_key = name0_str_id;
        
        IF stored_value_id != const1_id THEN
            RAISE EXCEPTION 'FAIL: Stored value is %, expected % (const1_id, updated)', stored_value_id, const1_id;
        END IF;
        
        -- Verify only one entry exists for this key (not duplicated)
        SELECT COUNT(*) INTO entry_count
        FROM public.py_dict_entry
        WHERE dict_id = locals_dict_id
        AND me_key = name0_str_id;
        
        IF entry_count != 1 THEN
            RAISE EXCEPTION 'FAIL: Found % entries for key, expected 1 (no duplication)', entry_count;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ STORE_NAME correctly updates existing entry';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: STORE_NAME with different name indices
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: STORE_NAME with different name indices...';
    test_count := test_count + 1;
    
    -- Create new constant for second name
    DECLARE
        const2_id UUID;
    BEGIN
        const2_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const2_id, 200);
        
        -- Push value onto stack
        PERFORM public.py_stack_push(frame_id, const2_id);
        
        -- Execute STORE_NAME(1) - stores value with name 'y' (name1_str_id)
        PERFORM public.py_opcode_STORE_NAME(frame_id, 1);
        
        -- Verify value is stored for second name
        SELECT me_value INTO stored_value_id
        FROM public.py_dict_entry
        WHERE dict_id = locals_dict_id
        AND me_key = name1_str_id;
        
        IF stored_value_id != const2_id THEN
            RAISE EXCEPTION 'FAIL: Stored value for name ''y'' is %, expected % (const2_id)', stored_value_id, const2_id;
        END IF;
        
        -- Verify both entries exist
        SELECT COUNT(*) INTO entry_count
        FROM public.py_dict_entry
        WHERE dict_id = locals_dict_id;
        
        IF entry_count != 2 THEN
            RAISE EXCEPTION 'FAIL: Found % entries in locals dict, expected 2', entry_count;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ STORE_NAME works correctly with different name indices';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: STORE_NAME with out-of-range index
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: STORE_NAME with out-of-range index...';
    test_count := test_count + 1;
    
    -- Push value onto stack
    PERFORM public.py_stack_push(frame_id, const0_id);
    
    error_occurred := FALSE;
    BEGIN
        PERFORM public.py_opcode_STORE_NAME(frame_id, 999);
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on out-of-range index';
    END IF;
    
    IF error_message NOT LIKE '%out of range%' THEN
        RAISE EXCEPTION 'FAIL: Expected "out of range" error, got: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ STORE_NAME with out-of-range index correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 6: STORE_NAME with negative index
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: STORE_NAME with negative index...';
    test_count := test_count + 1;
    
    -- Push value onto stack
    PERFORM public.py_stack_push(frame_id, const0_id);
    
    error_occurred := FALSE;
    BEGIN
        PERFORM public.py_opcode_STORE_NAME(frame_id, -1);
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on negative index';
    END IF;
    
    IF error_message NOT LIKE '%non-negative%' THEN
        RAISE EXCEPTION 'FAIL: Expected "non-negative" error, got: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ STORE_NAME with negative index correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 7: STORE_NAME with empty stack
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: STORE_NAME with empty stack...';
    test_count := test_count + 1;
    
    -- Ensure stack is empty
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[] WHERE ob_base = frame_id;
    
    error_occurred := FALSE;
    BEGIN
        PERFORM public.py_opcode_STORE_NAME(frame_id, 0);
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on empty stack';
    END IF;
    
    IF error_message NOT LIKE '%underflow%' AND error_message NOT LIKE '%empty%' THEN
        RAISE EXCEPTION 'FAIL: Expected stack underflow error, got: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ STORE_NAME with empty stack correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 8: STORE_NAME integration with py_eval_frame
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: STORE_NAME integration with py_eval_frame...';
    test_count := test_count + 1;
    
    -- Create bytecode: LOAD_CONST(0) STORE_NAME(0) RETURN_VALUE
    -- But we need a constant first, so create a new setup
    DECLARE
        test_const_id UUID;
        test_co_consts_id UUID;
        test_co_code_id UUID;
        test_code_obj_id UUID;
        test_frame_id UUID;
    BEGIN
        -- Create test constant
        test_const_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (test_const_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_const_id, 999);
        
        -- Create constants tuple
        test_co_consts_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (test_co_consts_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (test_co_consts_id, ARRAY[test_const_id]);
        
        -- Create bytecode: LOAD_CONST(0) STORE_NAME(0) RETURN_VALUE
        -- Bytecode: [100, 0, 90, 0, 83, 0]
        -- LOAD_CONST = 100, STORE_NAME = 90, RETURN_VALUE = 83
        test_co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (test_co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (test_co_code_id, E'\\x64005a005300'::bytea);
        
        -- Create code object
        test_code_obj_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (test_code_obj_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_code_object (
            ob_base, co_code, co_consts, co_names, co_filename, co_name,
            co_argcount, co_varnames, co_cellvars, co_freevars
        ) VALUES (
            test_code_obj_id, test_co_code_id, test_co_consts_id, co_names_id, empty_str_id, empty_str_id,
            0, empty_tuple_id, empty_tuple_id, empty_tuple_id
        );
        
        -- Create new locals dict for this test
        DECLARE
            test_locals_dict_id UUID;
        BEGIN
            test_locals_dict_id := gen_random_uuid();
            INSERT INTO public.py_object (id, ob_type) VALUES (test_locals_dict_id, ID_DICT_TYPE);
            INSERT INTO public.py_dict_object (ob_base) VALUES (test_locals_dict_id);
            
            -- Create frame
            test_frame_id := gen_random_uuid();
            INSERT INTO public.py_object (id, ob_type) VALUES (test_frame_id, ID_OBJECT_TYPE);
            INSERT INTO public.py_frame_object (
                ob_base, f_code, f_globals, f_locals, f_builtins
            ) VALUES (
                test_frame_id, test_code_obj_id, globals_dict_id, test_locals_dict_id, builtins_dict_id
            );
            
            -- Execute frame
            -- Note: This will fail because RETURN_VALUE needs a value on stack,
            -- but STORE_NAME pops it. This is expected behavior.
            -- We'll test that STORE_NAME worked by checking locals dict
            error_occurred := FALSE;
            BEGIN
                PERFORM public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, test_frame_id);
                error_occurred := FALSE;
            EXCEPTION
                WHEN OTHERS THEN
                    error_occurred := TRUE;
                    error_message := SQLERRM;
            END;
            
            -- Verify STORE_NAME executed (value should be in locals)
            SELECT me_value INTO stored_value_id
            FROM public.py_dict_entry
            WHERE dict_id = test_locals_dict_id
            AND me_key = name0_str_id;
            
            IF stored_value_id != test_const_id THEN
                RAISE EXCEPTION 'FAIL: Value not stored in locals dict after py_eval_frame. Got %, expected %', stored_value_id, test_const_id;
            END IF;
            
            -- Verify RETURN_VALUE error occurred (expected, since stack is empty)
            IF NOT error_occurred THEN
                RAISE EXCEPTION 'FAIL: Expected error from RETURN_VALUE with empty stack';
            END IF;
        END;
    END;
    
    RAISE NOTICE '  ✓ STORE_NAME works correctly with py_eval_frame';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Summary
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
        RAISE EXCEPTION 'Some tests failed. See details above.';
    END IF;
    
    RAISE NOTICE '✅ All STORE_NAME opcode tests passed!';
    
END $$;
