-- ============================================================================
-- Test: VM Frame Evaluation Test
-- 
-- Purpose:
--   Tests that py_eval_frame function works correctly. This verifies:
--   - Function exists and can be called
--   - Input validation (frame, code object, bytecode existence)
--   - RETURN_VALUE opcode correctly returns value and exits loop
--   - f_lasti is updated correctly
--   - Error handling for invalid inputs
--
--   Note: This test uses minimal opcode handlers. Full opcode implementation
--   tests are in other test files.
--
-- Usage:
--   Run this file after migrations to verify py_eval_frame implementation.
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
    
    -- Test objects
    test_const_id UUID;
    result_id UUID;
    
    -- Helper variables
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    f_lasti_value INTEGER;
    
    -- Error handling
    error_occurred BOOLEAN;
    error_message TEXT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM Frame Evaluation Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Test 1: Function exists
    -- ========================================================================
    RAISE NOTICE 'Test 1: Function exists...';
    test_count := test_count + 1;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'py_eval_frame' 
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) THEN
        RAISE EXCEPTION 'FAIL: py_eval_frame function does not exist';
    END IF;
    
    RAISE NOTICE '  ✓ py_eval_frame function exists';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: Invalid frame ID
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Invalid frame ID...';
    test_count := test_count + 1;
    
    error_occurred := FALSE;
    BEGIN
        result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, gen_random_uuid());
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on invalid frame ID, but none occurred';
    END IF;
    
    IF error_message NOT LIKE '%does not exist%' THEN
        RAISE EXCEPTION 'FAIL: Expected "does not exist" error, got: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ Invalid frame ID correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Setup: Create minimal frame for remaining tests
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Setting up test environment...';
    
    -- Create test constant
    test_const_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (test_const_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (test_const_id, 42);
    
    -- Create empty tuple for various tuple fields
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    
    -- Create empty string
    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
    
    -- Create constants tuple with test constant
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[test_const_id]);
    
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
    -- Test 3: Frame without code object
    -- ========================================================================
    RAISE NOTICE 'Test 3: Frame without code object...';
    test_count := test_count + 1;
    
    -- Create frame with invalid code object (exists in py_object but not in py_code_object)
    DECLARE
        invalid_code_obj_id UUID;
    BEGIN
        invalid_code_obj_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (invalid_code_obj_id, ID_CODE_TYPE);
        -- Note: Not inserting into py_code_object, so it's invalid
        
        frame_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_frame_object (
            ob_base, f_code, f_globals, f_locals, f_builtins
        ) VALUES (
            frame_id, invalid_code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
        );
    END;
    
    error_occurred := FALSE;
    BEGIN
        result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on frame without valid code object';
    END IF;
    
    RAISE NOTICE '  ✓ Frame without code object correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: Empty bytecode (no instructions)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Empty bytecode (no instructions)...';
    test_count := test_count + 1;
    
    -- Create empty bytecode
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
    
    -- Execute (should return NULL since no RETURN_VALUE)
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    IF result_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Empty bytecode should return NULL, got %', result_id;
    END IF;
    
    RAISE NOTICE '  ✓ Empty bytecode correctly returns NULL';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: RETURN_VALUE with empty stack (should raise exception)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: RETURN_VALUE with empty stack...';
    test_count := test_count + 1;
    
    -- Create bytecode with only RETURN_VALUE (no value on stack)
    -- Bytecode: [83, 0] = RETURN_VALUE
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x5300'::bytea);
    
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
    
    error_occurred := FALSE;
    BEGIN
        result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on RETURN_VALUE with empty stack';
    END IF;
    
    IF error_message NOT LIKE '%Stack underflow%' THEN
        RAISE EXCEPTION 'FAIL: Expected "Stack underflow" error, got: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ RETURN_VALUE with empty stack correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 6: RETURN_VALUE with value on stack
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: RETURN_VALUE with value on stack...';
    test_count := test_count + 1;
    
    -- Create bytecode with only RETURN_VALUE
    -- Bytecode: [83, 0] = RETURN_VALUE
    -- Note: We manually push value to stack since LOAD_CONST handler doesn't exist yet
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x5300'::bytea);
    
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
    
    -- Manually push test constant to stack (since LOAD_CONST handler doesn't exist yet)
    PERFORM public.py_stack_push(frame_id, test_const_id);
    
    -- Execute (should handle RETURN_VALUE and return the value)
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    IF result_id != test_const_id THEN
        RAISE EXCEPTION 'FAIL: RETURN_VALUE should return %, got %', test_const_id, result_id;
    END IF;
    
    RAISE NOTICE '  ✓ RETURN_VALUE correctly returns value from stack';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 7: f_lasti is updated correctly
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: f_lasti is updated correctly...';
    test_count := test_count + 1;
    
    -- Create bytecode: RETURN_VALUE at offset 0
    -- Bytecode: [83, 0]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x5300'::bytea);
    
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
    
    -- Push value to stack
    PERFORM public.py_stack_push(frame_id, test_const_id);
    
    -- Execute
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify f_lasti is set to RETURN_VALUE's byte offset (0)
    SELECT f_lasti INTO f_lasti_value
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF f_lasti_value != 0 THEN
        RAISE EXCEPTION 'FAIL: f_lasti is %, expected 0 (byte offset of RETURN_VALUE)', f_lasti_value;
    END IF;
    
    RAISE NOTICE '  ✓ f_lasti correctly updated to byte offset';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 8: Unknown opcode raises exception
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 9: Unknown opcode raises exception...';
    test_count := test_count + 1;
    
    -- Create bytecode with unknown opcode (255)
    -- Bytecode: [255, 0]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\xFF00'::bytea);
    
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
    
    error_occurred := FALSE;
    BEGIN
        result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on unknown opcode';
    END IF;
    
    IF error_message NOT LIKE '%Unknown opcode%' THEN
        RAISE EXCEPTION 'FAIL: Expected "Unknown opcode" error, got: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ Unknown opcode correctly raises exception';
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
    
    RAISE NOTICE '✅ All py_eval_frame tests passed!';
    
END $$;
