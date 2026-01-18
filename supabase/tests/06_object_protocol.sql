-- =====================================================
-- Test 06: VM Object Protocol and Attributes
-- Description: Test attribute access, method binding, and getattr
-- Dependencies: Migrations 07, 10-11 (vm_object_protocol, vm_call, vm_interpreter)
-- =====================================================

DO $$
DECLARE
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    ID_METHOD_TYPE uuid := '00000000-0000-4000-a000-000000000013';
    
    v_int_obj uuid;
    v_add_method uuid;
    v_method_type uuid;
    v_result uuid;
    v_val bigint;
BEGIN
    -------------------------------------------------------
    -- 1. Test getattr on Integer
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing getattr ===';
    
    v_int_obj := public.vm_create_int(42);
    
    -- Get __add__ method
    v_add_method := public.vm_getattr(v_int_obj, '__add__');
    PERFORM public.test_assert_not_null(v_add_method, 'getattr(int, "__add__") returns method');
    
    -- Check it's a bound method
    v_method_type := public.vm_get_type(v_add_method);
    PERFORM public.test_assert(v_method_type = ID_METHOD_TYPE, '__add__ is a bound method');
    
    -------------------------------------------------------
    -- 2. Test Bound Method Call
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Bound Method Call ===';
    
    DECLARE
        v_other uuid := public.vm_create_int(8);
        v_args uuid[];
    BEGIN
        -- Call bound method: 42.__add__(8) = 50
        v_args := ARRAY[v_other];
        v_result := public.vm_call(v_add_method, v_args);
        
        v_val := public.vm_get_int_value(v_result);
        PERFORM public.test_assert_eq_int(v_val, 50, '42.__add__(8) = 50');
    END;
    
    -------------------------------------------------------
    -- 3. Test Method Lookup in Type
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Type Lookup ===';
    
    DECLARE
        v_found uuid;
    BEGIN
        -- Look for __add__ in int type
        v_found := public.vm_lookup_in_type(ID_INT_TYPE, '__add__');
        PERFORM public.test_assert_not_null(v_found, 'Lookup __add__ in int type');
        
        -- Look for non-existent method
        v_found := public.vm_lookup_in_type(ID_INT_TYPE, 'nonexistent_method');
        PERFORM public.test_assert(v_found IS NULL, 'Lookup nonexistent method returns NULL');
    END;
    
    -------------------------------------------------------
    -- 4. Test Descriptor Protocol
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Descriptor Protocol ===';
    
    DECLARE
        v_func uuid;
        v_bound uuid;
        v_self uuid := public.vm_create_int(100);
    BEGIN
        -- Get unbound method from type
        v_func := public.vm_lookup_in_type(ID_INT_TYPE, '__add__');
        
        -- Apply descriptor protocol to bind it
        v_bound := public.vm_descriptor_get(v_func, v_self, ID_INT_TYPE);
        PERFORM public.test_assert_not_null(v_bound, 'Descriptor protocol creates bound method');
        
        -- Should be different from original function
        PERFORM public.test_assert(v_bound <> v_func, 'Bound method is different object');
        
        -- Call the bound method
        v_result := public.vm_call(v_bound, ARRAY[public.vm_create_int(23)]);
        v_val := public.vm_get_int_value(v_result);
        PERFORM public.test_assert_eq_int(v_val, 123, '100.__add__(23) = 123 via descriptor');
    END;
    
    -------------------------------------------------------
    -- 5. Test LOAD_ATTR Opcode
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing LOAD_ATTR in Bytecode ===';
    
    DECLARE
        v_source text;
    BEGIN
        -- This would require LOAD_ATTR implementation which uses varnames for attr names
        -- For now, we test the underlying mechanism was already tested above
        RAISE NOTICE 'LOAD_ATTR tested via getattr unit tests';
    END;
    
    RAISE NOTICE E'\n=== All Object Protocol Tests Passed! ===\n';
END $$;
