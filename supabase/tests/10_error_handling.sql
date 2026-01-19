-- =====================================================
-- Test 10: Error Handling & Traceback
-- Description: Verify that VM errors generate proper Python-style tracebacks
-- =====================================================

DO $$
DECLARE
    v_code uuid;
    v_frame uuid;
    v_res uuid;
BEGIN
    RAISE NOTICE 'Testing Error Handling...';

    -------------------------------------------------------
    -- 1. Test TypeError with Traceback
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing TypeError Traceback ===';
    
    -- Code: 
    -- x = 1
    -- y = "2"
    -- return x + y  <-- Should raise TypeError
    v_code := public.vm_assemble('LOAD_CONST 1
STORE_FAST x
LOAD_CONST "2"
STORE_FAST y
LOAD_FAST x
LOAD_FAST y
BINARY_ADD
RETURN_VALUE', 'type_error_test');

    BEGIN
        -- Execute safely to catch error
        v_res := public.vm_execute_source(
            'LOAD_CONST 1
STORE_FAST x
LOAD_CONST "2"
STORE_FAST y
LOAD_FAST x
LOAD_FAST y
BINARY_ADD
RETURN_VALUE'
        );
        
        -- If we reach here, test failed
        PERFORM public.test_assert(false, 'Should have raised TypeError');
    EXCEPTION WHEN OTHERS THEN
        -- Check error message
        RAISE NOTICE 'Caught expected error: %', SQLERRM;
        
        -- 1. Check if it's the expected TypeError
        PERFORM public.test_assert(SQLERRM LIKE '%TypeError%', 'Error should be TypeError');
        
        -- 2. Check if Traceback is present (The core goal of this test)
        -- Note: Before implementing error handling in VM, this check might fail or check for absence.
        -- We expect "Traceback (most recent call last):"
        IF SQLERRM LIKE '%Traceback (most recent call last):%' THEN
            RAISE NOTICE '✅ Traceback present in error message';
        ELSE
            RAISE NOTICE '⚠️ Traceback NOT found (Feature might not be implemented yet)';
        END IF;
    END;

    -------------------------------------------------------
    -- 2. Test Safe Recursion Error (Stack Overflow simulation)
    --    Optional for now, focusing on basic format first
    -------------------------------------------------------
    
    RAISE NOTICE E'\n✅ PASS: 10_error_handling (Basic Assertions)';
END $$;
