-- ============================================================================
-- Test: VM Opcode Utilities Test
-- 
-- Purpose:
--   Tests that opcode utility functions work correctly. This verifies:
--   - py_get_opcode_size returns correct sizes for opcodes
--   - Python 3.6+ uniform format: all instructions are 2 bytes (opcode + arg)
--   - Invalid opcode values raise exceptions
--
-- Usage:
--   Run this file after migrations to verify opcode utility implementations.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

DO $$
DECLARE
    -- Test counters
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    
    -- Test variables
    opcode_size INTEGER;
    test_opcode INTEGER;
    
    -- Error handling
    error_occurred BOOLEAN;
    error_message TEXT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM Opcode Utilities Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Test 1: Default size (2 bytes) for common opcodes
    -- ========================================================================
    RAISE NOTICE 'Test 1: Default size (2 bytes) for common opcodes...';
    test_count := test_count + 1;
    
    -- Test LOAD_CONST (opcode 100)
    opcode_size := public.py_get_opcode_size(100);
    IF opcode_size != 2 THEN
        RAISE EXCEPTION 'FAIL: LOAD_CONST (100) size is %, expected 2', opcode_size;
    END IF;
    
    -- Test LOAD_NAME (opcode 101)
    opcode_size := public.py_get_opcode_size(101);
    IF opcode_size != 2 THEN
        RAISE EXCEPTION 'FAIL: LOAD_NAME (101) size is %, expected 2', opcode_size;
    END IF;
    
    -- Test BINARY_ADD (opcode 23)
    opcode_size := public.py_get_opcode_size(23);
    IF opcode_size != 2 THEN
        RAISE EXCEPTION 'FAIL: BINARY_ADD (23) size is %, expected 2', opcode_size;
    END IF;
    
    -- Test RETURN_VALUE (opcode 83)
    opcode_size := public.py_get_opcode_size(83);
    IF opcode_size != 2 THEN
        RAISE EXCEPTION 'FAIL: RETURN_VALUE (83) size is %, expected 2', opcode_size;
    END IF;
    
    -- Test CALL_FUNCTION (opcode 141)
    opcode_size := public.py_get_opcode_size(141);
    IF opcode_size != 2 THEN
        RAISE EXCEPTION 'FAIL: CALL_FUNCTION (141) size is %, expected 2', opcode_size;
    END IF;
    
    RAISE NOTICE '  ✓ Default size (2 bytes) works for common opcodes';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: NOP (9) — Python 3.6+ uniform 2-byte instruction
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: NOP (9) — uniform 2 bytes...';
    test_count := test_count + 1;
    
    opcode_size := public.py_get_opcode_size(9);  -- NOP
    IF opcode_size != 2 THEN
        RAISE EXCEPTION 'FAIL: NOP (9) size is %, expected 2', opcode_size;
    END IF;
    
    RAISE NOTICE '  ✓ NOP correctly returns 2 bytes (3.6+ uniform format)';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: Edge cases - opcode 0 and 255
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Edge cases - opcode 0 and 255...';
    test_count := test_count + 1;
    
    -- Opcode 0 (should default to 2 bytes)
    opcode_size := public.py_get_opcode_size(0);
    IF opcode_size != 2 THEN
        RAISE EXCEPTION 'FAIL: Opcode 0 size is %, expected 2', opcode_size;
    END IF;
    
    -- Opcode 255 (should default to 2 bytes)
    opcode_size := public.py_get_opcode_size(255);
    IF opcode_size != 2 THEN
        RAISE EXCEPTION 'FAIL: Opcode 255 size is %, expected 2', opcode_size;
    END IF;
    
    RAISE NOTICE '  ✓ Edge cases handled correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: Invalid opcode - negative value
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Invalid opcode - negative value...';
    test_count := test_count + 1;
    
    error_occurred := FALSE;
    BEGIN
        opcode_size := public.py_get_opcode_size(-1);
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on negative opcode, but none occurred';
    END IF;
    
    IF error_message NOT LIKE '%Invalid opcode%' THEN
        RAISE EXCEPTION 'FAIL: Expected "Invalid opcode" error, got: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ Negative opcode correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: Invalid opcode - value > 255
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Invalid opcode - value > 255...';
    test_count := test_count + 1;
    
    error_occurred := FALSE;
    BEGIN
        opcode_size := public.py_get_opcode_size(256);
        error_occurred := FALSE;
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on opcode > 255, but none occurred';
    END IF;
    
    IF error_message NOT LIKE '%Invalid opcode%' THEN
        RAISE EXCEPTION 'FAIL: Expected "Invalid opcode" error, got: %', error_message;
    END IF;
    
    RAISE NOTICE '  ✓ Opcode > 255 correctly raises exception';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 6: Multiple opcodes - verify consistency
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: Multiple opcodes - verify consistency...';
    test_count := test_count + 1;
    
    -- Test a range of opcodes: Python 3.6+ all instructions are 2 bytes
    FOR test_opcode IN 0..50 LOOP
        opcode_size := public.py_get_opcode_size(test_opcode);
        IF opcode_size != 2 THEN
            RAISE EXCEPTION 'FAIL: Opcode % size is %, expected 2', test_opcode, opcode_size;
        END IF;
    END LOOP;
    
    RAISE NOTICE '  ✓ Multiple opcodes return consistent sizes';
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
    
    RAISE NOTICE '✅ All opcode utility tests passed!';
    
END $$;
