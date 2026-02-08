-- ============================================================================
-- Test: KW_NAMES + PRECALL + CALL opcode integration (CPython 3.11 call protocol)
--
-- Purpose:
--   Verifies KW_NAMES(172) + PRECALL(166) + CALL(171) build kwargs from
--   co_consts[keyword names tuple] and call py_object_call(..., kwargs_id).
--   Tests that passing keyword args to builtins that do not accept them (len)
--   raises TypeError: len() takes no keyword arguments.
--
-- Design: docs/CALL_PROTOCOL_3_11_DESIGN.md
-- ============================================================================

DO $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_TYPE_ERROR_TYPE UUID := '00000000-0000-4000-a000-000000000022';

    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_names_id UUID;
    co_consts_id UUID;
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    real_builtins_dict_id UUID;
    len_str_id UUID;
    const_hello_id UUID;
    const_x_id UUID;
    result_id UUID;
    error_message TEXT;
    got_exc_type_id UUID;
    kw_names_tuple_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'KW_NAMES + CALL Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    SELECT md_dict INTO real_builtins_dict_id
    FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;
    IF real_builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ dict not found';
    END IF;

    SELECT ob_base INTO len_str_id FROM public.py_unicode_object WHERE str_value = 'len' LIMIT 1;
    IF len_str_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: ''len'' string not found';
    END IF;

    const_hello_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_hello_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const_hello_id, 'hello');

    const_x_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_x_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const_x_id, 'x');

    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, (SELECT ob_base FROM public.py_type_object WHERE tp_name = 'tuple' LIMIT 1));
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    builtins_dict_id := real_builtins_dict_id;

    -- co_consts[0] = tuple of keyword names ('x'); co_consts[1] = 'hello'
    kw_names_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (kw_names_tuple_id, (SELECT ob_base FROM public.py_type_object WHERE tp_name = 'tuple' LIMIT 1));
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (kw_names_tuple_id, ARRAY[const_x_id]);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, (SELECT ob_base FROM public.py_type_object WHERE tp_name = 'tuple' LIMIT 1));
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[kw_names_tuple_id, const_hello_id]);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, (SELECT ob_base FROM public.py_type_object WHERE tp_name = 'tuple' LIMIT 1));
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[len_str_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- Bytecode (CPython 3.11): LOAD_NAME 0, LOAD_CONST 1 ('hello' pos), LOAD_CONST 1 ('hello' kw val), KW_NAMES 0, PRECALL 1, CALL 1, RETURN_VALUE
    -- 101,0 100,1 100,1 172,0 166,1 171,1 83,0
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id,
        decode('650064016401ac00a601ab015300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, (SELECT ob_base FROM public.py_type_object WHERE tp_name = 'type' LIMIT 1));
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, (SELECT ob_base FROM public.py_type_object WHERE tp_name = 'type' LIMIT 1));
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    -- 명세: kwargs 거부 시 py_call_cfunction는 Python TypeError 세팅 후 NULL 반환; py_eval_frame도 NULL 반환.
    PERFORM public.py_err_clear();
    result_id := public.py_eval_frame(frame_id);
    IF result_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: len(..., x=...) should return NULL (TypeError), got result_id %', result_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: len(..., x=...) should set Python exception';
    END IF;
    SELECT exc_type_id INTO got_exc_type_id FROM public.py_exception_state WHERE id = (SELECT id FROM public.py_exception_state LIMIT 1);
    IF got_exc_type_id IS DISTINCT FROM ID_TYPE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: expected TypeError, got exc_type_id %', got_exc_type_id;
    END IF;
    SELECT u.str_value INTO error_message
    FROM public.py_exception_state e
    JOIN public.py_base_exception_object b ON b.ob_base = e.exc_value_id
    JOIN public.py_tuple_object t ON t.ob_base = b.ob_args
    JOIN public.py_unicode_object u ON u.ob_base = t.ob_item[1]
    WHERE e.id = (SELECT id FROM public.py_exception_state LIMIT 1);
    IF error_message IS NULL OR error_message NOT LIKE '%len() takes no keyword arguments%' THEN
        RAISE EXCEPTION 'FAIL: expected "len() takes no keyword arguments", got: %', error_message;
    END IF;
    RAISE NOTICE '✓ 36.1 KW_NAMES+CALL len(hello, x=hello) raises TypeError: len() takes no keyword arguments';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'KW_NAMES + CALL integration: all checks passed';
    RAISE NOTICE '========================================';
END;
$$;
