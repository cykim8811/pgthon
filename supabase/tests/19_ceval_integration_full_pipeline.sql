-- ============================================================================
-- Test: VM Full Pipeline Integration
--
-- Purpose:
--   Bytecode sequences that exercise STORE_NAME → LOAD_NAME → RETURN_VALUE
--   (and BINARY_ADD) in a single py_eval_frame call. Ensures name storage,
--   lookup (dict API), and BINARY_ADD work together in end-to-end scenarios.
--
--   Scenarios:
--   1. a=1; b=2; return a  →  1
--   2. a=1; b=2; return a+b  →  3
--   3. x='a'; y='b'; return x+y  →  "ab"
--   4. a=1; b=2; return (a < b)  →  True  (COMPARE_OP + names)
--   5. a=1; b=2; if a < b: return a+b else return 0  →  3  (compare + POP_JUMP_IF_FALSE + return)
--
-- Usage:
--   Run after migrations. If any assertion fails, an exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';

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

    const0_id UUID;
    const1_id UUID;
    name_a_id UUID;
    name_b_id UUID;
    name_x_id UUID;
    name_y_id UUID;
    str_a_id UUID;
    str_b_id UUID;
    result_id UUID;
    result_num NUMERIC;
    result_txt TEXT;
    const_zero_id UUID;
    ID_TRUE_OBJ UUID := '00000000-0000-4000-b000-000000000010';
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM Full Pipeline Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Constants: 1, 2
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 2);

    -- Names: 'a', 'b'
    name_a_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_a_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_a_id, 'a');
    name_b_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_b_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_b_id, 'b');

    -- For x='a'; y='b'; return x+y
    str_a_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_a_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_a_id, 'a');
    str_b_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_b_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_b_id, 'b');
    name_x_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_x_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_x_id, 'x');
    name_y_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_y_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_y_id, 'y');

    SELECT md_dict INTO real_builtins_dict_id
    FROM public.py_module_object
    WHERE ob_base = ID_BUILTINS_MODULE;
    IF real_builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ dict not found';
    END IF;

    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
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
    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_a_id, name_b_id]);

    -- Bytecode: LOAD_CONST(0) STORE_NAME(0) LOAD_CONST(1) STORE_NAME(1) LOAD_NAME(0) RETURN_VALUE
    -- a=1; b=2; return a
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005a0064015a0165005300'::bytea);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, real_builtins_dict_id
    );

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL OR result_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: full pipeline (a=1;b=2;return a) expected const0_id (1), got %', result_id;
    END IF;
    IF public.py_dict_get_item(locals_dict_id, name_a_id) != const0_id
       OR public.py_dict_get_item(locals_dict_id, name_b_id) != const1_id THEN
        RAISE EXCEPTION 'FAIL: after pipeline, py_dict_get_item(locals,a/b) should return 1 and 2';
    END IF;

    RAISE NOTICE '  ✓ Full pipeline (a=1; b=2; return a) → 1, dict API consistent';

    -- Test 2: a=1; b=2; return a+b  →  3  (STORE_NAME + LOAD_NAME + BINARY_ADD)
    -- Bytecode: LOAD_CONST(0) STORE_NAME(0) LOAD_CONST(1) STORE_NAME(1) LOAD_NAME(0) LOAD_NAME(1) BINARY_ADD RETURN_VALUE
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005a0064015a016500650117005300'::bytea);
    UPDATE public.py_code_object SET co_code = co_code_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: full pipeline (a=1;b=2;return a+b) returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 3 THEN
        RAISE EXCEPTION 'FAIL: full pipeline (a=1;b=2;return a+b) expected 3, got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ Full pipeline (a=1; b=2; return a+b) → 3';

    -- Test 3: x='a'; y='b'; return x+y  →  "ab"  (BINARY_ADD str+str via names)
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[str_a_id, str_b_id]);
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_x_id, name_y_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005a0064015a016500650117005300'::bytea);
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: full pipeline (x=''a'';y=''b'';return x+y) returned NULL';
    END IF;
    SELECT str_value INTO result_txt FROM public.py_unicode_object WHERE ob_base = result_id;
    IF result_txt IS NULL OR result_txt <> 'ab' THEN
        RAISE EXCEPTION 'FAIL: full pipeline (x=''a'';y=''b'';return x+y) expected "ab", got %', COALESCE(result_txt, 'NULL');
    END IF;
    RAISE NOTICE '  ✓ Full pipeline (x=''a''; y=''b''; return x+y) → "ab"';

    -- Test 4: a=1; b=2; return (a < b)  →  True  (names + COMPARE_OP + RETURN_VALUE)
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_a_id, name_b_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- LOAD_CONST 0 STORE_NAME 0 LOAD_CONST 1 STORE_NAME 1 LOAD_NAME 0 LOAD_NAME 1 COMPARE_OP 0 (<) RETURN_VALUE
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005a0064015a01650065016b005300'::bytea);
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: full pipeline (a=1;b=2;return a<b) returned NULL';
    END IF;
    IF result_id IS DISTINCT FROM ID_TRUE_OBJ THEN
        RAISE EXCEPTION 'FAIL: full pipeline (a=1;b=2;return a<b) expected True, got %', result_id;
    END IF;
    RAISE NOTICE '  ✓ Full pipeline (a=1; b=2; return (a < b)) → True';

    -- Test 5: a=1; b=2; if a < b: return a+b else return 0  →  3  (compare + POP_JUMP_IF_FALSE + BINARY_ADD / LOAD_CONST 0)
    const_zero_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_zero_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_zero_id, 0);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const_zero_id]);
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_a_id, name_b_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- a=1 b=2 LOAD_NAME a LOAD_NAME b COMPARE_OP < POP_JUMP_IF_FALSE 4 (->24) LOAD_NAME a LOAD_NAME b BINARY_ADD RETURN_VALUE LOAD_CONST 2(0) RETURN_VALUE
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005a0064015a01650065016b007204650065011700530064025300'::bytea);
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: full pipeline (if a<b return a+b else return 0) returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 3 THEN
        RAISE EXCEPTION 'FAIL: full pipeline (if a<b return a+b else 0) expected 3, got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ Full pipeline (a=1; b=2; if a < b: return a+b else return 0) → 3';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✓ Full pipeline integration test passed';
    RAISE NOTICE '========================================';
END $$;
