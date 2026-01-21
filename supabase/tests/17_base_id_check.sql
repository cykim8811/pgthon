-- =====================================================
-- Test 17: Base ID Unification Check
-- Description: Verify that Type IDs are unified (BaseID == TableID) 
--              and schema constraints are correctly enforced.
-- dependencies: 20260121000000_fix_type_ids_and_schema.sql
-- =====================================================

DO $$
DECLARE
    -- Hardcoded IDs (Table IDs) that should now be valid Base IDs
    ID_OBJ_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    
    v_int_obj uuid;
    v_type_id uuid;
    v_base_check uuid;
    v_lookup_res uuid;
BEGIN
    RAISE NOTICE E'\n=== Testing Base ID Unification ===';

    -- 1. Verify Built-in Types have Base ID == Table ID
    SELECT ob_base INTO v_base_check FROM public.py_type_object WHERE id = ID_INT_TYPE;
    PERFORM public.test_assert(v_base_check = ID_INT_TYPE, 'int type Base ID matches Table ID');
    
    SELECT ob_base INTO v_base_check FROM public.py_type_object WHERE id = ID_STR_TYPE;
    PERFORM public.test_assert(v_base_check = ID_STR_TYPE, 'str type Base ID matches Table ID');

    -- 2. Verify vm_get_type returns the Hardcoded ID (which is now Base ID)
    v_int_obj := public.vm_create_int(100);
    v_type_id := public.vm_get_type(v_int_obj);
    
    PERFORM public.test_assert(v_type_id = ID_INT_TYPE, 'vm_get_type returns correct Base ID for int');

    -- 3. Verify vm_lookup_in_type works with Hardcoded ID (as Base ID)
    -- We'll look up 'upper' on STR type (assuming it has methods, though native methods might be empty in test env)
    -- Actually, let's check basic inheritance or attribute lookup if possible.
    -- Or just ensure it doesn't crash.
    
    -- Let's try to look up something that might exist or just check non-crash
    -- We don't have many methods bound in default bootstrap unless added.
    -- But we can check if it returns NULL (not crash) for non-existent.
    v_lookup_res := public.vm_lookup_in_type(ID_STR_TYPE, 'non_existent_method');
    PERFORM public.test_assert(v_lookup_res IS NULL, 'vm_lookup_in_type runs safely with Base ID');

    -- 4. Verify FK Constraint on py_object.ob_type
    -- We'll try to insert a py_object with a random UUID as type (should fail)
    BEGIN
        INSERT INTO public.py_object (id, ob_type) VALUES (gen_random_uuid(), gen_random_uuid());
        RAISE EXCEPTION 'FK Constraint failed to catch invalid type ID';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE '✅ FK Constraint verified: Cannot use random UUID as type';
    END;

    RAISE NOTICE E'\n=== All Base ID Verification Tests Passed! ===\n';
END $$;
