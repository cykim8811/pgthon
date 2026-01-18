-- Test Helper Functions
-- Created at: 2026-01-18 00:00:99

-- 1. Simple Assertion Helpers
CREATE OR REPLACE FUNCTION public.test_assert(condition BOOLEAN, message TEXT)
RETURNS VOID AS $$
BEGIN
    IF NOT condition THEN
        RAISE EXCEPTION 'TEST FAILED: %', message;
    ELSE
        RAISE NOTICE 'TEST PASSED: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.test_assert_eq_int(actual BIGINT, expected BIGINT, message TEXT)
RETURNS VOID AS $$
BEGIN
    IF actual IS DISTINCT FROM expected THEN
        RAISE EXCEPTION 'TEST FAILED: % (Expected %, Got %)', message, expected, actual;
    ELSE
        RAISE NOTICE 'TEST PASSED: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;
