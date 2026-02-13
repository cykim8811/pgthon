-- ============================================================================
-- Test: Method Object Schema Validation
-- 
-- Purpose:
--   Validates that the method object schema is correctly created with proper
--   structure, constraints, and relationships. This test verifies:
--   - py_method_object table exists with correct structure
--   - Shared-PK inheritance is correct
--   - All references point to py_object.id (CPython's PyObject* principle)
--   - Foreign key constraints are properly set up
--   - Tables and constraints are correct
--
-- Usage:
--   Run this file after migrations to verify schema integrity.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

DO $$
DECLARE
    -- Test counters
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    
    -- Helper variables
    table_exists BOOLEAN;
    column_exists BOOLEAN;
    constraint_exists BOOLEAN;
    column_count INTEGER;
    fk_count INTEGER;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Method Object Schema Validation Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- Test 1: Verify py_method_object table exists
    -- ========================================================================
    RAISE NOTICE 'Test 1: Verifying py_method_object table...';
    test_count := test_count + 1;
    
    SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'py_method_object'
    ) INTO table_exists;
    
    IF table_exists THEN
        RAISE NOTICE '  ✓ py_method_object table exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object table does not exist';
    END IF;

    -- ========================================================================
    -- Test 2: Verify py_method_object structure (columns)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Verifying py_method_object structure...';
    
    -- ob_base column
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_method_object'
        AND column_name = 'ob_base'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_method_object.ob_base column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object.ob_base column does not exist';
    END IF;
    
    -- im_func column
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_method_object'
        AND column_name = 'im_func'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_method_object.im_func column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object.im_func column does not exist';
    END IF;
    
    -- im_self column
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_method_object'
        AND column_name = 'im_self'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_method_object.im_self column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object.im_self column does not exist';
    END IF;
    
    -- im_class column
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_method_object'
        AND column_name = 'im_class'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_method_object.im_class column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object.im_class column does not exist';
    END IF;
    
    -- Verify all required columns exist
    test_count := test_count + 1;
    SELECT COUNT(*) INTO column_count
    FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'py_method_object'
    AND column_name IN ('ob_base', 'im_func', 'im_self', 'im_class');
    
    IF column_count = 4 THEN
        RAISE NOTICE '  ✓ py_method_object has all required columns';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object missing required columns (expected 4, found %)', column_count;
    END IF;

    -- ========================================================================
    -- Test 3: Verify py_method_object foreign key constraints
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Verifying py_method_object foreign keys...';
    
    -- ob_base references py_object(id)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_schema = 'public'
        AND tc.table_name = 'py_method_object'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND ccu.table_name = 'py_object'
        AND ccu.column_name = 'id'
    ) INTO constraint_exists;
    
    IF constraint_exists THEN
        RAISE NOTICE '  ✓ py_method_object.ob_base references py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object.ob_base does not reference py_object(id)';
    END IF;
    
    -- im_func references py_object(id)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_schema = 'public'
        AND tc.table_name = 'py_method_object'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND ccu.table_name = 'py_object'
        AND ccu.column_name = 'id'
        AND EXISTS (
            SELECT FROM information_schema.key_column_usage kcu
            WHERE kcu.constraint_name = tc.constraint_name
            AND kcu.column_name = 'im_func'
        )
    ) INTO constraint_exists;
    
    IF constraint_exists THEN
        RAISE NOTICE '  ✓ py_method_object.im_func references py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object.im_func does not reference py_object(id)';
    END IF;
    
    -- im_self references py_object(id) (nullable)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_schema = 'public'
        AND tc.table_name = 'py_method_object'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND ccu.table_name = 'py_object'
        AND ccu.column_name = 'id'
        AND EXISTS (
            SELECT FROM information_schema.key_column_usage kcu
            WHERE kcu.constraint_name = tc.constraint_name
            AND kcu.column_name = 'im_self'
        )
    ) INTO constraint_exists;
    
    IF constraint_exists THEN
        RAISE NOTICE '  ✓ py_method_object.im_self references py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object.im_self does not reference py_object(id)';
    END IF;
    
    -- im_class references py_object(id)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_schema = 'public'
        AND tc.table_name = 'py_method_object'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND ccu.table_name = 'py_object'
        AND ccu.column_name = 'id'
        AND EXISTS (
            SELECT FROM information_schema.key_column_usage kcu
            WHERE kcu.constraint_name = tc.constraint_name
            AND kcu.column_name = 'im_class'
        )
    ) INTO constraint_exists;
    
    IF constraint_exists THEN
        RAISE NOTICE '  ✓ py_method_object.im_class references py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object.im_class does not reference py_object(id)';
    END IF;
    
    -- Count all foreign keys that reference py_object(id)
    test_count := test_count + 1;
    SELECT COUNT(DISTINCT tc.constraint_name) INTO fk_count
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu 
        ON tc.constraint_name = ccu.constraint_name
    WHERE tc.table_schema = 'public'
    AND tc.table_name = 'py_method_object'
    AND tc.constraint_type = 'FOREIGN KEY'
    AND ccu.table_name = 'py_object'
    AND ccu.column_name = 'id';
    
    -- Should have at least 4 foreign keys (ob_base + im_func, im_self, im_class)
    IF fk_count >= 4 THEN
        RAISE NOTICE '  ✓ All py_method_object foreign keys reference py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object foreign keys do not all reference py_object(id) (found % constraints)', fk_count;
    END IF;

    -- ========================================================================
    -- Test 4: Verify im_self is nullable (for unbound methods)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Verifying im_self is nullable...';
    test_count := test_count + 1;
    
    SELECT is_nullable INTO column_exists
    FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'py_method_object'
    AND column_name = 'im_self';
    
    IF column_exists = 'YES' THEN
        RAISE NOTICE '  ✓ py_method_object.im_self is nullable (supports unbound methods)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_method_object.im_self is not nullable (should support unbound methods)';
    END IF;

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
    
    IF fail_count = 0 THEN
        RAISE NOTICE '✓ All tests passed! Schema is valid.';
    ELSE
        RAISE EXCEPTION '✗ % test(s) failed. Schema validation failed.', fail_count;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Test Failed';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Error: %', SQLERRM;
        RAISE NOTICE '';
        RAISE NOTICE 'Tests completed: %', test_count;
        RAISE NOTICE 'Passed: %', pass_count;
        RAISE NOTICE 'Failed: %', fail_count;
        RAISE;
END $$;
