-- ============================================================================
-- Test: VM LOAD_FAST / STORE_FAST Opcode Test (CPython 3.11)
--
-- Purpose:
--   Tests that LOAD_FAST(124) and STORE_FAST(125) opcode handlers work correctly:
--   - py_opcode_LOAD_FAST / py_opcode_STORE_FAST exist
--   - STORE_FAST stores value from stack into f_fastlocals slot
--   - LOAD_FAST loads from f_fastlocals slot and pushes to stack
--   - LOAD_FAST before assignment raises (local variable referenced before assignment)
--   - Multiple slots (var_num 0, 1, ...)
--   - Negative var_num raises
--   - Integration with py_eval_frame
--
-- Usage:
--   Run after migrations. If any assertion fails, an exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';

    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;

    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_consts_id UUID;
    co_varnames_id UUID;
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;

    const0_id UUID;
    const1_id UUID;
    name_x_id UUID;
    name_y_id UUID;

    fast_arr uuid[];
    stack_len INTEGER;
    popped_id UUID;
    error_occurred BOOLEAN;
    error_message TEXT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM LOAD_FAST / STORE_FAST Opcode Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- Setup
    -- ========================================================================
    RAISE NOTICE 'Setting up test environment...';

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 42);

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 100);

    name_x_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_x_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_x_id, 'x');

    name_y_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_y_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_y_id, 'y');

    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');

    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, ARRAY[name_x_id, name_y_id]);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, empty_tuple_id, empty_str_id, empty_str_id,
        0, co_varnames_id, empty_tuple_id, empty_tuple_id
    );

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);

    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- ========================================================================
    -- Test 1: Functions exist
    -- ========================================================================
    RAISE NOTICE 'Test 1: py_opcode_LOAD_FAST and py_opcode_STORE_FAST exist...';
    test_count := test_count + 1;

    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_load_fast' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_LOAD_FAST does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_store_fast' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_STORE_FAST does not exist';
    END IF;

    RAISE NOTICE '  ✓ py_opcode_LOAD_FAST and py_opcode_STORE_FAST exist';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 2: STORE_FAST stores value in f_fastlocals slot
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: STORE_FAST stores value from stack into f_fastlocals...';
    test_count := test_count + 1;

    PERFORM public.py_stack_push(frame_id, const0_id);
    PERFORM public.py_opcode_STORE_FAST(frame_id, 0);

    SELECT f_fastlocals INTO fast_arr FROM public.py_frame_object WHERE ob_base = frame_id;
    IF coalesce(array_length(fast_arr, 1), 0) < 1 THEN
        RAISE EXCEPTION 'FAIL: f_fastlocals too short after STORE_FAST(0)';
    END IF;
    IF fast_arr[1] IS NULL OR fast_arr[1] != const0_id THEN
        RAISE EXCEPTION 'FAIL: f_fastlocals[1] is %, expected %', fast_arr[1], const0_id;
    END IF;

    SELECT array_length(f_valuestack, 1) INTO stack_len FROM public.py_frame_object WHERE ob_base = frame_id;
    IF stack_len IS NOT NULL AND stack_len != 0 THEN
        RAISE EXCEPTION 'FAIL: Stack not empty after STORE_FAST, size %', stack_len;
    END IF;

    RAISE NOTICE '  ✓ STORE_FAST correctly stores value in f_fastlocals slot';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 3: LOAD_FAST loads from slot and pushes to stack
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: LOAD_FAST loads from f_fastlocals and pushes to stack...';
    test_count := test_count + 1;

    PERFORM public.py_opcode_LOAD_FAST(frame_id, 0);

    SELECT array_length(f_valuestack, 1), f_valuestack[1] INTO stack_len, popped_id
    FROM public.py_frame_object WHERE ob_base = frame_id;
    IF stack_len != 1 OR popped_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: After LOAD_FAST(0) stack has % elements, top is %, expected 1 and %', stack_len, popped_id, const0_id;
    END IF;

    RAISE NOTICE '  ✓ LOAD_FAST correctly loads from slot and pushes to stack';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 4: LOAD_FAST before assignment sets VM error (referenced before assignment)
    -- CPython: opcode sets exception state and returns; eval loop checks py_err_occurred().
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: LOAD_FAST before STORE_FAST sets py_err (referenced before assignment)...';
    test_count := test_count + 1;

    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_fastlocals = array[]::uuid[] WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    PERFORM public.py_opcode_LOAD_FAST(frame_id, 0);

    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Expected py_err_occurred() after LOAD_FAST before assignment';
    END IF;

    RAISE NOTICE '  ✓ LOAD_FAST before assignment correctly sets VM error state';
    pass_count := pass_count + 1;

    PERFORM public.py_err_clear();

    -- ========================================================================
    -- Test 5: STORE_FAST with two slots (var_num 0 and 1)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: STORE_FAST with different var_num (0 and 1)...';
    test_count := test_count + 1;

    UPDATE public.py_frame_object SET f_fastlocals = array[]::uuid[] WHERE ob_base = frame_id;
    PERFORM public.py_stack_push(frame_id, const0_id);
    PERFORM public.py_opcode_STORE_FAST(frame_id, 0);
    PERFORM public.py_stack_push(frame_id, const1_id);
    PERFORM public.py_opcode_STORE_FAST(frame_id, 1);

    SELECT f_fastlocals INTO fast_arr FROM public.py_frame_object WHERE ob_base = frame_id;
    IF coalesce(array_length(fast_arr, 1), 0) < 2 THEN
        RAISE EXCEPTION 'FAIL: f_fastlocals length % after STORE_FAST(0) and STORE_FAST(1)', coalesce(array_length(fast_arr, 1), 0);
    END IF;
    IF fast_arr[1] != const0_id THEN
        RAISE EXCEPTION 'FAIL: f_fastlocals[1] = %, expected %', fast_arr[1], const0_id;
    END IF;
    IF fast_arr[2] != const1_id THEN
        RAISE EXCEPTION 'FAIL: f_fastlocals[2] = %, expected %', fast_arr[2], const1_id;
    END IF;

    RAISE NOTICE '  ✓ STORE_FAST works correctly with different var_num';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 6: STORE_FAST negative var_num raises
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: STORE_FAST with negative var_num raises...';
    test_count := test_count + 1;

    PERFORM public.py_stack_push(frame_id, const0_id);
    error_occurred := FALSE;
    BEGIN
        PERFORM public.py_opcode_STORE_FAST(frame_id, -1);
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;

    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on STORE_FAST(-1)';
    END IF;
    IF error_message NOT LIKE '%non-negative%' THEN
        RAISE EXCEPTION 'FAIL: Expected "non-negative", got: %', error_message;
    END IF;

    RAISE NOTICE '  ✓ STORE_FAST with negative var_num correctly raises';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 7: LOAD_FAST negative var_num raises
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: LOAD_FAST with negative var_num raises...';
    test_count := test_count + 1;

    error_occurred := FALSE;
    BEGIN
        PERFORM public.py_opcode_LOAD_FAST(frame_id, -1);
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
            error_message := SQLERRM;
    END;

    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on LOAD_FAST(-1)';
    END IF;
    IF error_message NOT LIKE '%non-negative%' THEN
        RAISE EXCEPTION 'FAIL: Expected "non-negative", got: %', error_message;
    END IF;

    RAISE NOTICE '  ✓ LOAD_FAST with negative var_num correctly raises';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 8: STORE_FAST with empty stack raises
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: STORE_FAST with empty stack raises...';
    test_count := test_count + 1;

    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[] WHERE ob_base = frame_id;
    error_occurred := FALSE;
    BEGIN
        PERFORM public.py_opcode_STORE_FAST(frame_id, 0);
    EXCEPTION
        WHEN OTHERS THEN
            error_occurred := TRUE;
    END;

    IF NOT error_occurred THEN
        RAISE EXCEPTION 'FAIL: Expected exception on STORE_FAST with empty stack';
    END IF;

    RAISE NOTICE '  ✓ STORE_FAST with empty stack correctly raises';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test 9: py_eval_frame with LOAD_CONST + STORE_FAST + LOAD_FAST + RETURN_VALUE
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 9: py_eval_frame bytecode LOAD_CONST STORE_FAST LOAD_FAST RETURN_VALUE...';
    test_count := test_count + 1;

    -- Bytecode: LOAD_CONST(0) STORE_FAST(0) LOAD_FAST(0) RETURN_VALUE
    -- 100,0  125,0  124,0  83,0  → 64 00 7d 00 7c 00 53 00
    UPDATE public.py_bytes_object SET bytes_value = E'\\x64007d007c005300'::bytea WHERE ob_base = co_code_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_fastlocals = array[]::uuid[], f_lasti = -1 WHERE ob_base = frame_id;

    popped_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF popped_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: py_eval_frame returned NULL (exception?)';
    END IF;
    IF popped_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: py_eval_frame returned %, expected % (const0)', popped_id, const0_id;
    END IF;

    RAISE NOTICE '  ✓ py_eval_frame LOAD_CONST+STORE_FAST+LOAD_FAST+RETURN_VALUE returns correct value';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Summary
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total tests: %', test_count;
    RAISE NOTICE 'Passed: %', pass_count;
    RAISE NOTICE 'Failed: %', fail_count;
    RAISE NOTICE '';

    IF fail_count > 0 THEN
        RAISE EXCEPTION 'Some tests failed. See details above.';
    END IF;

    RAISE NOTICE '✅ All LOAD_FAST / STORE_FAST opcode tests passed!';

END $$;
