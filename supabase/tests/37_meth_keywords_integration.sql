-- ============================================================================
-- Test: METH_KEYWORDS builtin integration
--
-- Purpose:
--   Verifies that builtins with METH_KEYWORDS accept kwargs via
--   py_object_call(..., kwargs_id) and that py_call_cfunction dispatches
--   to ml_meth(func_obj_id, args, kwargs_id). Tests first_kwarg builtin.
--
-- Design: docs/KWARGS_IMPLEMENTATION_PLAN.md Phase 3
-- ============================================================================

DO $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_NONE_OBJ UUID := '00000000-0000-4000-b000-000000000001';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';

    builtins_dict_id UUID;
    first_kwarg_str_id UUID;
    first_kwarg_func_id UUID;
    kwargs_dict_id UUID;
    key_x_id UUID;
    value_42_id UUID;
    result_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'METH_KEYWORDS Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    SELECT md_dict INTO builtins_dict_id
    FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;
    IF builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ dict not found';
    END IF;

    SELECT ob_base INTO first_kwarg_str_id FROM public.py_unicode_object WHERE str_value = 'first_kwarg' LIMIT 1;
    IF first_kwarg_str_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: ''first_kwarg'' string not found';
    END IF;

    first_kwarg_func_id := public.py_dict_get_item(builtins_dict_id, first_kwarg_str_id);
    IF first_kwarg_func_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: first_kwarg not found in __builtins__';
    END IF;

    -- Test 1: first_kwarg(kwargs={'x': 42}) returns 42 (first value from kwargs)
    key_x_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (key_x_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (key_x_id, 'x');

    value_42_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_42_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_42_id, 42);

    kwargs_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (kwargs_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (kwargs_dict_id);
    PERFORM public.py_dict_set_item(kwargs_dict_id, key_x_id, value_42_id);

    result_id := public.py_object_call(first_kwarg_func_id, ARRAY[]::uuid[], kwargs_dict_id);
    IF result_id IS DISTINCT FROM value_42_id THEN
        RAISE EXCEPTION 'FAIL: first_kwarg(x=42) expected %, got %', value_42_id, result_id;
    END IF;
    RAISE NOTICE '✓ 37.1 first_kwarg(x=42) returns 42';

    -- Test 2: first_kwarg(kwargs=NULL) returns None
    result_id := public.py_object_call(first_kwarg_func_id, ARRAY[]::uuid[], NULL);
    IF result_id IS DISTINCT FROM ID_NONE_OBJ THEN
        RAISE EXCEPTION 'FAIL: first_kwarg(kwargs=NULL) expected None (%), got %', ID_NONE_OBJ, result_id;
    END IF;
    RAISE NOTICE '✓ 37.2 first_kwarg(kwargs=NULL) returns None';

    -- Test 3: first_kwarg(kwargs={}) empty dict returns None
    kwargs_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (kwargs_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (kwargs_dict_id);

    result_id := public.py_object_call(first_kwarg_func_id, ARRAY[]::uuid[], kwargs_dict_id);
    IF result_id IS DISTINCT FROM ID_NONE_OBJ THEN
        RAISE EXCEPTION 'FAIL: first_kwarg({{}}) expected None (%), got %', ID_NONE_OBJ, result_id;
    END IF;
    RAISE NOTICE '✓ 37.3 first_kwarg({{}}) returns None';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'METH_KEYWORDS integration: all checks passed';
    RAISE NOTICE '========================================';
END;
$$;
