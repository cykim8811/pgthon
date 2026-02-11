-- ============================================================================
-- Test: Try/Except Integration (CPython 3.11 exception table)
--
-- Purpose:
--   End-to-end try/except: bytecode that raises (1 + "a" → TypeError), exception
--   table lookup, jump to handler, handler pushes "caught" constant and
--   RETURN_VALUE. Verifies exception dispatch → handler → return path.
--
--   Scenario 1: With exception table — expect return = const 777 (handler ran).
--   Scenario 2: Same bytecode without exception table — expect return NULL,
--               py_err_occurred() true (exception propagates).
--
-- Bytecode (14 bytes):
--   [0]  LOAD_CONST 0   (1)
--   [2]  LOAD_CONST 1   ("a")
--   [4]  BINARY_ADD    → raises TypeError
--   [6]  LOAD_CONST 2   (99, no-exception path)
--   [8]  JUMP_FORWARD 1 → skip handler
--   [10] LOAD_CONST 3   (777, handler: "caught")
--   [12] RETURN_VALUE
--
-- Exception table (code units): start=0, end=3, target=5, depth=0.
--   When BINARY_ADD at byte offset 4 (code unit 2) sets exception,
--   lookup yields target=5 → byte offset 10 → LOAD_CONST 3 then RETURN_VALUE.
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE    uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE   uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';

    frame_id uuid;
    code_obj_id uuid;
    co_code_id uuid;
    co_names_id uuid;
    co_consts_id uuid;
    empty_tuple_id uuid;
    empty_str_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;

    const_1_id uuid;
    const_a_id uuid;
    const_99_id uuid;
    const_777_id uuid;

    exc_table bytea;
    result_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Try/Except Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Constants: 1, "a", 99, 777
    const_1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_1_id, 1);

    const_a_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_a_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const_a_id, 'a');

    const_99_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_99_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_99_id, 99);

    const_777_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_777_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_777_id, 777);

    -- Empty tuple / str for code object
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);

    -- co_consts: (1, "a", 99, 777)
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item)
    VALUES (co_consts_id, ARRAY[const_1_id, const_a_id, const_99_id, const_777_id]);

    -- Bytecode: 100,0 100,1 23,0 100,2 110,1 100,3 83,0
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value)
    VALUES (co_code_id, E'\\x64006401170064026e0164035300'::bytea);

    -- Exception table: start=0, size=3, target=5, depth=0, lasti=0 → 128,3,5,0
    exc_table := decode('80030500', 'hex');

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars, co_exceptiontable
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id, exc_table
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
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    RAISE NOTICE '✓ 34.1 Setup: code with try/except bytecode and exception table';
    RAISE NOTICE '';

    -- Test 1: With exception table — 1+"a" raises, handler runs, return 777
    RAISE NOTICE 'Test 1: 1 + "a" with exception table → handler runs, return 777...';
    PERFORM public.py_err_clear();
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);

    IF result_id IS NULL THEN
        RAISE EXCEPTION '✓ 34.1 FAIL: with exception table expected return 777 (handler), got NULL';
    END IF;
    IF result_id IS DISTINCT FROM const_777_id THEN
        RAISE EXCEPTION '✓ 34.1 FAIL: with exception table expected return const 777 (%), got %', const_777_id, result_id;
    END IF;
    RAISE NOTICE '✓ 34.1 With exception table: return 777 (handler ran)';

    -- Test 2: Same bytecode, no exception table — expect NULL return, exception set
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: same bytecode without exception table → NULL return, py_err_occurred()...';
    UPDATE public.py_code_object SET co_exceptiontable = NULL WHERE ob_base = code_obj_id;
    PERFORM public.py_err_clear();
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);

    IF result_id IS NOT NULL THEN
        RAISE EXCEPTION '✓ 34.2 FAIL: without exception table expected NULL return, got %', result_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION '✓ 34.2 FAIL: without exception table expected py_err_occurred() true';
    END IF;
    PERFORM public.py_err_clear();
    RAISE NOTICE '✓ 34.2 Without exception table: NULL return, exception propagated';

    RAISE NOTICE '';
    RAISE NOTICE 'Test Summary: Try/except integration (34.x) passed.';
END $$;
