-- ============================================================================
-- Test 85: Star-Unpacking Opcodes
--
-- Tests:
--   1. LIST_EXTEND: [*[1,2], *[3,4]] → [1,2,3,4]
--   2. SET_UPDATE: {*[1,2], *[3]} → set with 3 items
--   3. DICT_UPDATE: {**{'a':1}, **{'b':2}} → {'a':1, 'b':2}
--   4. DICT_UPDATE: duplicate key overwrites silently
--   5. DICT_MERGE: no duplicates → success
--   6. DICT_MERGE: duplicate key → TypeError
--   7. CALL_FUNCTION_EX(0): abs(*(-5,)) → 5
--   8. CALL_FUNCTION_EX(1): abs(*(-5,), **{}) → 5
--   9. UNPACK_EX: a, *b, c = [1,2,3,4,5] → a=1, b=[2,3,4], c=5
--  10. UNPACK_EX: a, *b = [1] → a=1, b=[]
--  11. UNPACK_EX: too few values → ValueError
--  12. BUILD_CONST_KEY_MAP(2): {'a':1, 'b':2}
--  13. BUILD_CONST_KEY_MAP(0): empty dict
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE   uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE   uuid := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE  uuid := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE  uuid := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE uuid := '00000000-0000-4000-a000-000000000007';
    ID_SET_TYPE   uuid := '00000000-0000-4000-a000-000000000018';
    ID_ABS_FUNC   uuid := '00000000-0000-4000-b000-000000000004';

    test_count int := 0;
    pass_count int := 0;

    frame_id uuid;
    code_obj_id uuid;
    co_code_id uuid;
    co_names_id uuid;
    co_consts_id uuid;
    co_varnames_id uuid;
    empty_tuple_id uuid;
    empty_str_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;

    const0_id uuid;
    const1_id uuid;
    const2_id uuid;
    const3_id uuid;
    result_id uuid;
    result_int numeric;
    result_str text;
    result_type uuid;
    result_items uuid[];
    result_count int;
    temp_id uuid;
    name_id uuid;
    val_id uuid;

    v_key text;
    v_val_int numeric;
    v_val_str text;
    v_exc_type uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Star-Unpacking Opcodes Test';
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
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    -- =========================================================================
    -- Test 1: LIST_EXTEND: [*[1,2], *[3,4]] → [1,2,3,4]
    -- BUILD_LIST(0) LOAD_CONST(0=(1,2)) LIST_EXTEND(1) LOAD_CONST(1=(3,4)) LIST_EXTEND(1) RETURN_VALUE
    -- hex: 970067006400a2016401a2015300
    -- =========================================================================
    RAISE NOTICE 'Test 1: LIST_EXTEND — [*(1,2), *(3,4)] → [1,2,3,4]...';
    test_count := test_count + 1;

    -- const0 = tuple(1, 2)
    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (temp_id, 1);
    const0_id := temp_id;

    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (temp_id, 2);
    const1_id := temp_id;

    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (temp_id, ARRAY[const0_id, const1_id]);
    const0_id := temp_id;  -- const0 = (1, 2)

    -- const1 = tuple(3, 4)
    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (temp_id, 3);
    const2_id := temp_id;

    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (temp_id, 4);
    const3_id := temp_id;

    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (temp_id, ARRAY[const2_id, const3_id]);
    const1_id := temp_id;  -- const1 = (3, 4)

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970067006400a2016401a2015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: LIST_EXTEND returned NULL'; END IF;
    SELECT ob_type INTO result_type FROM public.py_object WHERE id = result_id;
    IF result_type <> ID_LIST_TYPE THEN
        RAISE EXCEPTION 'FAIL: LIST_EXTEND result type is not list';
    END IF;
    SELECT ob_item INTO result_items FROM public.py_list_object WHERE ob_base = result_id;
    IF COALESCE(array_length(result_items, 1), 0) <> 4 THEN
        RAISE EXCEPTION 'FAIL: LIST_EXTEND has % items, expected 4', COALESCE(array_length(result_items, 1), 0);
    END IF;
    -- Verify values: [1, 2, 3, 4]
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_items[1];
    IF result_int <> 1 THEN RAISE EXCEPTION 'FAIL: list[0]=%, expected 1', result_int; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_items[2];
    IF result_int <> 2 THEN RAISE EXCEPTION 'FAIL: list[1]=%, expected 2', result_int; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_items[3];
    IF result_int <> 3 THEN RAISE EXCEPTION 'FAIL: list[2]=%, expected 3', result_int; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_items[4];
    IF result_int <> 4 THEN RAISE EXCEPTION 'FAIL: list[3]=%, expected 4', result_int; END IF;
    RAISE NOTICE '  ✓ LIST_EXTEND: [1, 2, 3, 4]';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 2: SET_UPDATE: {*(1,2), *(3,)} → set with 3 items
    -- BUILD_SET(0) LOAD_CONST(0=(1,2)) SET_UPDATE(1) LOAD_CONST(1=(3,)) SET_UPDATE(1) RETURN_VALUE
    -- hex: 970068006400a3016401a3015300
    -- =========================================================================
    RAISE NOTICE 'Test 2: SET_UPDATE — {*(1,2), *(3,)} → set with 3 items...';
    test_count := test_count + 1;

    -- const0 = tuple(1, 2) — reuse int objects
    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (temp_id, 1);
    const0_id := temp_id;
    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (temp_id, 2);
    const1_id := temp_id;
    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (temp_id, ARRAY[const0_id, const1_id]);
    const0_id := temp_id;

    -- const1 = tuple(3,)
    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (temp_id, 3);
    const2_id := temp_id;
    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (temp_id, ARRAY[const2_id]);
    const1_id := temp_id;

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970068006400a3016401a3015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: SET_UPDATE returned NULL'; END IF;
    SELECT ob_type INTO result_type FROM public.py_object WHERE id = result_id;
    IF result_type <> ID_SET_TYPE THEN
        RAISE EXCEPTION 'FAIL: SET_UPDATE result type is not set';
    END IF;
    SELECT ob_item INTO result_items FROM public.py_set_object WHERE ob_base = result_id;
    IF COALESCE(array_length(result_items, 1), 0) <> 3 THEN
        RAISE EXCEPTION 'FAIL: SET_UPDATE has % items, expected 3', COALESCE(array_length(result_items, 1), 0);
    END IF;
    RAISE NOTICE '  ✓ SET_UPDATE: set with 3 items';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 3: DICT_UPDATE: {**{'a':1}, **{'b':2}} → {'a':1, 'b':2}
    -- BUILD_MAP(0) LOAD_CONST(0='a') LOAD_CONST(1=1) BUILD_MAP(1) DICT_UPDATE(1)
    -- LOAD_CONST(2='b') LOAD_CONST(3=2) BUILD_MAP(1) DICT_UPDATE(1) RETURN_VALUE
    -- Note: BUILD_MAP pops value (TOS) then key (TOS-1), so push key first
    -- hex: 97006900640064016901a401640264036901a4015300
    -- =========================================================================
    RAISE NOTICE 'Test 3: DICT_UPDATE — {**{"a":1}, **{"b":2}} → {"a":1, "b":2}...';
    test_count := test_count + 1;

    -- const0 = 'a'
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const0_id, 'a');
    -- const1 = 1
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 1);
    -- const2 = 'b'
    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const2_id, 'b');
    -- const3 = 2
    const3_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const3_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const3_id, 2);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const2_id, const3_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('97006900640064016901a401640264036901a4015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: DICT_UPDATE returned NULL'; END IF;
    SELECT ob_type INTO result_type FROM public.py_object WHERE id = result_id;
    IF result_type <> ID_DICT_TYPE THEN
        RAISE EXCEPTION 'FAIL: DICT_UPDATE result type is not dict';
    END IF;
    SELECT count(*) INTO result_count FROM public.py_dict_entry WHERE dict_id = result_id;
    IF result_count <> 2 THEN
        RAISE EXCEPTION 'FAIL: DICT_UPDATE has % entries, expected 2', result_count;
    END IF;
    -- Check 'a' → 1
    SELECT u.str_value INTO v_key
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    JOIN public.py_long_object l ON l.ob_base = e.me_value
    WHERE e.dict_id = result_id AND l.long_value = 1 LIMIT 1;
    IF v_key <> 'a' THEN
        RAISE EXCEPTION 'FAIL: DICT_UPDATE key for value 1 = %, expected a', v_key;
    END IF;
    RAISE NOTICE '  ✓ DICT_UPDATE: {"a":1, "b":2}';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 4: DICT_UPDATE duplicate key overwrites silently
    -- {**{'x':1}, **{'x':99}} → {'x':99}
    -- BUILD_MAP(0) LOAD_CONST(0='x') LOAD_CONST(1=1) BUILD_MAP(1) DICT_UPDATE(1)
    -- LOAD_CONST(0='x') LOAD_CONST(2=99) BUILD_MAP(1) DICT_UPDATE(1) RETURN_VALUE
    -- hex: 97006900640064016901a401640064026901a4015300
    -- =========================================================================
    RAISE NOTICE 'Test 4: DICT_UPDATE duplicate overwrite — {"x":99}...';
    test_count := test_count + 1;

    -- const0 = 'x', const1 = 1, const2 = 99
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const0_id, 'x');
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 1);
    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const2_id, 99);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const2_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('97006900640064016901a401640064026901a4015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: DICT_UPDATE overwrite returned NULL'; END IF;
    SELECT count(*) INTO result_count FROM public.py_dict_entry WHERE dict_id = result_id;
    IF result_count <> 1 THEN
        RAISE EXCEPTION 'FAIL: DICT_UPDATE overwrite has % entries, expected 1', result_count;
    END IF;
    SELECT l.long_value INTO result_int
    FROM public.py_dict_entry e
    JOIN public.py_long_object l ON l.ob_base = e.me_value
    WHERE e.dict_id = result_id LIMIT 1;
    IF result_int <> 99 THEN
        RAISE EXCEPTION 'FAIL: DICT_UPDATE overwrite value=%, expected 99', result_int;
    END IF;
    RAISE NOTICE '  ✓ DICT_UPDATE: duplicate key overwrites → {"x":99}';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 5: DICT_MERGE no duplicates → success
    -- {**{'a':1}} merge {**{'b':2}} → {'a':1, 'b':2}
    -- BUILD_MAP(0) LOAD_CONST(0='a') LOAD_CONST(1=1) BUILD_MAP(1) DICT_MERGE(1)
    -- LOAD_CONST(2='b') LOAD_CONST(3=2) BUILD_MAP(1) DICT_MERGE(1) RETURN_VALUE
    -- hex: 97006900640064016901a501640264036901a5015300
    -- =========================================================================
    RAISE NOTICE 'Test 5: DICT_MERGE no duplicates → {"a":1, "b":2}...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const0_id, 'a');
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 1);
    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const2_id, 'b');
    const3_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const3_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const3_id, 2);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const2_id, const3_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('97006900640064016901a501640264036901a5015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: DICT_MERGE returned NULL'; END IF;
    SELECT count(*) INTO result_count FROM public.py_dict_entry WHERE dict_id = result_id;
    IF result_count <> 2 THEN
        RAISE EXCEPTION 'FAIL: DICT_MERGE has % entries, expected 2', result_count;
    END IF;
    RAISE NOTICE '  ✓ DICT_MERGE: no duplicates → {"a":1, "b":2}';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 6: DICT_MERGE duplicate key → TypeError
    -- {**{'x':1}} merge {**{'x':99}} → TypeError
    -- BUILD_MAP(0) LOAD_CONST(0='x') LOAD_CONST(1=1) BUILD_MAP(1) DICT_MERGE(1)
    -- LOAD_CONST(0='x') LOAD_CONST(2=99) BUILD_MAP(1) DICT_MERGE(1) RETURN_VALUE
    -- hex: 97006900640064016901a501640064026901a5015300
    -- =========================================================================
    RAISE NOTICE 'Test 6: DICT_MERGE duplicate → TypeError...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (const0_id, 'x');
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 1);
    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const2_id, 99);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const2_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('97006900640064016901a501640064026901a5015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: DICT_MERGE should return NULL on duplicate';
    END IF;
    -- Check that TypeError is set
    SELECT exc_type_id INTO v_exc_type
    FROM public.py_thread_state
    WHERE id = current_setting('elytra.thread_state_id')::uuid;
    IF v_exc_type IS NULL THEN
        RAISE EXCEPTION 'FAIL: DICT_MERGE no exception set';
    END IF;
    SELECT tp_name INTO v_key FROM public.py_type_object WHERE ob_base = v_exc_type;
    IF v_key <> 'TypeError' THEN
        RAISE EXCEPTION 'FAIL: DICT_MERGE exception is %, expected TypeError', v_key;
    END IF;
    RAISE NOTICE '  ✓ DICT_MERGE: duplicate key → TypeError';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 7: CALL_FUNCTION_EX(0): abs(*(-5,)) → 5
    -- PUSH_NULL LOAD_NAME(0='abs') LOAD_CONST(0=(-5,)) CALL_FUNCTION_EX(0) RETURN_VALUE
    -- hex: 97000200650064008e005300
    -- co_names: ['abs'], need 'abs' in builtins
    -- =========================================================================
    RAISE NOTICE 'Test 7: CALL_FUNCTION_EX(0) — abs(*(-5,)) → 5...';
    test_count := test_count + 1;

    -- Put abs in builtins
    name_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name_id, 'abs');
    PERFORM public.py_dict_set_item(builtins_dict_id, name_id, ID_ABS_FUNC);

    -- co_names = ('abs',)
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_id]);

    -- const0 = tuple(-5,)
    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (temp_id, -5);
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (const0_id, ARRAY[temp_id]);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('97000200650064008e005300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: CALL_FUNCTION_EX returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int <> 5 THEN
        RAISE EXCEPTION 'FAIL: CALL_FUNCTION_EX result=%, expected 5', result_int;
    END IF;
    RAISE NOTICE '  ✓ CALL_FUNCTION_EX(0): abs(*(-5,)) → 5';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 8: CALL_FUNCTION_EX(1): abs(*(-5,), **{}) → 5
    -- PUSH_NULL LOAD_NAME(0='abs') LOAD_CONST(0=(-5,)) BUILD_MAP(0) CALL_FUNCTION_EX(1) RETURN_VALUE
    -- hex: 970002006500640069008e015300
    -- Note: abs() doesn't take kwargs, but empty kwargs dict should be OK
    -- =========================================================================
    RAISE NOTICE 'Test 8: CALL_FUNCTION_EX(1) with empty kwargs — abs(*(-5,), **{}) → 5...';
    test_count := test_count + 1;

    -- Reuse co_names from test 7 (abs is already in builtins)
    -- const0 = tuple(-5,) - reuse from test 7
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970002006500640069008e015300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: CALL_FUNCTION_EX(1) returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int <> 5 THEN
        RAISE EXCEPTION 'FAIL: CALL_FUNCTION_EX(1) result=%, expected 5', result_int;
    END IF;
    RAISE NOTICE '  ✓ CALL_FUNCTION_EX(1): abs(*(-5,), **{}) → 5';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 9: UNPACK_EX: a, *b, c = (1,2,3,4,5) → a=1, b=[2,3,4], c=5
    -- count_before=1, count_after=1, oparg=257 → EXTENDED_ARG(1) UNPACK_EX(1)
    -- LOAD_CONST(0) EXTENDED_ARG(1) UNPACK_EX(1) STORE_FAST(0) STORE_FAST(1) STORE_FAST(2) LOAD_FAST(0) RETURN_VALUE
    -- hex: 9700640090015e017d007d017d027c005300
    -- =========================================================================
    RAISE NOTICE 'Test 9: UNPACK_EX — a, *b, c = (1,2,3,4,5)...';
    test_count := test_count + 1;

    -- Create tuple(1,2,3,4,5)
    DECLARE
        int1 uuid; int2 uuid; int3 uuid; int4 uuid; int5 uuid;
        tup_id uuid;
    BEGIN
        int1 := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (int1, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int1, 1);
        int2 := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (int2, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int2, 2);
        int3 := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (int3, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int3, 3);
        int4 := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (int4, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int4, 4);
        int5 := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (int5, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (int5, 5);
        tup_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (tup_id, ID_TUPLE_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (tup_id, ARRAY[int1, int2, int3, int4, int5]);
        const0_id := tup_id;
    END;

    -- co_varnames = ('a', 'b', 'c')
    DECLARE
        vn_a uuid; vn_b uuid; vn_c uuid;
    BEGIN
        vn_a := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (vn_a, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (vn_a, 'a');
        vn_b := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (vn_b, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (vn_b, 'b');
        vn_c := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (vn_c, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (vn_c, 'c');
        co_varnames_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, ARRAY[vn_a, vn_b, vn_c]);
    END;

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('9700640090015e017d007d017d027c005300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_varnames = co_varnames_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0, f_fastlocals = array[]::uuid[] WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: UNPACK_EX returned NULL'; END IF;
    -- result_id = a = 1
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int <> 1 THEN
        RAISE EXCEPTION 'FAIL: UNPACK_EX a=%, expected 1', result_int;
    END IF;

    -- Check b = [2, 3, 4] (f_fastlocals[2])
    DECLARE
        fl uuid[];
        b_id uuid;
        b_items uuid[];
        b_len int;
        b_val numeric;
    BEGIN
        SELECT f_fastlocals INTO fl FROM public.py_frame_object WHERE ob_base = frame_id;
        b_id := fl[2]; -- index 2 = varname 'b' (1-based)
        SELECT ob_type INTO result_type FROM public.py_object WHERE id = b_id;
        IF result_type <> ID_LIST_TYPE THEN
            RAISE EXCEPTION 'FAIL: UNPACK_EX b is not a list (type=%)', result_type;
        END IF;
        SELECT ob_item INTO b_items FROM public.py_list_object WHERE ob_base = b_id;
        b_len := COALESCE(array_length(b_items, 1), 0);
        IF b_len <> 3 THEN
            RAISE EXCEPTION 'FAIL: UNPACK_EX b has % items, expected 3', b_len;
        END IF;
        SELECT long_value INTO b_val FROM public.py_long_object WHERE ob_base = b_items[1];
        IF b_val <> 2 THEN RAISE EXCEPTION 'FAIL: b[0]=%, expected 2', b_val; END IF;
        SELECT long_value INTO b_val FROM public.py_long_object WHERE ob_base = b_items[2];
        IF b_val <> 3 THEN RAISE EXCEPTION 'FAIL: b[1]=%, expected 3', b_val; END IF;
        SELECT long_value INTO b_val FROM public.py_long_object WHERE ob_base = b_items[3];
        IF b_val <> 4 THEN RAISE EXCEPTION 'FAIL: b[2]=%, expected 4', b_val; END IF;

        -- Check c = 5 (f_fastlocals[3])
        SELECT long_value INTO b_val FROM public.py_long_object WHERE ob_base = fl[3];
        IF b_val <> 5 THEN RAISE EXCEPTION 'FAIL: UNPACK_EX c=%, expected 5', b_val; END IF;
    END;

    RAISE NOTICE '  ✓ UNPACK_EX: a=1, b=[2,3,4], c=5';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 10: UNPACK_EX: a, *b = (1,) → a=1, b=[]
    -- count_before=1, count_after=0, oparg=1
    -- LOAD_CONST(0=(1,)) UNPACK_EX(1) STORE_FAST(0) STORE_FAST(1) LOAD_FAST(0) RETURN_VALUE
    -- hex: 970064005e017d007d017c005300
    -- =========================================================================
    RAISE NOTICE 'Test 10: UNPACK_EX — a, *b = (1,) → a=1, b=[]...';
    test_count := test_count + 1;

    -- const0 = tuple(1,)
    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (temp_id, 1);
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (const0_id, ARRAY[temp_id]);

    -- co_varnames = ('a', 'b')
    DECLARE
        vn_a uuid; vn_b uuid;
    BEGIN
        vn_a := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (vn_a, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (vn_a, 'a');
        vn_b := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (vn_b, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (vn_b, 'b');
        co_varnames_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, ARRAY[vn_a, vn_b]);
    END;

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064005e017d007d017c005300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_varnames = co_varnames_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0, f_fastlocals = array[]::uuid[] WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: UNPACK_EX a,*b returned NULL'; END IF;
    SELECT long_value INTO result_int FROM public.py_long_object WHERE ob_base = result_id;
    IF result_int <> 1 THEN
        RAISE EXCEPTION 'FAIL: UNPACK_EX a=%, expected 1', result_int;
    END IF;

    -- Check b = [] (f_fastlocals[2])
    DECLARE
        fl uuid[];
        b_id uuid;
        b_items uuid[];
    BEGIN
        SELECT f_fastlocals INTO fl FROM public.py_frame_object WHERE ob_base = frame_id;
        b_id := fl[2];
        SELECT ob_type INTO result_type FROM public.py_object WHERE id = b_id;
        IF result_type <> ID_LIST_TYPE THEN
            RAISE EXCEPTION 'FAIL: UNPACK_EX b is not a list';
        END IF;
        SELECT ob_item INTO b_items FROM public.py_list_object WHERE ob_base = b_id;
        IF COALESCE(array_length(b_items, 1), 0) <> 0 THEN
            RAISE EXCEPTION 'FAIL: UNPACK_EX b has % items, expected 0', array_length(b_items, 1);
        END IF;
    END;

    RAISE NOTICE '  ✓ UNPACK_EX: a=1, b=[]';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 11: UNPACK_EX too few values → ValueError
    -- a, *b, c = (1,) with count_before=2, count_after=1 → 3 needed, got 1
    -- oparg=258 → EXTENDED_ARG(1) UNPACK_EX(2)
    -- hex: 9700640090015e025300
    -- =========================================================================
    RAISE NOTICE 'Test 11: UNPACK_EX too few values → ValueError...';
    test_count := test_count + 1;

    -- const0 = tuple(1,)
    temp_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (temp_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (temp_id, 1);
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (const0_id, ARRAY[temp_id]);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('9700640090015e025300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: UNPACK_EX too few should return NULL';
    END IF;
    SELECT exc_type_id INTO v_exc_type
    FROM public.py_thread_state
    WHERE id = current_setting('elytra.thread_state_id')::uuid;
    IF v_exc_type IS NULL THEN
        RAISE EXCEPTION 'FAIL: UNPACK_EX no exception set';
    END IF;
    SELECT tp_name INTO v_key FROM public.py_type_object WHERE ob_base = v_exc_type;
    IF v_key <> 'ValueError' THEN
        RAISE EXCEPTION 'FAIL: UNPACK_EX exception is %, expected ValueError', v_key;
    END IF;
    RAISE NOTICE '  ✓ UNPACK_EX: too few values → ValueError';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 12: BUILD_CONST_KEY_MAP(2): {'a':1, 'b':2}
    -- LOAD_CONST(0=1) LOAD_CONST(1=2) LOAD_CONST(2=('a','b')) BUILD_CONST_KEY_MAP(2) RETURN_VALUE
    -- hex: 97006400640164029c025300
    -- =========================================================================
    RAISE NOTICE 'Test 12: BUILD_CONST_KEY_MAP(2) — {"a":1, "b":2}...';
    test_count := test_count + 1;

    -- const0 = 1, const1 = 2, const2 = ('a', 'b')
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 2);

    -- keys tuple ('a', 'b')
    DECLARE
        key_a uuid; key_b uuid;
    BEGIN
        key_a := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (key_a, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (key_a, 'a');
        key_b := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (key_b, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (key_b, 'b');
        const2_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_TUPLE_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (const2_id, ARRAY[key_a, key_b]);
    END;

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const2_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('97006400640164029c025300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: BUILD_CONST_KEY_MAP returned NULL'; END IF;
    SELECT ob_type INTO result_type FROM public.py_object WHERE id = result_id;
    IF result_type <> ID_DICT_TYPE THEN
        RAISE EXCEPTION 'FAIL: BUILD_CONST_KEY_MAP result is not dict';
    END IF;
    SELECT count(*) INTO result_count FROM public.py_dict_entry WHERE dict_id = result_id;
    IF result_count <> 2 THEN
        RAISE EXCEPTION 'FAIL: BUILD_CONST_KEY_MAP has % entries, expected 2', result_count;
    END IF;
    -- Check 'a' → 1
    SELECT l.long_value INTO result_int
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    JOIN public.py_long_object l ON l.ob_base = e.me_value
    WHERE e.dict_id = result_id AND u.str_value = 'a' LIMIT 1;
    IF result_int <> 1 THEN
        RAISE EXCEPTION 'FAIL: BUILD_CONST_KEY_MAP a=%, expected 1', result_int;
    END IF;
    -- Check 'b' → 2
    SELECT l.long_value INTO result_int
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    JOIN public.py_long_object l ON l.ob_base = e.me_value
    WHERE e.dict_id = result_id AND u.str_value = 'b' LIMIT 1;
    IF result_int <> 2 THEN
        RAISE EXCEPTION 'FAIL: BUILD_CONST_KEY_MAP b=%, expected 2', result_int;
    END IF;
    RAISE NOTICE '  ✓ BUILD_CONST_KEY_MAP(2): {"a":1, "b":2}';
    pass_count := pass_count + 1;

    -- =========================================================================
    -- Test 13: BUILD_CONST_KEY_MAP(0): empty dict
    -- LOAD_CONST(0=()) BUILD_CONST_KEY_MAP(0) RETURN_VALUE
    -- hex: 970064009c005300
    -- =========================================================================
    RAISE NOTICE 'Test 13: BUILD_CONST_KEY_MAP(0) — empty dict...';
    test_count := test_count + 1;

    -- const0 = empty tuple
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (const0_id, ARRAY[]::uuid[]);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('970064009c005300', 'hex'));
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;
    PERFORM public.py_err_clear();

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN RAISE EXCEPTION 'FAIL: BUILD_CONST_KEY_MAP(0) returned NULL'; END IF;
    SELECT ob_type INTO result_type FROM public.py_object WHERE id = result_id;
    IF result_type <> ID_DICT_TYPE THEN
        RAISE EXCEPTION 'FAIL: BUILD_CONST_KEY_MAP(0) result is not dict';
    END IF;
    SELECT count(*) INTO result_count FROM public.py_dict_entry WHERE dict_id = result_id;
    IF result_count <> 0 THEN
        RAISE EXCEPTION 'FAIL: BUILD_CONST_KEY_MAP(0) has % entries, expected 0', result_count;
    END IF;
    RAISE NOTICE '  ✓ BUILD_CONST_KEY_MAP(0): empty dict';
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
