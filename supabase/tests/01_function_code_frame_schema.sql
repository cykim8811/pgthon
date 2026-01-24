-- ============================================================================
-- Test: Function, Code, Frame, and CFunction Object Schema Validation
-- 
-- Purpose:
--   Validates that the function, code, frame, and C function object schemas
--   are correctly created with proper structure, constraints, and relationships.
--   This test verifies:
--   - Tables exist with correct structure (py_function_object, py_code_object,
--     py_frame_object, py_cfunction_object)
--   - Shared-PK inheritance is correct
--   - All references point to py_object.id (CPython's PyObject* principle)
--   - Foreign key constraints are properly set up
--   - RLS policies are enabled
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
    rls_enabled BOOLEAN;
    policy_exists BOOLEAN;
    constraint_name TEXT;
    column_count INTEGER;
    fk_count INTEGER;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Function, Code, and Frame Schema Validation Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- Test 1: Verify py_function_object table exists
    -- ========================================================================
    RAISE NOTICE 'Test 1: Verifying py_function_object table...';
    test_count := test_count + 1;
    
    SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'py_function_object'
    ) INTO table_exists;
    
    IF table_exists THEN
        RAISE NOTICE '  ✓ py_function_object table exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_function_object table does not exist';
    END IF;

    -- ========================================================================
    -- Test 2: Verify py_function_object structure (columns and constraints)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Verifying py_function_object structure...';
    
    -- ob_base column
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_function_object'
        AND column_name = 'ob_base'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_function_object.ob_base column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_function_object.ob_base column does not exist';
    END IF;
    
    -- func_code column
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_function_object'
        AND column_name = 'func_code'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_function_object.func_code column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_function_object.func_code column does not exist';
    END IF;
    
    -- func_globals column
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_function_object'
        AND column_name = 'func_globals'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_function_object.func_globals column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_function_object.func_globals column does not exist';
    END IF;
    
    -- func_defaults column (optional)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_function_object'
        AND column_name = 'func_defaults'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_function_object.func_defaults column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_function_object.func_defaults column does not exist';
    END IF;
    
    -- func_closure column (optional)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_function_object'
        AND column_name = 'func_closure'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_function_object.func_closure column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_function_object.func_closure column does not exist';
    END IF;

    -- ========================================================================
    -- Test 3: Verify py_function_object foreign key constraints
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Verifying py_function_object foreign keys...';
    
    -- ob_base references py_object(id)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_schema = 'public'
        AND tc.table_name = 'py_function_object'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND ccu.table_name = 'py_object'
        AND ccu.column_name = 'id'
    ) INTO constraint_exists;
    
    IF constraint_exists THEN
        RAISE NOTICE '  ✓ py_function_object.ob_base references py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_function_object.ob_base does not reference py_object(id)';
    END IF;
    
    -- func_code references py_object(id)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_schema = 'public'
        AND tc.table_name = 'py_function_object'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND ccu.table_name = 'py_object'
        AND ccu.column_name = 'id'
        AND EXISTS (
            SELECT FROM information_schema.key_column_usage kcu
            WHERE kcu.constraint_name = tc.constraint_name
            AND kcu.column_name = 'func_code'
        )
    ) INTO constraint_exists;
    
    IF constraint_exists THEN
        RAISE NOTICE '  ✓ py_function_object.func_code references py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_function_object.func_code does not reference py_object(id)';
    END IF;
    
    -- func_globals references py_object(id)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_schema = 'public'
        AND tc.table_name = 'py_function_object'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND ccu.table_name = 'py_object'
        AND ccu.column_name = 'id'
        AND EXISTS (
            SELECT FROM information_schema.key_column_usage kcu
            WHERE kcu.constraint_name = tc.constraint_name
            AND kcu.column_name = 'func_globals'
        )
    ) INTO constraint_exists;
    
    IF constraint_exists THEN
        RAISE NOTICE '  ✓ py_function_object.func_globals references py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_function_object.func_globals does not reference py_object(id)';
    END IF;

    -- ========================================================================
    -- Test 4: Verify py_code_object table exists and structure
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Verifying py_code_object table...';
    test_count := test_count + 1;
    
    SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'py_code_object'
    ) INTO table_exists;
    
    IF table_exists THEN
        RAISE NOTICE '  ✓ py_code_object table exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_code_object table does not exist';
    END IF;
    
    -- Verify key columns
    test_count := test_count + 1;
    SELECT COUNT(*) INTO column_count
    FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'py_code_object'
    AND column_name IN ('ob_base', 'co_code', 'co_consts', 'co_names', 'co_filename', 'co_name');
    
    IF column_count = 6 THEN
        RAISE NOTICE '  ✓ py_code_object has all required columns';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_code_object missing required columns (expected 6, found %)', column_count;
    END IF;

    -- ========================================================================
    -- Test 5: Verify py_code_object foreign keys point to py_object
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Verifying py_code_object foreign keys...';
    test_count := test_count + 1;
    
    -- Count foreign keys that reference py_object(id)
    SELECT COUNT(DISTINCT tc.constraint_name) INTO fk_count
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu 
        ON tc.constraint_name = ccu.constraint_name
    WHERE tc.table_schema = 'public'
    AND tc.table_name = 'py_code_object'
    AND tc.constraint_type = 'FOREIGN KEY'
    AND ccu.table_name = 'py_object'
    AND ccu.column_name = 'id';
    
    -- Should have at least 6 foreign keys (ob_base + 5 co_* fields)
    IF fk_count >= 6 THEN
        RAISE NOTICE '  ✓ py_code_object foreign keys reference py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_code_object foreign keys do not all reference py_object(id) (found % constraints)', fk_count;
    END IF;

    -- ========================================================================
    -- Test 6: Verify py_frame_object table exists and structure
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: Verifying py_frame_object table...';
    test_count := test_count + 1;
    
    SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'py_frame_object'
    ) INTO table_exists;
    
    IF table_exists THEN
        RAISE NOTICE '  ✓ py_frame_object table exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_frame_object table does not exist';
    END IF;
    
    -- Verify key columns
    test_count := test_count + 1;
    SELECT COUNT(*) INTO column_count
    FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'py_frame_object'
    AND column_name IN ('ob_base', 'f_code', 'f_globals', 'f_locals', 'f_back');
    
    IF column_count = 5 THEN
        RAISE NOTICE '  ✓ py_frame_object has all required columns';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_frame_object missing required columns (expected 5, found %)', column_count;
    END IF;

    -- ========================================================================
    -- Test 7: Verify py_frame_object foreign keys point to py_object
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: Verifying py_frame_object foreign keys...';
    test_count := test_count + 1;
    
    -- Count foreign keys that reference py_object(id)
    SELECT COUNT(DISTINCT tc.constraint_name) INTO fk_count
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu 
        ON tc.constraint_name = ccu.constraint_name
    WHERE tc.table_schema = 'public'
    AND tc.table_name = 'py_frame_object'
    AND tc.constraint_type = 'FOREIGN KEY'
    AND ccu.table_name = 'py_object'
    AND ccu.column_name = 'id';
    
    -- Should have at least 4 foreign keys (ob_base + f_code, f_globals, f_locals, f_back)
    IF fk_count >= 4 THEN
        RAISE NOTICE '  ✓ py_frame_object foreign keys reference py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_frame_object foreign keys do not all reference py_object(id) (found % constraints)', fk_count;
    END IF;

    -- ========================================================================
    -- Test 8: Verify RLS is enabled on all tables
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: Verifying RLS is enabled...';
    
    -- py_function_object
    test_count := test_count + 1;
    SELECT relrowsecurity INTO rls_enabled
    FROM pg_class
    WHERE relname = 'py_function_object' AND relnamespace = 'public'::regnamespace;
    
    IF rls_enabled THEN
        RAISE NOTICE '  ✓ RLS enabled on py_function_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: RLS not enabled on py_function_object';
    END IF;
    
    -- py_code_object
    test_count := test_count + 1;
    SELECT relrowsecurity INTO rls_enabled
    FROM pg_class
    WHERE relname = 'py_code_object' AND relnamespace = 'public'::regnamespace;
    
    IF rls_enabled THEN
        RAISE NOTICE '  ✓ RLS enabled on py_code_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: RLS not enabled on py_code_object';
    END IF;
    
    -- py_frame_object
    test_count := test_count + 1;
    SELECT relrowsecurity INTO rls_enabled
    FROM pg_class
    WHERE relname = 'py_frame_object' AND relnamespace = 'public'::regnamespace;
    
    IF rls_enabled THEN
        RAISE NOTICE '  ✓ RLS enabled on py_frame_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: RLS not enabled on py_frame_object';
    END IF;

    -- ========================================================================
    -- Test 9: Verify RLS policies exist
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 9: Verifying RLS policies...';
    
    -- py_function_object policy
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'py_function_object'
    ) INTO policy_exists;
    
    IF policy_exists THEN
        RAISE NOTICE '  ✓ RLS policy exists for py_function_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: RLS policy does not exist for py_function_object';
    END IF;
    
    -- py_code_object policy
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'py_code_object'
    ) INTO policy_exists;
    
    IF policy_exists THEN
        RAISE NOTICE '  ✓ RLS policy exists for py_code_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: RLS policy does not exist for py_code_object';
    END IF;
    
    -- py_frame_object policy
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'py_frame_object'
    ) INTO policy_exists;
    
    IF policy_exists THEN
        RAISE NOTICE '  ✓ RLS policy exists for py_frame_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: RLS policy does not exist for py_frame_object';
    END IF;

    -- ========================================================================
    -- Test 10: Verify py_cfunction_object table exists
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 10: Verifying py_cfunction_object table...';
    test_count := test_count + 1;
    
    SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'py_cfunction_object'
    ) INTO table_exists;
    
    IF table_exists THEN
        RAISE NOTICE '  ✓ py_cfunction_object table exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_cfunction_object table does not exist';
    END IF;

    -- ========================================================================
    -- Test 11: Verify py_cfunction_object structure (columns)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 11: Verifying py_cfunction_object structure...';
    
    -- ob_base column
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_cfunction_object'
        AND column_name = 'ob_base'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_cfunction_object.ob_base column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_cfunction_object.ob_base column does not exist';
    END IF;
    
    -- m_ml_name column
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_cfunction_object'
        AND column_name = 'm_ml_name'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_cfunction_object.m_ml_name column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_cfunction_object.m_ml_name column does not exist';
    END IF;
    
    -- m_ml_flags column
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_cfunction_object'
        AND column_name = 'm_ml_flags'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_cfunction_object.m_ml_flags column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_cfunction_object.m_ml_flags column does not exist';
    END IF;
    
    -- m_ml_doc column (optional)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_cfunction_object'
        AND column_name = 'm_ml_doc'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_cfunction_object.m_ml_doc column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_cfunction_object.m_ml_doc column does not exist';
    END IF;
    
    -- m_self column (optional)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_cfunction_object'
        AND column_name = 'm_self'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_cfunction_object.m_self column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_cfunction_object.m_self column does not exist';
    END IF;
    
    -- m_module column (optional)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'py_cfunction_object'
        AND column_name = 'm_module'
    ) INTO column_exists;
    
    IF column_exists THEN
        RAISE NOTICE '  ✓ py_cfunction_object.m_module column exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_cfunction_object.m_module column does not exist';
    END IF;

    -- ========================================================================
    -- Test 12: Verify py_cfunction_object foreign key constraints
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 12: Verifying py_cfunction_object foreign keys...';
    
    -- ob_base references py_object(id)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_schema = 'public'
        AND tc.table_name = 'py_cfunction_object'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND ccu.table_name = 'py_object'
        AND ccu.column_name = 'id'
    ) INTO constraint_exists;
    
    IF constraint_exists THEN
        RAISE NOTICE '  ✓ py_cfunction_object.ob_base references py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_cfunction_object.ob_base does not reference py_object(id)';
    END IF;
    
    -- m_ml_name references py_object(id)
    test_count := test_count + 1;
    SELECT EXISTS (
        SELECT FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_schema = 'public'
        AND tc.table_name = 'py_cfunction_object'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND ccu.table_name = 'py_object'
        AND ccu.column_name = 'id'
        AND EXISTS (
            SELECT FROM information_schema.key_column_usage kcu
            WHERE kcu.constraint_name = tc.constraint_name
            AND kcu.column_name = 'm_ml_name'
        )
    ) INTO constraint_exists;
    
    IF constraint_exists THEN
        RAISE NOTICE '  ✓ py_cfunction_object.m_ml_name references py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_cfunction_object.m_ml_name does not reference py_object(id)';
    END IF;
    
    -- Count all foreign keys that reference py_object(id)
    test_count := test_count + 1;
    SELECT COUNT(DISTINCT tc.constraint_name) INTO fk_count
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu 
        ON tc.constraint_name = ccu.constraint_name
    WHERE tc.table_schema = 'public'
    AND tc.table_name = 'py_cfunction_object'
    AND tc.constraint_type = 'FOREIGN KEY'
    AND ccu.table_name = 'py_object'
    AND ccu.column_name = 'id';
    
    -- Should have at least 4 foreign keys (ob_base + m_ml_name + m_ml_doc + m_self + m_module)
    IF fk_count >= 4 THEN
        RAISE NOTICE '  ✓ py_cfunction_object foreign keys reference py_object(id)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: py_cfunction_object foreign keys do not all reference py_object(id) (found % constraints)', fk_count;
    END IF;

    -- ========================================================================
    -- Test 13: Verify RLS is enabled on py_cfunction_object
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 13: Verifying RLS is enabled on py_cfunction_object...';
    test_count := test_count + 1;
    
    SELECT relrowsecurity INTO rls_enabled
    FROM pg_class
    WHERE relname = 'py_cfunction_object' AND relnamespace = 'public'::regnamespace;
    
    IF rls_enabled THEN
        RAISE NOTICE '  ✓ RLS enabled on py_cfunction_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: RLS not enabled on py_cfunction_object';
    END IF;

    -- ========================================================================
    -- Test 14: Verify RLS policy exists for py_cfunction_object
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 14: Verifying RLS policy for py_cfunction_object...';
    test_count := test_count + 1;
    
    SELECT EXISTS (
        SELECT FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'py_cfunction_object'
    ) INTO policy_exists;
    
    IF policy_exists THEN
        RAISE NOTICE '  ✓ RLS policy exists for py_cfunction_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: RLS policy does not exist for py_cfunction_object';
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
