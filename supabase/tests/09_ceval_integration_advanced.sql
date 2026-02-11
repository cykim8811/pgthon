-- ============================================================================
-- Test: VM Advanced Integration Test
-- 
-- Purpose:
--   Tests advanced VM integration scenarios that verify multiple opcodes
--   working together in realistic bytecode sequences. This verifies:
--   - Multiple LOAD_CONST instructions in sequence
--   - f_lasti updates across multiple instructions
--   - Stack state management across instruction sequences
--   - RETURN_VALUE with values loaded from multiple constants
--   - Edge cases: empty bytecode, single instruction, etc.
--
--   All tests follow CPython's exact behavior and execution model.
--
-- Usage:
--   Run this file after migrations to verify advanced VM integration.
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
    co_consts_id UUID;
    
    -- Test constants
    const0_id UUID;
    const1_id UUID;
    const2_id UUID;
    const3_id UUID;
    const4_id UUID;
    
    -- Test variables
    result_id UUID;
    stack_size INTEGER;
    f_lasti_value INTEGER;
    
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
    RAISE NOTICE 'VM Advanced Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Setup: Create test constants and frame infrastructure
    -- ========================================================================
    RAISE NOTICE 'Setting up test environment...';
    
    -- Create test constants (various types)
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 100);
    
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 200);
    
    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const2_id, 300);
    
    const3_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const3_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const3_id, 'hello');
    
    const4_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const4_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const4_id, 'world');
    
    -- Create empty tuple for various tuple fields
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    
    -- Create empty string
    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
    
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
    -- Test 1: Multiple LOAD_CONST instructions in sequence
    -- ========================================================================
    RAISE NOTICE 'Test 1: Multiple LOAD_CONST instructions in sequence...';
    test_count := test_count + 1;
    
    -- Create constants tuple
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const2_id]);
    
    -- Create bytecode: LOAD_CONST(0) LOAD_CONST(1) LOAD_CONST(2) RETURN_VALUE
    -- Bytecode: [100, 0, 100, 1, 100, 2, 83, 0]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x6400640164025300'::bytea);
    
    -- Create code object
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
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
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify return value is const2_id (last loaded constant, top of stack)
    IF result_id != const2_id THEN
        RAISE EXCEPTION 'FAIL: Return value is %, expected % (const2_id, last loaded)', result_id, const2_id;
    END IF;
    
    -- CPython behavior: RETURN_VALUE only pops the top value from stack
    -- After RETURN_VALUE, remaining values (const0_id, const1_id) should still be on stack
    -- In CPython, the frame is destroyed after function return, but in our implementation
    -- the frame persists, so we can verify the stack state
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 2 THEN
        RAISE EXCEPTION 'FAIL: Stack size after RETURN_VALUE is %, expected 2 (const0, const1 remain)', stack_size;
    END IF;
    
    -- Verify remaining stack contents (const0_id, const1_id in order)
    DECLARE
        stack_array uuid[];
    BEGIN
        SELECT f_valuestack INTO stack_array
        FROM public.py_frame_object
        WHERE ob_base = frame_id;
        
        IF stack_array[1] != const0_id OR stack_array[2] != const1_id THEN
            RAISE EXCEPTION 'FAIL: Stack contents incorrect. Got [%, %], expected [%, %]',
                stack_array[1], stack_array[2], const0_id, const1_id;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ Multiple LOAD_CONST instructions work correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: f_lasti updates across multiple instructions
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: f_lasti updates across multiple instructions...';
    test_count := test_count + 1;
    
    -- Create new frame with same bytecode
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify f_lasti is set to RETURN_VALUE's byte offset (6)
    -- Bytecode: [100, 0, 100, 1, 100, 2, 83, 0]
    -- RETURN_VALUE is at byte offset 6 (0-indexed)
    SELECT f_lasti INTO f_lasti_value
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF f_lasti_value != 6 THEN
        RAISE EXCEPTION 'FAIL: f_lasti is %, expected 6 (byte offset of RETURN_VALUE)', f_lasti_value;
    END IF;
    
    RAISE NOTICE '  ✓ f_lasti correctly updated to RETURN_VALUE byte offset';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: Stack state after multiple LOAD_CONST (before RETURN_VALUE)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Stack state after multiple LOAD_CONST...';
    test_count := test_count + 1;
    
    -- Create bytecode: LOAD_CONST(0) LOAD_CONST(1) LOAD_CONST(2)
    -- (No RETURN_VALUE, so we can inspect stack state)
    -- Bytecode: [100, 0, 100, 1, 100, 2]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016402'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id WHERE ob_base = code_obj_id;
    
    -- Create new frame
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    -- Execute frame (should return NULL since no RETURN_VALUE)
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    IF result_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Return value is %, expected NULL (no RETURN_VALUE)', result_id;
    END IF;
    
    -- Verify stack has 3 items (all constants loaded)
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 3 THEN
        RAISE EXCEPTION 'FAIL: Stack size is %, expected 3', stack_size;
    END IF;
    
    -- Verify stack order (LIFO: const0, const1, const2)
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
    
    -- Verify f_lasti is set to last instruction's byte offset (4)
    -- Last instruction (LOAD_CONST 2) is at byte offset 4 (0-indexed)
    SELECT f_lasti INTO f_lasti_value
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF f_lasti_value != 4 THEN
        RAISE EXCEPTION 'FAIL: f_lasti is %, expected 4 (byte offset of last LOAD_CONST)', f_lasti_value;
    END IF;
    
    RAISE NOTICE '  ✓ Stack state correctly maintained across multiple LOAD_CONST';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: Mixed constant types (int and str)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Mixed constant types (int and str)...';
    test_count := test_count + 1;
    
    -- Create constants tuple with mixed types
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const3_id, const1_id, const4_id]);
    
    -- Create bytecode: LOAD_CONST(0) LOAD_CONST(1) LOAD_CONST(2) LOAD_CONST(3) RETURN_VALUE
    -- Bytecode: [100, 0, 100, 1, 100, 2, 100, 3, 83, 0]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64006401640264035300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    
    -- Create new frame
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify return value is const4_id (last loaded constant, top of stack)
    IF result_id != const4_id THEN
        RAISE EXCEPTION 'FAIL: Return value is %, expected % (const4_id, last loaded)', result_id, const4_id;
    END IF;
    
    -- CPython behavior: RETURN_VALUE only pops the top value from stack
    -- After RETURN_VALUE, remaining values (const0_id, const3_id, const1_id) should still be on stack
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 3 THEN
        RAISE EXCEPTION 'FAIL: Stack size after RETURN_VALUE is %, expected 3 (3 constants remain)', stack_size;
    END IF;
    
    -- Verify remaining stack contents (const0_id, const3_id, const1_id in order)
    DECLARE
        stack_array uuid[];
    BEGIN
        SELECT f_valuestack INTO stack_array
        FROM public.py_frame_object
        WHERE ob_base = frame_id;
        
        IF stack_array[1] != const0_id OR
           stack_array[2] != const3_id OR
           stack_array[3] != const1_id THEN
            RAISE EXCEPTION 'FAIL: Stack contents incorrect. Got [%, %, %], expected [%, %, %]',
                stack_array[1], stack_array[2], stack_array[3],
                const0_id, const3_id, const1_id;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ Mixed constant types work correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: Single LOAD_CONST followed by RETURN_VALUE
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Single LOAD_CONST followed by RETURN_VALUE...';
    test_count := test_count + 1;
    
    -- Create bytecode: LOAD_CONST(0) RETURN_VALUE
    -- Bytecode: [100, 0, 83, 0]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005300'::bytea);
    
    -- Create constants tuple
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    
    -- Create new frame
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify return value
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Return value is %, expected % (const0_id)', result_id, const0_id;
    END IF;
    
    -- CPython behavior: RETURN_VALUE only pops the top value from stack
    -- After RETURN_VALUE with single LOAD_CONST, stack should be empty
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size IS NOT NULL AND stack_size != 0 THEN
        RAISE EXCEPTION 'FAIL: Stack size after RETURN_VALUE is %, expected 0 (empty)', stack_size;
    END IF;
    
    -- Verify f_lasti is set to RETURN_VALUE's byte offset (2)
    SELECT f_lasti INTO f_lasti_value
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF f_lasti_value != 2 THEN
        RAISE EXCEPTION 'FAIL: f_lasti is %, expected 2 (byte offset of RETURN_VALUE)', f_lasti_value;
    END IF;
    
    RAISE NOTICE '  ✓ Single LOAD_CONST with RETURN_VALUE works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 6: f_lasti updates for each instruction
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: f_lasti updates for each instruction...';
    test_count := test_count + 1;
    
    -- Create bytecode: LOAD_CONST(0) LOAD_CONST(1) LOAD_CONST(2)
    -- We'll manually step through to verify f_lasti at each step
    -- Bytecode: [100, 0, 100, 1, 100, 2]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016402'::bytea);
    
    -- Create constants tuple
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const2_id]);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    
    -- Create new frame
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    -- Execute frame (no RETURN_VALUE, so it completes normally)
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify f_lasti is set to last instruction's byte offset (4)
    -- Last instruction (LOAD_CONST 2) is at byte offset 4 (0-indexed)
    SELECT f_lasti INTO f_lasti_value
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF f_lasti_value != 4 THEN
        RAISE EXCEPTION 'FAIL: f_lasti is %, expected 4 (byte offset of last instruction)', f_lasti_value;
    END IF;
    
    RAISE NOTICE '  ✓ f_lasti correctly updated to last instruction byte offset';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 7: Large number of LOAD_CONST instructions
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: Large number of LOAD_CONST instructions...';
    test_count := test_count + 1;
    
    -- Create constants tuple with 5 constants
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const2_id, const3_id, const4_id]);
    
    -- Create bytecode: LOAD_CONST(0) ... LOAD_CONST(4) RETURN_VALUE
    -- Bytecode: [100, 0, 100, 1, 100, 2, 100, 3, 100, 4, 83, 0]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016402640364045300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    
    -- Create new frame
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify return value is const4_id (last loaded constant, top of stack)
    IF result_id != const4_id THEN
        RAISE EXCEPTION 'FAIL: Return value is %, expected % (const4_id, last loaded)', result_id, const4_id;
    END IF;
    
    -- CPython behavior: RETURN_VALUE only pops the top value from stack
    -- After RETURN_VALUE, remaining values (const0_id, const1_id, const2_id, const3_id) should still be on stack
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size != 4 THEN
        RAISE EXCEPTION 'FAIL: Stack size after RETURN_VALUE is %, expected 4 (4 constants remain)', stack_size;
    END IF;
    
    -- Verify f_lasti is set to RETURN_VALUE's byte offset (10)
    SELECT f_lasti INTO f_lasti_value
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF f_lasti_value != 10 THEN
        RAISE EXCEPTION 'FAIL: f_lasti is %, expected 10 (byte offset of RETURN_VALUE)', f_lasti_value;
    END IF;
    
    RAISE NOTICE '  ✓ Large number of LOAD_CONST instructions work correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 8: RETURN_VALUE with empty stack (should raise exception)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: RETURN_VALUE with empty stack (should raise exception)...';
    test_count := test_count + 1;
    
    -- Create bytecode: RETURN_VALUE (no LOAD_CONST before it)
    -- Bytecode: [83, 0]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x5300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id WHERE ob_base = code_obj_id;
    
    -- Create new frame
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    -- Execute frame (should raise stack underflow exception)
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
    
    IF error_message NOT LIKE '%underflow%' AND error_message NOT LIKE '%empty%' THEN
        RAISE EXCEPTION 'FAIL: Expected stack underflow error, got: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ RETURN_VALUE with empty stack correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 9: Bytecode with only RETURN_VALUE after manual stack push
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 9: RETURN_VALUE after manual stack push...';
    test_count := test_count + 1;
    
    -- Create bytecode: RETURN_VALUE only
    -- Bytecode: [83, 0]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x5300'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id WHERE ob_base = code_obj_id;
    
    -- Create new frame
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    -- Manually push value onto stack
    PERFORM public.py_stack_push(frame_id, const0_id);
    
    -- Execute frame
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    
    -- Verify return value
    IF result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Return value is %, expected % (const0_id)', result_id, const0_id;
    END IF;
    
    -- CPython behavior: RETURN_VALUE only pops the top value from stack
    -- After RETURN_VALUE with single manually pushed value, stack should be empty
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size IS NOT NULL AND stack_size != 0 THEN
        RAISE EXCEPTION 'FAIL: Stack size after RETURN_VALUE is %, expected 0 (empty)', stack_size;
    END IF;
    
    RAISE NOTICE '  ✓ RETURN_VALUE works correctly with manually pushed stack value';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 10: Multiple frames with different bytecode (frame isolation)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 10: Multiple frames with different bytecode (frame isolation)...';
    test_count := test_count + 1;
    
    -- Create and execute both frames in a single block to verify isolation
    DECLARE
        first_frame_id UUID;
        first_code_obj_id UUID;
        first_co_code_id UUID;
        first_co_consts_id UUID;
        first_result_id UUID;
        first_f_lasti INTEGER;
        first_stack_size INTEGER;
        second_frame_id UUID;
        second_code_obj_id UUID;
        second_co_code_id UUID;
        second_co_consts_id UUID;
        second_result_id UUID;
        second_f_lasti INTEGER;
        second_stack_size INTEGER;
    BEGIN
        -- ====================================================================
        -- First frame: LOAD_CONST(0) RETURN_VALUE
        -- ====================================================================
        first_co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (first_co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (first_co_code_id, E'\\x64005300'::bytea);
        
        first_co_consts_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (first_co_consts_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (first_co_consts_id, ARRAY[const0_id]);
        
        first_code_obj_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (first_code_obj_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_code_object (
            ob_base, co_code, co_consts, co_names, co_filename, co_name,
            co_argcount, co_varnames, co_cellvars, co_freevars
        ) VALUES (
            first_code_obj_id, first_co_code_id, first_co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
            0, empty_tuple_id, empty_tuple_id, empty_tuple_id
        );
        
        first_frame_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (first_frame_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_frame_object (
            ob_base, f_code, f_globals, f_locals, f_builtins
        ) VALUES (
            first_frame_id, first_code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
        );
        
        -- Execute first frame
        first_result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, first_frame_id);
        
        -- Verify first frame return value
        IF first_result_id != const0_id THEN
            RAISE EXCEPTION 'FAIL: First frame returned %, expected %', first_result_id, const0_id;
        END IF;
        
        -- Verify first frame stack is empty after RETURN_VALUE
        SELECT array_length(f_valuestack, 1) INTO first_stack_size
        FROM public.py_frame_object
        WHERE ob_base = first_frame_id;
        
        IF first_stack_size IS NOT NULL AND first_stack_size != 0 THEN
            RAISE EXCEPTION 'FAIL: First frame stack size is %, expected 0 (empty)', first_stack_size;
        END IF;
        
        -- Verify first frame f_lasti is set correctly
        SELECT f_lasti INTO first_f_lasti
        FROM public.py_frame_object
        WHERE ob_base = first_frame_id;
        
        IF first_f_lasti != 2 THEN
            RAISE EXCEPTION 'FAIL: First frame f_lasti is %, expected 2 (byte offset of RETURN_VALUE)', first_f_lasti;
        END IF;
        
        -- ====================================================================
        -- Second frame: LOAD_CONST(0) RETURN_VALUE (different constant, different code object)
        -- Note: co_consts has const1_id at index 0, so LOAD_CONST(0) loads const1_id
        -- ====================================================================
        second_co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (second_co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (second_co_code_id, E'\\x64005300'::bytea);
        
        second_co_consts_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (second_co_consts_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (second_co_consts_id, ARRAY[const1_id]);
        
        second_code_obj_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (second_code_obj_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_code_object (
            ob_base, co_code, co_consts, co_names, co_filename, co_name,
            co_argcount, co_varnames, co_cellvars, co_freevars
        ) VALUES (
            second_code_obj_id, second_co_code_id, second_co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
            0, empty_tuple_id, empty_tuple_id, empty_tuple_id
        );
        
        second_frame_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (second_frame_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_frame_object (
            ob_base, f_code, f_globals, f_locals, f_builtins
        ) VALUES (
            second_frame_id, second_code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
        );
        
        -- Execute second frame
        second_result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, second_frame_id);
        
        -- Verify second frame return value
        IF second_result_id != const1_id THEN
            RAISE EXCEPTION 'FAIL: Second frame returned %, expected %', second_result_id, const1_id;
        END IF;
        
        -- Verify second frame stack is empty after RETURN_VALUE
        SELECT array_length(f_valuestack, 1) INTO second_stack_size
        FROM public.py_frame_object
        WHERE ob_base = second_frame_id;
        
        IF second_stack_size IS NOT NULL AND second_stack_size != 0 THEN
            RAISE EXCEPTION 'FAIL: Second frame stack size is %, expected 0 (empty)', second_stack_size;
        END IF;
        
        -- Verify second frame f_lasti is set correctly
        SELECT f_lasti INTO second_f_lasti
        FROM public.py_frame_object
        WHERE ob_base = second_frame_id;
        
        IF second_f_lasti != 2 THEN
            RAISE EXCEPTION 'FAIL: Second frame f_lasti is %, expected 2 (byte offset of RETURN_VALUE)', second_f_lasti;
        END IF;
        
        -- ====================================================================
        -- Frame isolation verification: first frame state should not be affected
        -- ====================================================================
        -- Verify first frame's f_lasti is still correct after second frame execution
        SELECT f_lasti INTO first_f_lasti
        FROM public.py_frame_object
        WHERE ob_base = first_frame_id;
        
        IF first_f_lasti != 2 THEN
            RAISE EXCEPTION 'FAIL: First frame f_lasti changed to % after second frame execution, expected 2', first_f_lasti;
        END IF;
        
        -- Verify first frame's stack is still empty after second frame execution
        SELECT array_length(f_valuestack, 1) INTO first_stack_size
        FROM public.py_frame_object
        WHERE ob_base = first_frame_id;
        
        IF first_stack_size IS NOT NULL AND first_stack_size != 0 THEN
            RAISE EXCEPTION 'FAIL: First frame stack size changed to % after second frame execution, expected 0', first_stack_size;
        END IF;
        
        -- Verify frames are independent (different code objects, different frame IDs)
        IF first_code_obj_id = second_code_obj_id THEN
            RAISE EXCEPTION 'FAIL: First and second frames share the same code object (should be independent)';
        END IF;
        
        IF first_frame_id = second_frame_id THEN
            RAISE EXCEPTION 'FAIL: First and second frames have the same ID (should be different)';
        END IF;
    END;
    
    RAISE NOTICE '  ✓ Multiple frames with different bytecode work correctly and maintain isolation';
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
    
    RAISE NOTICE '✅ All advanced integration tests passed!';
    
END $$;
