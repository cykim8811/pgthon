-- =====================================================
-- Test 12: Exception Creation
-- Description: Verify vm_create_exception creates valid exception objects
-- =====================================================

DO $$
DECLARE
    v_type_err_class uuid;
    v_type_err_type_id uuid;
    v_exc_obj uuid;
    v_args_obj uuid;
    v_msg_obj uuid;
    v_msg_val text;
    v_obj_type uuid;
    v_type_name text;
    
    ID_DT_BUILTINS uuid := '00000000-0000-4000-c000-000000000002';
    ID_TUP_TYPE uuid := '00000000-0000-4000-a000-000000000007';
BEGIN
    RAISE NOTICE 'Testing Exception Creation...';

    -- 1. Get TypeError Type ID
    v_type_err_class := public.vm_dict_get_item(ID_DT_BUILTINS, 'TypeError');
    -- v_type_err_class is ob_base of the class object. We need its TYPE ID (py_type_object.id)
    SELECT id INTO v_type_err_type_id FROM public.py_type_object WHERE ob_base = v_type_err_class;
    
    -- 2. Create Exception Instance: TypeError("Something went wrong")
    v_exc_obj := public.vm_create_exception(v_type_err_type_id, 'Something went wrong');
    
    PERFORM public.test_assert(v_exc_obj IS NOT NULL, 'Exception object creation failed');
    
    -- 3. Verify Type
    v_obj_type := public.vm_get_type(v_exc_obj);
    PERFORM public.test_assert(v_obj_type = v_type_err_type_id, 'Exception has incorrect type');
    
    -- 4. Verify Arguments (ex_args)
    -- We need to access ex_args column from py_exception_object
    SELECT ex_args INTO v_args_obj FROM public.py_exception_object WHERE ob_base = v_exc_obj;
    PERFORM public.test_assert(v_args_obj IS NOT NULL, 'ex_args is NULL');
    
    -- Verify args type is tuple
    PERFORM public.test_assert(public.vm_get_type(v_args_obj) = ID_TUP_TYPE, 'args is not a tuple');
    
    -- 5. Verify Message Content
    -- args[0] should be the message
    v_msg_obj := public.vm_tuple_getitem(v_args_obj, 0);
    v_msg_val := public.vm_get_str_value(v_msg_obj);
    
    PERFORM public.test_assert_eq_str(v_msg_val, 'Something went wrong', 'Exception message mismatch');

    RAISE NOTICE E'\n✅ PASS: 12_exception_creation';
END $$;
