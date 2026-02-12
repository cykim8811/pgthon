-- ============================================================================
-- Test: VM Basic Opcodes Test
-- 
-- Purpose:
--   Tests that basic opcode handlers work correctly. This verifies:
--   - py_opcode_LOAD_CONST correctly loads constants from co_consts
--   - Constants are pushed onto the evaluation stack
--   - Index validation works correctly
--   - Integration with py_eval_frame
--
-- Usage:
--   Run this file after migrations to verify basic opcode implementations.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    -- Builtin Type IDs (from bootstrap)
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
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
    co_consts_id UUID;
    
    -- Test constants
    const0_id UUID;
    const1_id UUID;
    const2_id UUID;
    
    -- Test variables
    result_id UUID;
    stack_size INTEGER;
    
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
    RAISE NOTICE 'VM Basic Opcodes Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Setup: Create test constants and frame
    -- ========================================================================
    RAISE NOTICE 'Setting up test environment...';
    
    -- Create test constants
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 10);
    
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 20);
    
    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const2_id, 'hello');
    
    -- Create empty tuple for various tuple fields
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    
    -- Create empty string
    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
    
    -- Create constants tuple (co_consts) with test constants
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const2_id]);
    
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
        WHERE proname = 'py_opcode_load_const' 
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_LOAD_CONST function does not exist';
    END IF;
    
    RAISE NOTICE '  ✓ py_opcode_LOAD_CONST function exists';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: LOAD_CONST loads constant and pushes to stack
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: LOAD_CONST loads constant and pushes to stack...';
    test_count := test_count + 1;
    
    -- Create empty bytecode (not used in this test)
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);
    
    -- Create code object
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
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
    
    -- Execute LOAD_CONST(0)
    PERFORM public.py_opcode_LOAD_CONST(frame_id, 0);
    
    -- Verify stack has one item
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 1 THEN
        RAISE EXCEPTION 'FAIL: Stack size after LOAD_CONST(0) is %, expected 1', stack_size;
    END IF;
    
    -- Verify the value on stack is const0_id
    SELECT f_valuestack[1] INTO result_id
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Stack top is %, expected % (const0_id)', result_id, const0_id;
    END IF;
    
    RAISE NOTICE '  ✓ LOAD_CONST(0) correctly loads constant onto stack';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: LOAD_CONST with different indices
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: LOAD_CONST with different indices...';
    test_count := test_count + 1;
    
    -- Clear stack
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[] WHERE ob_base = frame_id;
    
    -- Load constants in order
    PERFORM public.py_opcode_LOAD_CONST(frame_id, 0);  -- const0_id
    PERFORM public.py_opcode_LOAD_CONST(frame_id, 1);  -- const1_id
    PERFORM public.py_opcode_LOAD_CONST(frame_id, 2);  -- const2_id
    
    -- Verify stack has 3 items
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 3 THEN
        RAISE EXCEPTION 'FAIL: Stack size after 3 LOAD_CONST is %, expected 3', stack_size;
    END IF;
    
    -- Verify stack order (LIFO: last pushed is on top)
    DECLARE
        stack_array uuid[];
    BEGIN
        SELECT f_valuestack INTO stack_array
        FROM public.py_frame_object
        WHERE ob_base = frame_id;
        
        IF stack_array[1] != const0_id OR
           stack_array[2] != const1_id OR
           stack_array[3] != const2_id THEN
            RAISE EXCEPTION 'FAIL: Stack order incorrect. Got [%, %, %], expected [%, %, %]',
                stack_array[1], stack_array[2], stack_array[3],
                const0_id, const1_id, const2_id;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ LOAD_CONST with different indices works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: LOAD_CONST with out-of-range index
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: LOAD_CONST with out-of-range index...';
    test_count := test_count + 1;
    
    error_occurred := FALSE;
    BEGIN
        PERFORM public.py_opcode_LOAD_CONST(frame_id, 999);
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
    
    RAISE NOTICE '  ✓ LOAD_CONST with out-of-range index correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: LOAD_CONST with negative index
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: LOAD_CONST with negative index...';
    test_count := test_count + 1;
    
    error_occurred := FALSE;
    BEGIN
        PERFORM public.py_opcode_LOAD_CONST(frame_id, -1);
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
    
    RAISE NOTICE '  ✓ LOAD_CONST with negative index correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 6: LOAD_CONST integration with py_eval_frame
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: LOAD_CONST integration with py_eval_frame...';
    test_count := test_count + 1;
    
    -- Create bytecode: LOAD_CONST(0) RETURN_VALUE
    -- Bytecode: [100, 0, 83, 0]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005300'::bytea);
    
    -- Update code object with new bytecode
    UPDATE public.py_code_object SET co_code = co_code_id WHERE ob_base = code_obj_id;
    
    -- Create new frame
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    -- Execute frame (should load constant and return it)
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: py_eval_frame returned %, expected % (const0_id)', result_id, const0_id;
    END IF;
    
    RAISE NOTICE '  ✓ LOAD_CONST works correctly with py_eval_frame';
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
    
    RAISE NOTICE '✅ All basic opcode tests passed!';
    
END $$;
