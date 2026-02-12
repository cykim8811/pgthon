-- ============================================================================
-- Test 84: SWAP, Comprehension Opcodes, F-String Opcodes
--
-- Tests:
--   1. SWAP(2): swap TOS and TOS-1
--   2. BUILD_SET(3): build set from 3 stack items
--   3. LIST_APPEND: append to list (list comprehension pattern)
--   4. SET_ADD: add to set (set comprehension pattern)
--   5. MAP_ADD: add key-value to dict (dict comprehension pattern)
--   6. FORMAT_VALUE(0): FVC_NONE — int → str
--   7. FORMAT_VALUE(1): FVC_STR — int → str()
--   8. FORMAT_VALUE(2): FVC_REPR — str → repr()
--   9. BUILD_STRING(2): concatenate two strings
--  10. F-string combo: FORMAT_VALUE + BUILD_STRING (f"x={42}")
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE   uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE   uuid := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE  uuid := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE  uuid := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE uuid := '00000000-0000-4000-a000-000000000007';
    ID_SET_TYPE   uuid := '00000000-0000-4000-a000-000000000018';

    test_count int := 0;
    pass_count int := 0;

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

    const0_id uuid;
    const1_id uuid;
    const2_id uuid;
    result_id uuid;
    result_int numeric;
    result_str text;
    result_type uuid;
    result_items uuid[];
    result_count int;

    -- dict entry vars
    v_key text;
    v_val text;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'SWAP, Comprehension, F-String Opcodes Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup shared test infrastructure
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);

    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, array[]::uuid[]);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);

    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    -- =========================================================================
    -- Test 1: SWAP(2) — push 10, push 20, SWAP(2) → TOS=10
    -- RESUME(0) LOAD_CONST(0) LOAD_CONST(1) SWAP(2) RETURN_VALUE
    -- consts: [10, 20]
    -- hex: 97006400640163025300
    -- =========================================================================
    RAISE NOTICE 'Test 1: SWAP(2) — push 10,20 swap → TOS=10...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 10);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 20);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('97006400640163025300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: SWAP(2) returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int <> 10 THEN
        RAISE EXCEPTION 'FAIL: SWAP(2) TOS=%, expected 10', result_int;
    END IF;
    RAISE NOTICE '  ✓ SWAP(2): TOS=10 after swapping [10,20]';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 2: BUILD_SET(3) — push 1,2,3 → BUILD_SET(3) → set with 3 items
    -- RESUME(0) LOAD_CONST(0) LOAD_CONST(1) LOAD_CONST(2) BUILD_SET(3) RETURN_VALUE
    -- consts: [1, 2, 3]
    -- hex: 970064006401640268035300
    -- =========================================================================
    RAISE NOTICE 'Test 2: BUILD_SET(3) — {1, 2, 3}...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 2);
    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const2_id, 3);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const2_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064006401640268035300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: BUILD_SET(3) returned NULL'; END IF;
    SELECT ob_type INTO result_type FROM public.py_object WHERE id = result_id;
    IF result_type <> ID_SET_TYPE THEN
        RAISE EXCEPTION 'FAIL: BUILD_SET(3) result type is not set';
    END IF;
    SELECT ob_item INTO result_items FROM public.py_set_object WHERE ob_base = result_id;
    IF array_length(result_items, 1) <> 3 THEN
        RAISE EXCEPTION 'FAIL: BUILD_SET(3) has % items, expected 3', array_length(result_items, 1);
    END IF;
    RAISE NOTICE '  ✓ BUILD_SET(3): set with 3 items';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 3: LIST_APPEND — BUILD_LIST(0), LOAD_CONST(0), LIST_APPEND(1), RETURN_VALUE
    -- consts: [42]
    -- hex: 97006700640091015300
    -- After: list contains [42]
    -- =========================================================================
    RAISE NOTICE 'Test 3: LIST_APPEND — [].append(42) → [42]...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 42);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('97006700640091015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: LIST_APPEND returned NULL'; END IF;
    SELECT ob_type INTO result_type FROM public.py_object WHERE id = result_id;
    IF result_type <> ID_LIST_TYPE THEN
        RAISE EXCEPTION 'FAIL: LIST_APPEND result type is not list';
    END IF;
    SELECT ob_item INTO result_items FROM public.py_list_object WHERE ob_base = result_id;
    IF array_length(result_items, 1) <> 1 THEN
        RAISE EXCEPTION 'FAIL: LIST_APPEND list has % items, expected 1', array_length(result_items, 1);
    END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_items[1];
    IF result_int <> 42 THEN
        RAISE EXCEPTION 'FAIL: LIST_APPEND list[0]=%, expected 42', result_int;
    END IF;
    RAISE NOTICE '  ✓ LIST_APPEND: [42]';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 4: SET_ADD — BUILD_SET(0), LOAD_CONST(0), SET_ADD(1), RETURN_VALUE
    -- consts: [99]
    -- hex: 97006800640092015300
    -- =========================================================================
    RAISE NOTICE 'Test 4: SET_ADD — set().add(99) → {99}...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 99);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('97006800640092015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: SET_ADD returned NULL'; END IF;
    SELECT ob_type INTO result_type FROM public.py_object WHERE id = result_id;
    IF result_type <> ID_SET_TYPE THEN
        RAISE EXCEPTION 'FAIL: SET_ADD result type is not set';
    END IF;
    SELECT ob_item INTO result_items FROM public.py_set_object WHERE ob_base = result_id;
    IF array_length(result_items, 1) <> 1 THEN
        RAISE EXCEPTION 'FAIL: SET_ADD set has % items, expected 1', array_length(result_items, 1);
    END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_items[1];
    IF result_int <> 99 THEN
        RAISE EXCEPTION 'FAIL: SET_ADD set element=%, expected 99', result_int;
    END IF;
    RAISE NOTICE '  ✓ SET_ADD: {99}';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 5: MAP_ADD — BUILD_MAP(0), LOAD_CONST(0='key'), LOAD_CONST(1='val'), MAP_ADD(1), RETURN_VALUE
    -- consts: ['key', 'val']
    -- hex: 970069006400640193015300
    -- =========================================================================
    RAISE NOTICE 'Test 5: MAP_ADD — {}["key"]="val" → {"key": "val"}...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const0_id, 'key');
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const1_id, 'val');

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970069006400640193015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: MAP_ADD returned NULL'; END IF;
    SELECT ob_type INTO result_type FROM public.py_object WHERE id = result_id;
    IF result_type <> ID_DICT_TYPE THEN
        RAISE EXCEPTION 'FAIL: MAP_ADD result type is not dict';
    END IF;
    -- Check dict has one entry with key='key', value='val'
    SELECT count(*) INTO result_count FROM public.py_dict_entry WHERE dict_id = result_id;
    IF result_count <> 1 THEN
        RAISE EXCEPTION 'FAIL: MAP_ADD dict has % entries, expected 1', result_count;
    END IF;
    SELECT u.str_value INTO v_key
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = result_id LIMIT 1;
    IF v_key <> 'key' THEN
        RAISE EXCEPTION 'FAIL: MAP_ADD dict key=%, expected key', v_key;
    END IF;
    SELECT u.str_value INTO v_val
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_value
    WHERE e.dict_id = result_id LIMIT 1;
    IF v_val <> 'val' THEN
        RAISE EXCEPTION 'FAIL: MAP_ADD dict value=%, expected val', v_val;
    END IF;
    RAISE NOTICE '  ✓ MAP_ADD: {"key": "val"}';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 6: FORMAT_VALUE(0) — FVC_NONE, no fmt spec: int 42 → str "42"
    -- RESUME(0) LOAD_CONST(0) FORMAT_VALUE(0) RETURN_VALUE
    -- consts: [42]
    -- hex: 970064009b005300
    -- =========================================================================
    RAISE NOTICE 'Test 6: FORMAT_VALUE(0) FVC_NONE — 42 → "42"...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 42);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064009b005300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: FORMAT_VALUE(0) returned NULL'; END IF;
    SELECT ob_type INTO result_type FROM public.py_object WHERE id = result_id;
    IF result_type <> ID_STR_TYPE THEN
        RAISE EXCEPTION 'FAIL: FORMAT_VALUE(0) result type is not str';
    END IF;
    SELECT str_value INTO result_str FROM public.py_unicode_object WHERE ob_base = result_id;
    IF result_str <> '42' THEN
        RAISE EXCEPTION 'FAIL: FORMAT_VALUE(0) result=%, expected "42"', result_str;
    END IF;
    RAISE NOTICE '  ✓ FORMAT_VALUE(0): 42 → "42"';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 7: FORMAT_VALUE(1) — FVC_STR: int 42 → str "42"
    -- hex: 970064009b015300
    -- =========================================================================
    RAISE NOTICE 'Test 7: FORMAT_VALUE(1) FVC_STR — 42 → "42"...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 42);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064009b015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: FORMAT_VALUE(1) returned NULL'; END IF;
    SELECT str_value INTO result_str FROM public.py_unicode_object WHERE ob_base = result_id;
    IF result_str <> '42' THEN
        RAISE EXCEPTION 'FAIL: FORMAT_VALUE(1) result=%, expected "42"', result_str;
    END IF;
    RAISE NOTICE '  ✓ FORMAT_VALUE(1): 42 → "42"';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 8: FORMAT_VALUE(2) — FVC_REPR: str 'hello' → repr "'hello'"
    -- hex: 970064009b025300
    -- =========================================================================
    RAISE NOTICE 'Test 8: FORMAT_VALUE(2) FVC_REPR — "hello" → "''hello''"...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const0_id, 'hello');

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064009b025300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: FORMAT_VALUE(2) returned NULL'; END IF;
    SELECT str_value INTO result_str FROM public.py_unicode_object WHERE ob_base = result_id;
    IF result_str <> '''hello''' THEN
        RAISE EXCEPTION 'FAIL: FORMAT_VALUE(2) result=%, expected ''hello''', result_str;
    END IF;
    RAISE NOTICE '  ✓ FORMAT_VALUE(2): "hello" → "''hello''"';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 9: BUILD_STRING(2) — "hello" + " world" → "hello world"
    -- RESUME(0) LOAD_CONST(0) LOAD_CONST(1) BUILD_STRING(2) RETURN_VALUE
    -- consts: ['hello', ' world']
    -- hex: 9700640064019d025300
    -- =========================================================================
    RAISE NOTICE 'Test 9: BUILD_STRING(2) — "hello" + " world"...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const0_id, 'hello');
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const1_id, ' world');

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('9700640064019d025300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: BUILD_STRING(2) returned NULL'; END IF;
    SELECT str_value INTO result_str FROM public.py_unicode_object WHERE ob_base = result_id;
    IF result_str <> 'hello world' THEN
        RAISE EXCEPTION 'FAIL: BUILD_STRING(2) result=%, expected "hello world"', result_str;
    END IF;
    RAISE NOTICE '  ✓ BUILD_STRING(2): "hello world"';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 10: F-string combo — f"x={42}" → "x=42"
    -- RESUME(0) LOAD_CONST(0='x=') LOAD_CONST(1=42) FORMAT_VALUE(0) BUILD_STRING(2) RETURN_VALUE
    -- consts: ['x=', 42]
    -- hex: 9700640064019b009d025300
    -- =========================================================================
    RAISE NOTICE 'Test 10: F-string combo — f"x={42}" → "x=42"...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const0_id, 'x=');
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 42);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('9700640064019b009d025300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: F-string combo returned NULL'; END IF;
    SELECT str_value INTO result_str FROM public.py_unicode_object WHERE ob_base = result_id;
    IF result_str <> 'x=42' THEN
        RAISE EXCEPTION 'FAIL: F-string combo result=%, expected "x=42"', result_str;
    END IF;
    RAISE NOTICE '  ✓ F-string combo: f"x={42}" → "x=42"';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Summary
    -- =========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Results: % / % tests passed', pass_count, test_count;
    RAISE NOTICE '========================================';

    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'FAIL: % tests failed', test_count - pass_count;
    END IF;
END $$;
