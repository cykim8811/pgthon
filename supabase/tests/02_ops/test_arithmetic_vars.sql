-- Test: 02 Ops - Arithmetic and Variables
-- Verify LOAD_CONST, STORE_FAST, LOAD_FAST, BINARY_ADD
DO $$
DECLARE
    -- a = 10
    -- b = 20
    -- return a + b (30)
    v_source TEXT := 
'LOAD_CONST 10
STORE_FAST a
LOAD_CONST 20
STORE_FAST b
LOAD_FAST a
LOAD_FAST b
BINARY_ADD
RETURN_VALUE';

    v_res UUID;
    v_val BIGINT;
BEGIN
    v_res := public.vm_execute_source(v_source);
    
    -- Check result
    SELECT long_value INTO v_val FROM public.py_long_object WHERE ob_base = v_res;
    PERFORM public.test_assert_eq_int(v_val, 30, '10 + 20 should be 30');
    
    -- Test Chaining: 1 + 2 + 3
    v_source := 
'LOAD_CONST 1
LOAD_CONST 2
BINARY_ADD
LOAD_CONST 3
BINARY_ADD
RETURN_VALUE';
    v_res := public.vm_execute_source(v_source);
    SELECT long_value INTO v_val FROM public.py_long_object WHERE ob_base = v_res;
    PERFORM public.test_assert_eq_int(v_val, 6, '1 + 2 + 3 should be 6');

END $$;
