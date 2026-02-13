-- ============================================================================
-- Test: VM Integration Test
-- 
-- Purpose:
--   Tests that VM core components work together correctly. This verifies:
--   - Frame creation with code objects
--   - Bytecode reading and parsing
--   - Opcode size calculation for bytecode navigation
--   - Stack operations during simulated bytecode execution
--   - Integration of stack operations and opcode utilities
--
--   This test simulates a simple bytecode execution scenario:
--   1. Create a frame with bytecode
--   2. Read bytecode and calculate instruction sizes
--   3. Simulate opcode execution by manipulating the stack
--   4. Verify the execution flow matches expected behavior
--
-- Usage:
--   Run this file after migrations to verify VM core integration.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

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
    
    -- Bytecode parsing
    i INTEGER;
    opcode INTEGER;
    operand INTEGER;
    instruction_size INTEGER;
    bytecode_length INTEGER;
    
    -- Stack simulation
    const1_id UUID;
    const2_id UUID;
    result_id UUID;
    stack_size INTEGER;
    
    -- Helper variables
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Setup: Create frame with bytecode
    -- ========================================================================
    RAISE NOTICE 'Setting up test environment...';
    
    -- Create test constants (will be pushed onto stack)
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 42);
    
    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const2_id, 10);
    
    -- Create empty tuple for various tuple fields
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    
    -- Create empty string
    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
    
    -- Create constants tuple (co_consts) with our test constants
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const1_id, const2_id]);
    
    -- Create bytecode (bytes object)
    -- Simulated bytecode: LOAD_CONST(0) LOAD_CONST(1) BINARY_ADD RETURN_VALUE
    -- LOAD_CONST = 100, operand = 0 (const1_id)
    -- LOAD_CONST = 100, operand = 1 (const2_id)
    -- BINARY_ADD = 23, operand = 0 (unused)
    -- RETURN_VALUE = 83, operand = 0 (unused)
    -- Each instruction is 2 bytes: opcode (1 byte) + operand (1 byte)
    -- Bytecode: [100, 0, 100, 1, 23, 0, 83, 0]
    -- Use bytea to store binary data (can include NULL bytes)
    DECLARE
        bytecode_bytes bytea;
    BEGIN
        bytecode_bytes := E'\\x6400640117005300';  -- Hex encoding: 100,0,100,1,23,0,83,0 (23 decimal = 0x17 hex)
        
        co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, bytecode_bytes);
    END;
    
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
    
    -- Create frame object
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Test 1: Bytecode reading and opcode size calculation
    -- ========================================================================
    RAISE NOTICE 'Test 1: Bytecode reading and opcode size calculation...';
    test_count := test_count + 1;
    
    -- Get bytecode from code object (bytes object)
    DECLARE
        bytecode_bytes bytea;
    BEGIN
        SELECT bytes_value INTO bytecode_bytes
        FROM public.py_bytes_object
        WHERE ob_base = co_code_id;
        
        -- Convert bytea to text for length calculation (length works on bytea)
        bytecode_length := length(bytecode_bytes);
    IF bytecode_length != 8 THEN
        RAISE EXCEPTION 'FAIL: Bytecode length is %, expected 8', bytecode_length;
    END IF;
    
        -- Parse first instruction: LOAD_CONST (opcode 100, operand 0)
        i := 1;
        -- Get byte value using get_byte (bytea is 1-indexed)
        opcode := get_byte(bytecode_bytes, i - 1);
        IF opcode != 100 THEN
            RAISE EXCEPTION 'FAIL: First opcode is %, expected 100 (LOAD_CONST)', opcode;
        END IF;
        
        instruction_size := public.py_get_opcode_size(opcode);
        IF instruction_size != 2 THEN
            RAISE EXCEPTION 'FAIL: LOAD_CONST instruction size is %, expected 2', instruction_size;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ Bytecode reading and opcode size calculation works';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: Simulated bytecode execution - LOAD_CONST instructions
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Simulated execution - LOAD_CONST instructions...';
    test_count := test_count + 1;
    
    -- Get bytecode bytes
    DECLARE
        bytecode_bytes bytea;
    BEGIN
        SELECT bytes_value INTO bytecode_bytes
        FROM public.py_bytes_object
        WHERE ob_base = co_code_id;
        
        -- Simulate: LOAD_CONST 0 (push const1_id onto stack)
        i := 1;
        opcode := get_byte(bytecode_bytes, i - 1);
        operand := get_byte(bytecode_bytes, i);
        
        IF opcode != 100 OR operand != 0 THEN
            RAISE EXCEPTION 'FAIL: First instruction is not LOAD_CONST 0 (expected opcode 100, operand 0, got opcode %, operand %)', opcode, operand;
        END IF;
        
        -- Simulate pushing constant onto stack
        PERFORM public.py_stack_push(frame_id, const1_id);
        
        -- Verify stack
        SELECT array_length(f_valuestack, 1) INTO stack_size
        FROM public.py_frame_object
        WHERE ob_base = frame_id;
        
        IF stack_size != 1 THEN
            RAISE EXCEPTION 'FAIL: Stack size after LOAD_CONST 0 is %, expected 1', stack_size;
        END IF;
    
        -- Simulate: LOAD_CONST 1 (push const2_id onto stack)
        i := i + public.py_get_opcode_size(opcode);  -- Move to next instruction
        opcode := get_byte(bytecode_bytes, i - 1);
        operand := get_byte(bytecode_bytes, i);
        
        IF opcode != 100 OR operand != 1 THEN
            RAISE EXCEPTION 'FAIL: Second instruction is not LOAD_CONST 1 (expected opcode 100, operand 1, got opcode %, operand %)', opcode, operand;
        END IF;
        
        -- Simulate pushing second constant onto stack
        PERFORM public.py_stack_push(frame_id, const2_id);
        
        -- Verify stack
        SELECT array_length(f_valuestack, 1) INTO stack_size
        FROM public.py_frame_object
        WHERE ob_base = frame_id;
        
        IF stack_size != 2 THEN
            RAISE EXCEPTION 'FAIL: Stack size after LOAD_CONST 1 is %, expected 2', stack_size;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ LOAD_CONST instructions correctly push constants onto stack';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: Simulated bytecode execution - BINARY_ADD
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Simulated execution - BINARY_ADD...';
    test_count := test_count + 1;
    
    -- Simulate: BINARY_ADD (pop 2 values, add them, push result)
    DECLARE
        bytecode_bytes bytea;
    BEGIN
        SELECT bytes_value INTO bytecode_bytes
        FROM public.py_bytes_object
        WHERE ob_base = co_code_id;
        
        -- Calculate current position (after 2 LOAD_CONST instructions = 4 bytes)
        -- BINARY_ADD is at byte offset 4 (0-indexed) = position 5 (1-indexed)
        i := 5;  -- Position of BINARY_ADD instruction
        opcode := get_byte(bytecode_bytes, i - 1);  -- get_byte uses 0-indexed
        operand := get_byte(bytecode_bytes, i);
        
        IF opcode != 23 THEN
            RAISE EXCEPTION 'FAIL: Third instruction is not BINARY_ADD (23), got %', opcode;
        END IF;
        
        instruction_size := public.py_get_opcode_size(opcode);
        IF instruction_size != 2 THEN
            RAISE EXCEPTION 'FAIL: BINARY_ADD instruction size is %, expected 2', instruction_size;
        END IF;
        
        -- Simulate BINARY_ADD: pop two values (we'll just verify the stack has 2 items)
        -- In real implementation, we'd pop, add, and push result
        -- For now, just verify we can pop both values
        result_id := public.py_stack_pop(frame_id);  -- Pop const2_id
        IF result_id != const2_id THEN
            RAISE EXCEPTION 'FAIL: Popped value is not const2_id';
        END IF;
        
        result_id := public.py_stack_pop(frame_id);  -- Pop const1_id
        IF result_id != const1_id THEN
            RAISE EXCEPTION 'FAIL: Popped value is not const1_id';
        END IF;
        
        -- In real BINARY_ADD, we'd create result and push it
        -- For this test, we'll just push a placeholder to simulate the result
        PERFORM public.py_stack_push(frame_id, const1_id);  -- Simulate result
    END;
    
    RAISE NOTICE '  ✓ BINARY_ADD stack manipulation works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: Simulated bytecode execution - RETURN_VALUE
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Simulated execution - RETURN_VALUE...';
    test_count := test_count + 1;
    
    -- Simulate: RETURN_VALUE (pop value from stack and return)
    DECLARE
        bytecode_bytes bytea;
    BEGIN
        SELECT bytes_value INTO bytecode_bytes
        FROM public.py_bytes_object
        WHERE ob_base = co_code_id;
        
        -- RETURN_VALUE is at byte offset 6 (0-indexed) = position 7 (1-indexed)
        i := 7;  -- Position of RETURN_VALUE instruction
        opcode := get_byte(bytecode_bytes, i - 1);
        operand := get_byte(bytecode_bytes, i);
        
        IF opcode != 83 THEN
            RAISE EXCEPTION 'FAIL: Fourth instruction is not RETURN_VALUE (83), got %', opcode;
        END IF;
        
        instruction_size := public.py_get_opcode_size(opcode);
        IF instruction_size != 2 THEN
            RAISE EXCEPTION 'FAIL: RETURN_VALUE instruction size is %, expected 2', instruction_size;
        END IF;
        
        -- Simulate RETURN_VALUE: pop value from stack
        result_id := public.py_stack_pop(frame_id);
        
        -- Verify stack is empty
        SELECT array_length(f_valuestack, 1) INTO stack_size
        FROM public.py_frame_object
        WHERE ob_base = frame_id;
        
        IF stack_size IS NOT NULL AND stack_size != 0 THEN
            RAISE EXCEPTION 'FAIL: Stack is not empty after RETURN_VALUE, size is %', stack_size;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ RETURN_VALUE correctly pops value from stack';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: Bytecode navigation using opcode sizes
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Bytecode navigation using opcode sizes...';
    test_count := test_count + 1;
    
    -- Verify we can navigate through all instructions correctly
    DECLARE
        bytecode_bytes bytea;
    BEGIN
        SELECT bytes_value INTO bytecode_bytes
        FROM public.py_bytes_object
        WHERE ob_base = co_code_id;
        
        bytecode_length := length(bytecode_bytes);
        i := 1;
        instruction_size := 0;
        
        WHILE i <= bytecode_length LOOP
            opcode := get_byte(bytecode_bytes, i - 1);
            instruction_size := public.py_get_opcode_size(opcode);
            i := i + instruction_size;
        END LOOP;
        
        -- After processing all instructions, i should be at bytecode_length + 1
        IF i != bytecode_length + 1 THEN
            RAISE EXCEPTION 'FAIL: Bytecode navigation ended at position %, expected %', i, bytecode_length + 1;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ Bytecode navigation works correctly using opcode sizes';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 6: Frame state after execution
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: Frame state after execution...';
    test_count := test_count + 1;
    
    -- Verify frame still exists and is valid
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'FAIL: Frame does not exist after execution';
    END IF;
    
    -- Verify stack is empty (we popped everything)
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size IS NOT NULL AND stack_size != 0 THEN
        RAISE EXCEPTION 'FAIL: Stack is not empty, size is %', stack_size;
    END IF;
    
    RAISE NOTICE '  ✓ Frame state is correct after execution';
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
    
    RAISE NOTICE '✅ All VM integration tests passed!';
    
END $$;
