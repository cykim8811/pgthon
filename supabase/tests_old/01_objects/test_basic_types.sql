-- Test: 01 Objects - Basic Types
-- Verify integer and string creation and type checks
DO $$
DECLARE
    v_int_id UUID;
    v_str_id UUID;
    v_type_id UUID;
    v_type_name TEXT;
    
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    
    v_val BIGINT;
    v_sval TEXT;
BEGIN
    -- 1. Integer Test
    v_int_id := public.vm_assembler_get_or_create_const('42');
    v_type_id := public.vm_get_type(v_int_id);
    
    PERFORM public.test_assert(v_type_id = ID_INT_TYPE, 'Integer type check');
    
    SELECT long_value INTO v_val FROM public.py_long_object WHERE ob_base = v_int_id;
    PERFORM public.test_assert_eq_int(v_val, 42, 'Integer value check');

    -- 2. String Test
    v_str_id := public.vm_assembler_get_or_create_const('hello');
    v_type_id := public.vm_get_type(v_str_id);
    PERFORM public.test_assert(v_type_id = ID_STR_TYPE, 'String type check');
    
    SELECT str_value INTO v_sval FROM public.py_unicode_object WHERE ob_base = v_str_id;
    PERFORM public.test_assert(v_sval = 'hello', 'String value check');
END $$;
