-- ============================================================================
-- Test: tp_call kwargs rejection (CPython fidelity)
--
-- Purpose:
--   Verifies that passing kwargs to builtins that do not accept keyword
--   arguments raises TypeError with CPython-exact message:
--   "len() takes no keyword arguments" (name without quotes).
--
-- Design: docs/KWARGS_IMPLEMENTATION_PLAN.md, docs/TP_CALL_KWARGS_DESIGN.md
-- ============================================================================

DO $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_LEN_FUNCTION UUID := '00000000-0000-4000-b000-000000000003';
    ID_ABS_FUNCTION UUID := '00000000-0000-4000-b000-000000000004';

    len_func_id UUID;
    abs_func_id UUID;
    arg_id UUID;
    kwargs_dict_id UUID;
    result_id UUID;
    error_message TEXT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'tp_call kwargs rejection (CPython fidelity)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup: one positional arg for len/abs, one non-empty dict as kwargs
    -- CPython ignores empty kwargs (PyDict_GET_SIZE == 0), so use a non-empty dict
    arg_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (arg_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (arg_id, 'hello');

    kwargs_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (kwargs_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (kwargs_dict_id);
    -- Add a dummy kwarg to make it non-empty
    DECLARE
        kw_key_id UUID;
        kw_val_id UUID;
    BEGIN
        kw_key_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (kw_key_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (kw_key_id, 'foo');
        kw_val_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (kw_val_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (kw_val_id, 'bar');
        PERFORM public.py_dict_set_item(kwargs_dict_id, kw_key_id, kw_val_id);
    END;

    len_func_id := ID_LEN_FUNCTION;
    abs_func_id := ID_ABS_FUNCTION;

    -- Test 1: len() with kwargs → Python TypeError (py_err_set_type_error), NULL 반환. CPython: "len() takes no keyword arguments"
    PERFORM public.py_err_clear();
    result_id := public.py_object_call(len_func_id, ARRAY[arg_id], kwargs_dict_id);
    IF result_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: py_object_call(len, args, kwargs) should return NULL';
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: py_object_call(len, args, kwargs) should set Python exception';
    END IF;
    SELECT u.str_value INTO error_message
    FROM public.py_exception_state e
    JOIN public.py_base_exception_object b ON b.ob_base = e.exc_value_id
    JOIN public.py_tuple_object t ON t.ob_base = b.ob_args
    JOIN public.py_unicode_object u ON u.ob_base = t.ob_item[1]
    WHERE e.id = (SELECT id FROM public.py_exception_state LIMIT 1);
    IF error_message IS NULL OR error_message NOT LIKE '%takes no keyword arguments%' THEN
        RAISE EXCEPTION 'FAIL: expected TypeError message containing "takes no keyword arguments", got: %', error_message;
    END IF;
    IF error_message LIKE '%''len''%' THEN
        RAISE EXCEPTION 'FAIL: function name must not be quoted (CPython: len() not ''len''()), got: %', error_message;
    END IF;
    RAISE NOTICE '✓ 35.1 len() with kwargs raises TypeError: len() takes no keyword arguments';

    -- Test 2: abs() with kwargs → Python TypeError, NULL 반환
    PERFORM public.py_err_clear();
    result_id := public.py_object_call(abs_func_id, ARRAY[arg_id], kwargs_dict_id);
    IF result_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: py_object_call(abs, args, kwargs) should return NULL';
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: py_object_call(abs, args, kwargs) should set Python exception';
    END IF;
    SELECT u.str_value INTO error_message
    FROM public.py_exception_state e
    JOIN public.py_base_exception_object b ON b.ob_base = e.exc_value_id
    JOIN public.py_tuple_object t ON t.ob_base = b.ob_args
    JOIN public.py_unicode_object u ON u.ob_base = t.ob_item[1]
    WHERE e.id = (SELECT id FROM public.py_exception_state LIMIT 1);
    IF error_message IS NULL OR error_message NOT LIKE '%abs() takes no keyword arguments%' THEN
        RAISE EXCEPTION 'FAIL: expected message containing "abs() takes no keyword arguments", got: %', error_message;
    END IF;
    IF error_message LIKE '%''abs''%' THEN
        RAISE EXCEPTION 'FAIL: function name must not be quoted (CPython), got: %', error_message;
    END IF;
    RAISE NOTICE '✓ 35.2 abs() with kwargs raises TypeError: abs() takes no keyword arguments';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'tp_call kwargs rejection: all checks passed';
    RAISE NOTICE '========================================';
END;
$$;
