-- ============================================================================
-- Script: Find two distinct strings with the same py_object_hash
--
-- Purpose:
--   Discovers a hash collision (two different str_value with same hashtext
--   via py_object_hash) for use in 18_dict_lookup_hash.sql Test 10.
--   Run once, copy the two printed strings into the test, then tests stay fast.
--
-- Usage:
--   After migrations are applied:
--     docker exec -i supabase_db_pgthon psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/scripts/find_hash_collision.sql
--
--   Or from repo root:
--     docker exec -i supabase_db_pgthon psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/scripts/find_hash_collision.sql
--
-- Output:
--   NOTICE: COLLISION_A = '...'
--   NOTICE: COLLISION_B = '...'
--   Copy those into 18_dict_lookup_hash.sql (COLLISION_A / COLLISION_B in Test 10).
--   Current Test 10 uses 'q16584' and 'q52834' from a prior run.
-- ============================================================================

DO $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    i INT;
    sid UUID;
    h_cand BIGINT;
    k1_id UUID;
    k2_id UUID;
    str_a TEXT;
    str_b TEXT;
BEGIN
    k1_id := NULL;
    k2_id := NULL;
    CREATE TEMP TABLE IF NOT EXISTS _ht (sid uuid, h bigint);
    TRUNCATE _ht;

    -- Increase upper bound if no collision (e.g. 199999).
    FOR i IN 0..99999 LOOP
        sid := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (sid, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (sid, 'q' || i::text);
        h_cand := public.py_object_hash(sid);
        SELECT ht.sid INTO k2_id FROM _ht ht WHERE ht.h = h_cand LIMIT 1;
        IF k2_id IS NOT NULL THEN
            k1_id := k2_id;
            k2_id := sid;
            EXIT;
        END IF;
        INSERT INTO _ht (sid, h) VALUES (sid, h_cand);
    END LOOP;

    DROP TABLE _ht;

    IF k1_id IS NULL OR k2_id IS NULL THEN
        RAISE EXCEPTION 'No collision found. Edit this script: change 99999 to 199999 and run again.';
    END IF;

    SELECT str_value INTO str_a FROM public.py_unicode_object WHERE ob_base = k1_id;
    SELECT str_value INTO str_b FROM public.py_unicode_object WHERE ob_base = k2_id;

    RAISE NOTICE '========================================';
    RAISE NOTICE 'Hash collision found. Use in 18_dict_lookup_hash.sql Test 10:';
    RAISE NOTICE '  COLLISION_A = ''%''', str_a;
    RAISE NOTICE '  COLLISION_B = ''%''', str_b;
    RAISE NOTICE '========================================';
END $$;
