-- ============================================================================
-- Test: VM BUILD_SLICE(133) Opcode (CPython 3.11)
--
-- Purpose:
--   BUILD_SLICE(oparg): oparg 2 → slice(start, stop, None); oparg 3 → slice(start, stop, step).
--   Stack: ... start, stop [ , step ] → ... slice.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_SLICE_TYPE UUID := '00000000-0000-4000-a000-000000000016';
    ID_NONE_OBJ UUID := '00000000-0000-4000-b000-000000000001';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';

    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_consts_id UUID;
    empty_tuple_id UUID;
    empty_str_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    locals_dict_id UUID;
    start_id UUID;
    stop_id UUID;
    step_id UUID;
    result_id UUID;
    r_start UUID;
    r_stop UUID;
    r_step UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM BUILD_SLICE(133) Opcode Test (CPython 3.11)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    start_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (start_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (start_id, 0);
    stop_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (stop_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (stop_id, 3);
    step_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (step_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (step_id, 1);

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_build_slice' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_BUILD_SLICE does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_BUILD_SLICE exists';
    pass_count := pass_count + 1;

    -- BUILD_SLICE(2): consts [start, stop]. Bytecode LOAD_CONST 0,1 BUILD_SLICE 2 RETURN. 64 00 64 01 85 02 53 00
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[start_id, stop_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_bytes_object SET bytes_value = E'\\x6400640185025300'::bytea WHERE ob_base = co_code_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: BUILD_SLICE(2) returned NULL'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_slice_object WHERE ob_base = result_id) THEN RAISE EXCEPTION 'FAIL: expected slice object'; END IF;
    SELECT ob_start, ob_stop, ob_step INTO r_start, r_stop, r_step FROM public.py_slice_object WHERE ob_base = result_id;
    IF r_start != start_id OR r_stop != stop_id OR r_step != ID_NONE_OBJ THEN RAISE EXCEPTION 'FAIL: slice(0,3,None) wrong fields'; END IF;
    RAISE NOTICE '  ✓ BUILD_SLICE(2) → slice(start, stop, None)';
    pass_count := pass_count + 1;

    -- BUILD_SLICE(3): consts [start, stop, step]. 64 00 64 01 64 02 85 03 53 00
    test_count := test_count + 1;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[start_id, stop_id, step_id] WHERE ob_base = co_consts_id;
    UPDATE public.py_bytes_object SET bytes_value = E'\\x64006401640285035300'::bytea WHERE ob_base = co_code_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;
    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: BUILD_SLICE(3) returned NULL'; END IF;
    SELECT ob_start, ob_stop, ob_step INTO r_start, r_stop, r_step FROM public.py_slice_object WHERE ob_base = result_id;
    IF r_start != start_id OR r_stop != stop_id OR r_step != step_id THEN RAISE EXCEPTION 'FAIL: slice(0,3,1) wrong fields'; END IF;
    RAISE NOTICE '  ✓ BUILD_SLICE(3) → slice(start, stop, step)';
    pass_count := pass_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE '✅ All BUILD_SLICE(133) opcode tests passed!';
END $$;
