-- =====================================================
-- Test Setup: Helper Functions
-- Description: Common test assertion helpers
-- =====================================================

-------------------------------------------------------
-- 1. Simple Assertion Helper
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.test_assert(condition boolean, message text)
RETURNS void AS $$
BEGIN
    IF NOT condition THEN
        RAISE EXCEPTION 'TEST FAILED: %', message;
    ELSE
        RAISE NOTICE 'TEST PASSED: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 2. Integer Equality Assertion
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.test_assert_eq_int(actual bigint, expected bigint, message text)
RETURNS void AS $$
BEGIN
    IF actual IS DISTINCT FROM expected THEN
        RAISE EXCEPTION 'TEST FAILED: % (Expected %, Got %)', message, expected, actual;
    ELSE
        RAISE NOTICE 'TEST PASSED: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 3. String Equality Assertion
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.test_assert_eq_str(actual text, expected text, message text)
RETURNS void AS $$
BEGIN
    IF actual IS DISTINCT FROM expected THEN
        RAISE EXCEPTION 'TEST FAILED: % (Expected "%", Got "%")', message, expected, actual;
    ELSE
        RAISE NOTICE 'TEST PASSED: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 4. UUID Not Null Assertion
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.test_assert_not_null(value uuid, message text)
RETURNS void AS $$
BEGIN
    IF value IS NULL THEN
        RAISE EXCEPTION 'TEST FAILED: % (Value is NULL)', message;
    ELSE
        RAISE NOTICE 'TEST PASSED: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;
