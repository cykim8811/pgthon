-- ============================================================================
-- Test: VM Stack Operations Test
-- 
-- Purpose:
--   Tests that stack operations (push/pop) work correctly. This verifies:
--   - Stack push adds objects to the stack
--   - Stack pop removes objects from the stack in LIFO order
--   - Stack underflow raises exception
--   - Stack operations work with frame objects
--
-- Usage:
--   Run this file after migrations to verify stack operation implementations.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

DO $$
DECLARE
    -- Builtin Type IDs (from bootstrap)
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYPE_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    
    -- Test counters
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    
    -- Test object IDs
    frame_id UUID;
    test_obj1_id UUID;
    test_obj2_id UUID;
    test_obj3_id UUID;
    popped_id UUID;
    
    -- Stack state
    stack_size INTEGER;
    stack_array uuid[];
    
    -- Error handling
    error_occurred BOOLEAN;
    error_message TEXT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM Stack Operations Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Setup: Create a test frame and test objects
    -- ========================================================================
    RAISE NOTICE 'Setting up test environment...';
    
    -- Create test frame object
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    
    -- Create a minimal code object for the frame
    DECLARE
        code_obj_id UUID;
        co_code_id UUID;
        co_consts_id UUID;
        co_names_id UUID;
        co_filename_id UUID;
        co_name_id UUID;
        co_varnames_id UUID;
        co_cellvars_id UUID;
        co_freevars_id UUID;
        empty_tuple_id UUID;
        empty_str_id UUID;
        locals_dict_id UUID;
        globals_dict_id UUID;
        builtins_dict_id UUID;
    BEGIN
        -- Create empty tuple for various tuple fields
        empty_tuple_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
        
        -- Create empty string for filename and name
        empty_str_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
        
        -- Create code object's co_code (empty bytecode)
        co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (co_code_id, '');
        
        -- Set all tuple/string references
        co_consts_id := empty_tuple_id;
        co_names_id := empty_tuple_id;
        co_filename_id := empty_str_id;
        co_name_id := empty_str_id;
        co_varnames_id := empty_tuple_id;
        co_cellvars_id := empty_tuple_id;
        co_freevars_id := empty_tuple_id;
        
        -- Create code object
        code_obj_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_code_object (
            ob_base, co_code, co_consts, co_names, co_filename, co_name,
            co_argcount, co_varnames, co_cellvars, co_freevars
        ) VALUES (
            code_obj_id, co_code_id, co_consts_id, co_names_id, co_filename_id, co_name_id,
            0, co_varnames_id, co_cellvars_id, co_freevars_id
        );
        
        -- Create empty dicts for namespaces
        locals_dict_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
        INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
        
        globals_dict_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
        INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
        
        builtins_dict_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
        INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);
        
        -- Create frame object
        INSERT INTO public.py_frame_object (
            ob_base, f_code, f_globals, f_locals, f_builtins
        ) VALUES (
            frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
        );
    END;
    
    -- Create test objects
    test_obj1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_obj1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_obj1_id, 1);
    
    test_obj2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_obj2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_obj2_id, 2);
    
    test_obj3_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_obj3_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_obj3_id, 3);
    
    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Test 1: Push single object
    -- ========================================================================
    RAISE NOTICE 'Test 1: Push single object onto stack...';
    test_count := test_count + 1;
    
    PERFORM public.py_stack_push(frame_id, test_obj1_id);
    
    -- Verify stack size
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 1 THEN
        RAISE EXCEPTION 'FAIL: Stack size is %, expected 1', stack_size;
    END IF;
    
    -- Verify stack content
    SELECT f_valuestack INTO stack_array
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_array[1] != test_obj1_id THEN
        RAISE EXCEPTION 'FAIL: Stack top is %, expected %', stack_array[1], test_obj1_id;
    END IF;
    
    RAISE NOTICE '  ✓ Single push works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: Push multiple objects (LIFO order)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Push multiple objects (verify LIFO order)...';
    test_count := test_count + 1;
    
    PERFORM public.py_stack_push(frame_id, test_obj2_id);
    PERFORM public.py_stack_push(frame_id, test_obj3_id);
    
    -- Verify stack size
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 3 THEN
        RAISE EXCEPTION 'FAIL: Stack size is %, expected 3', stack_size;
    END IF;
    
    -- Verify stack order (LIFO: last in, first out)
    SELECT f_valuestack INTO stack_array
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_array[1] != test_obj1_id OR
       stack_array[2] != test_obj2_id OR
       stack_array[3] != test_obj3_id THEN
        RAISE EXCEPTION 'FAIL: Stack order incorrect. Got [%, %, %], expected [%, %, %]',
            stack_array[1], stack_array[2], stack_array[3],
            test_obj1_id, test_obj2_id, test_obj3_id;
    END IF;
    
    RAISE NOTICE '  ✓ Multiple push works correctly (LIFO order maintained)';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: Pop single object (LIFO order)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Pop single object (verify LIFO order)...';
    test_count := test_count + 1;
    
    popped_id := public.py_stack_pop(frame_id);
    
    IF popped_id != test_obj3_id THEN
        RAISE EXCEPTION 'FAIL: Popped object is %, expected %', popped_id, test_obj3_id;
    END IF;
    
    -- Verify stack size
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 2 THEN
        RAISE EXCEPTION 'FAIL: Stack size is %, expected 2', stack_size;
    END IF;
    
    RAISE NOTICE '  ✓ Pop works correctly (LIFO: last pushed object popped first)';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: Pop all objects (verify order)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Pop all remaining objects (verify order)...';
    test_count := test_count + 1;
    
    popped_id := public.py_stack_pop(frame_id);
    IF popped_id != test_obj2_id THEN
        RAISE EXCEPTION 'FAIL: Popped object is %, expected %', popped_id, test_obj2_id;
    END IF;
    
    popped_id := public.py_stack_pop(frame_id);
    IF popped_id != test_obj1_id THEN
        RAISE EXCEPTION 'FAIL: Popped object is %, expected %', popped_id, test_obj1_id;
    END IF;
    
    -- Verify stack is empty
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size IS NOT NULL AND stack_size != 0 THEN
        RAISE EXCEPTION 'FAIL: Stack is not empty, size is %', stack_size;
    END IF;
    
    RAISE NOTICE '  ✓ All objects popped in correct order (LIFO)';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: Stack underflow (pop from empty stack)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Stack underflow (pop from empty stack)...';
    test_count := test_count + 1;
    
    error_occurred := FALSE;
    BEGIN
        popped_id := public.py_stack_pop(frame_id);
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on pop from empty stack, but none occurred';
    END IF;
    
    IF error_message NOT LIKE '%Stack underflow%' THEN
        RAISE EXCEPTION 'FAIL: Expected "Stack underflow" error, got: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ Stack underflow correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 6: Push after underflow (recovery)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: Push after underflow (verify recovery)...';
    test_count := test_count + 1;
    
    PERFORM public.py_stack_push(frame_id, test_obj1_id);
    
    -- Verify stack works again
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 1 THEN
        RAISE EXCEPTION 'FAIL: Stack size is %, expected 1 after recovery', stack_size;
    END IF;
    
    popped_id := public.py_stack_pop(frame_id);
    IF popped_id != test_obj1_id THEN
        RAISE EXCEPTION 'FAIL: Popped object is %, expected %', popped_id, test_obj1_id;
    END IF;
    
    RAISE NOTICE '  ✓ Stack recovery works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 7: Invalid frame ID
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: Invalid frame ID (push)...';
    test_count := test_count + 1;
    
    error_occurred := FALSE;
    BEGIN
        PERFORM public.py_stack_push(gen_random_uuid(), test_obj1_id);
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on push with invalid frame ID';
    END IF;
    
    RAISE NOTICE '  ✓ Invalid frame ID correctly raises exception (push)';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 8: Invalid object ID
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: Invalid object ID (push)...';
    test_count := test_count + 1;
    
    error_occurred := FALSE;
    BEGIN
        PERFORM public.py_stack_push(frame_id, gen_random_uuid());
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on push with invalid object ID';
    END IF;
    
    RAISE NOTICE '  ✓ Invalid object ID correctly raises exception (push)';
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
    
    RAISE NOTICE '✅ All stack operation tests passed!';
    
END $$;
