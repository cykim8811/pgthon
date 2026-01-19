-- =====================================================
-- Test 11: Exception Infrastructure
-- Description: Verify exception types are registered and storage works
-- =====================================================

DO $$
DECLARE
    v_type_error_id uuid;
    v_base_id uuid;
    v_exc_id uuid;
    ID_DT_BUILTINS uuid := '00000000-0000-4000-c000-000000000002';
BEGIN
    RAISE NOTICE 'Testing Exception Infrastructure...';

    -------------------------------------------------------
    -- 1. Check if TypeError is in __builtins__
    -------------------------------------------------------
    v_type_error_id := public.vm_dict_get_item(ID_DT_BUILTINS, 'TypeError');
    PERFORM public.test_assert(v_type_error_id IS NOT NULL, 'TypeError should be in __builtins__');
    
    -------------------------------------------------------
    -- 2. Check Type of TypeError (Metaclass check)
    -------------------------------------------------------
    DECLARE
        v_type_of_type uuid;
        v_type_name text;
    BEGIN
        v_type_of_type := public.vm_get_type(v_type_error_id);
        SELECT tp_name INTO v_type_name FROM public.py_type_object WHERE id = v_type_of_type;
        PERFORM public.test_assert_eq_str(v_type_name, 'type', 'TypeError should be an instance of type');
    END;

    -------------------------------------------------------
    -- 3. Test Storage (Manual Insert)
    -------------------------------------------------------
    DECLARE
        v_real_type_id uuid;
    BEGIN
        v_base_id := gen_random_uuid();
        v_exc_id := gen_random_uuid();
        
        -- v_type_error_id is the Class Object. To instantiate it, we need its Type ID.
        -- Find py_type_object.id where ob_base matches the class object
        SELECT id INTO v_real_type_id FROM public.py_type_object WHERE ob_base = v_type_error_id;
        
        -- Simulate creating an instance: TypeError('msg')
        -- 1. Create Base Object (Type: TypeError)
        INSERT INTO public.py_object (id, ob_type) VALUES (v_base_id, v_real_type_id);
        
        -- 2. Create Exception Object
        INSERT INTO public.py_exception_object (id, ob_base, ex_args) 
        VALUES (v_exc_id, v_base_id, NULL); -- NULL args for now
        
        PERFORM public.test_assert(true, 'Manual exception insertion successful');
    END;

    RAISE NOTICE E'\n✅ PASS: 11_exception_infrastructure';
END $$;
