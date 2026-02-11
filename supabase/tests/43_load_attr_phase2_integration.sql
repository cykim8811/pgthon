-- ============================================================================
-- Test: LOAD_ATTR Phase 2 — instance __dict__, type+bases, not found
--
-- Purpose:
--   Phase 2 속성 조회 검증: 인스턴스 __dict__ 우선, lookup_in_type_and_bases,
--   미존재 시 AttributeError. Design: docs/LOAD_ATTR_DESIGN.md §7.
--
-- Tests (basic):
--   1. Instance __dict__ only: attr only in in_dict → returns that value
--   2. Type only: no instance __dict__, attr in type tp_dict → returns from type
--   3. Bases: attr in base tp_dict only → found via tp_bases DFS
--   4. Not found: attr in neither → AttributeError
--
-- Tests (extended / 통합 시나리오):
--   5. Shadowing: same name in type tp_dict and instance __dict__ → instance wins
--   6. Mixed: instance has "a", type has "b" → getattr(inst,"a") and getattr(inst,"b") both correct
--   7. Multiple bases: Sub(tp_bases=(Base1,Base2)), attr "u" in Base1, "v" in Base2 → both found
--   8. Bytecode: LOAD_CONST(inst) LOAD_ATTR("a") with instance in_dict["a"]=99 → 99
--   9. Bytecode: Sub instance, LOAD_ATTR("z") where "z" only in base → value
--  10. Bytecode: LOAD_ATTR("missing") → AttributeError
--
-- Usage:
--   Run after migrations. If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_TYPE_TYPE   uuid := '00000000-0000-4000-a000-000000000002';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE  uuid := '00000000-0000-4000-a000-000000000007';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_ATTRIBUTE_ERROR_TYPE uuid := '00000000-0000-4000-a000-000000000027';

    test_count int := 0;
    pass_count int := 0;

    bases_tuple_id uuid;
    dict_empty_id uuid;
    dict_t_id uuid;
    value_42_id uuid;
    value_99_id uuid;
    value_z_id uuid;
    name_a_id uuid;
    name_x_id uuid;
    name_z_id uuid;
    name_missing_id uuid;
    type_t_id uuid;
    type_base_id uuid;
    type_sub_id uuid;
    bases_base_tuple_id uuid;
    dict_base_id uuid;
    inst_id uuid;
    inst_sub_id uuid;
    res_id uuid;
    got_exc_type_id uuid;
    -- Extended tests
    value_1_id uuid;
    value_2_id uuid;
    val_u_id uuid;
    val_v_id uuid;
    name_b_id uuid;
    name_u_id uuid;
    name_v_id uuid;
    type_base1_id uuid;
    type_base2_id uuid;
    dict_base1_id uuid;
    dict_base2_id uuid;
    bases_two_id uuid;
    empty_tuple_id uuid;
    empty_str_id uuid;
    co_names_id uuid;
    co_consts_id uuid;
    co_code_id uuid;
    code_obj_id uuid;
    frame_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'LOAD_ATTR Phase 2 Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    SELECT tp_bases INTO bases_tuple_id FROM public.py_type_object WHERE ob_base = ID_INT_TYPE LIMIT 1;
    IF bases_tuple_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: tp_bases (object,) not found';
    END IF;

    -- Value 42, 99, and a distinct "z" value
    value_42_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_42_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_42_id, 42);
    value_99_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_99_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_99_id, 99);
    value_z_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_z_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_z_id, 100);

    name_a_id := public.py_str_from_text('a');
    name_x_id := public.py_str_from_text('x');
    name_z_id := public.py_str_from_text('z');
    name_missing_id := public.py_str_from_text('missing');

    -- ------------------------------------------------------------------------
    -- Test 1: Instance __dict__ only — attr "a" only in in_dict, not in type tp_dict
    -- getattr(inst, "a") must return value from instance __dict__
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 1: Instance __dict__ only (in_dict["a"]=99, type tp_dict empty)...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_empty_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_empty_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_empty_id);

    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_empty_id);

    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_a_id, value_99_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_t_id);

    res_id := public.py_object_getattr(inst_id, name_a_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "a") raised but "a" is in instance __dict__';
    END IF;
    IF res_id IS DISTINCT FROM value_99_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "a") expected value 99 id %, got %', value_99_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Instance __dict__["a"] = 99 → getattr returns 99';

    -- ------------------------------------------------------------------------
    -- Test 2: Type only — no instance __dict__, attr "x" in type tp_dict = 42
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 2: Type only (no in_dict, tp_dict["x"]=42)...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_x_id, value_42_id);

    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);

    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    -- No py_instance_object row → no instance __dict__

    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "x") raised but "x" is in type tp_dict';
    END IF;
    IF res_id IS DISTINCT FROM value_42_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "x") expected value 42 id %, got %', value_42_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Type tp_dict["x"] = 42 → getattr returns 42';

    -- ------------------------------------------------------------------------
    -- Test 3: Bases — attr "z" only in base type tp_dict
    -- Sub has tp_bases = (Base,), Base has tp_dict["z"] = value_z
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 3: Bases (attr "z" in base tp_dict only)...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_base_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_base_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_base_id);
    PERFORM public.py_dict_set_item(dict_base_id, name_z_id, value_z_id);

    type_base_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_base_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_base_id, 'Base', bases_tuple_id, dict_base_id);

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);

    bases_base_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (bases_base_tuple_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (bases_base_tuple_id, ARRAY[type_base_id]);

    type_sub_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_sub_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_sub_id, 'Sub', bases_base_tuple_id, dict_t_id);

    inst_sub_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_sub_id, type_sub_id);

    res_id := public.py_object_getattr(inst_sub_id, name_z_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(sub_inst, "z") raised but "z" is in base tp_dict';
    END IF;
    IF res_id IS DISTINCT FROM value_z_id THEN
        RAISE EXCEPTION 'FAIL: getattr(sub_inst, "z") expected value_z id %, got %', value_z_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Base tp_dict["z"] → getattr on Sub instance returns value';

    -- ------------------------------------------------------------------------
    -- Test 4: Not found — "missing" in neither instance __dict__ nor type/bases → AttributeError
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 4: getattr(inst, "missing") → AttributeError...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);

    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);

    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);

    res_id := public.py_object_getattr(inst_id, name_missing_id);
    IF res_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "missing") should return NULL, got %', res_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "missing") should set exception';
    END IF;
    SELECT exc_type_id INTO got_exc_type_id FROM public.py_thread_state WHERE id = current_setting('elytra.thread_state_id')::uuid;
    IF got_exc_type_id IS DISTINCT FROM ID_ATTRIBUTE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: expected AttributeError, got exc_type_id %', got_exc_type_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ getattr(inst, "missing") → AttributeError';

    -- ------------------------------------------------------------------------
    -- Test 5: Shadowing — type tp_dict["x"]=42, instance in_dict["x"]=99 → instance wins
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 5: Shadowing (type x=42, instance x=99 → 99)...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_x_id, value_42_id);

    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);

    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_x_id, value_99_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_t_id);

    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "x") raised (shadowing test)';
    END IF;
    IF res_id IS DISTINCT FROM value_99_id THEN
        RAISE EXCEPTION 'FAIL: instance must shadow type: expected 99 id %, got %', value_99_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Instance __dict__["x"] shadows type tp_dict["x"] → 99';

    -- ------------------------------------------------------------------------
    -- Test 6: Mixed — instance in_dict["a"]=1, type tp_dict["b"]=2
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 6: Mixed (instance a=1, type b=2)...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    value_1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_1_id, 1);
    value_2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_2_id, 2);
    name_b_id := public.py_str_from_text('b');

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_b_id, value_2_id);

    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);

    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_a_id, value_1_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_t_id);

    res_id := public.py_object_getattr(inst_id, name_a_id);
    IF res_id IS DISTINCT FROM value_1_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "a") expected 1 id %, got %', value_1_id, res_id;
    END IF;
    res_id := public.py_object_getattr(inst_id, name_b_id);
    IF res_id IS DISTINCT FROM value_2_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst, "b") expected 2 id %, got %', value_2_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ getattr(inst, "a")=1, getattr(inst, "b")=2';

    -- ------------------------------------------------------------------------
    -- Test 7: Multiple bases — Sub(tp_bases=(Base1, Base2)), Base1 has "u", Base2 has "v"
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 7: Multiple bases (Base1.u, Base2.v)...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    val_u_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (val_u_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (val_u_id, 101);
    val_v_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (val_v_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (val_v_id, 102);
    name_u_id := public.py_str_from_text('u');
    name_v_id := public.py_str_from_text('v');

    dict_base1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_base1_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_base1_id);
    PERFORM public.py_dict_set_item(dict_base1_id, name_u_id, val_u_id);

    type_base1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_base1_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_base1_id, 'Base1', bases_tuple_id, dict_base1_id);

    dict_base2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_base2_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_base2_id);
    PERFORM public.py_dict_set_item(dict_base2_id, name_v_id, val_v_id);

    type_base2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_base2_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_base2_id, 'Base2', bases_tuple_id, dict_base2_id);

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    bases_two_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (bases_two_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (bases_two_id, ARRAY[type_base1_id, type_base2_id]);

    type_sub_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_sub_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_sub_id, 'Sub', bases_two_id, dict_t_id);

    inst_sub_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_sub_id, type_sub_id);

    res_id := public.py_object_getattr(inst_sub_id, name_u_id);
    IF res_id IS DISTINCT FROM val_u_id THEN
        RAISE EXCEPTION 'FAIL: getattr(sub_inst, "u") expected val_u id %, got %', val_u_id, res_id;
    END IF;
    res_id := public.py_object_getattr(inst_sub_id, name_v_id);
    IF res_id IS DISTINCT FROM val_v_id THEN
        RAISE EXCEPTION 'FAIL: getattr(sub_inst, "v") expected val_v id %, got %', val_v_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ getattr(sub_inst, "u")=101, getattr(sub_inst, "v")=102';

    -- ------------------------------------------------------------------------
    -- Test 8: Bytecode — LOAD_CONST(inst) LOAD_ATTR("a") with instance in_dict["a"]=99
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 8: Bytecode LOAD_ATTR from instance __dict__...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_empty_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_empty_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_empty_id);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_empty_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_a_id, value_99_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_t_id);

    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    empty_str_id := public.py_str_from_text('');
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_a_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inst_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64006a005300', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
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

    res_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Bytecode LOAD_ATTR("a") raised but instance has in_dict["a"]';
    END IF;
    IF res_id IS DISTINCT FROM value_99_id THEN
        RAISE EXCEPTION 'FAIL: Bytecode LOAD_ATTR("a") expected 99 id %, got %', value_99_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Bytecode obj.a with instance __dict__["a"]=99 → 99';

    -- ------------------------------------------------------------------------
    -- Test 9: Bytecode — Sub instance, LOAD_ATTR("z") where "z" only in base
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 9: Bytecode LOAD_ATTR from base (Sub instance, attr z in Base)...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_base_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_base_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_base_id);
    PERFORM public.py_dict_set_item(dict_base_id, name_z_id, value_z_id);
    type_base_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_base_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_base_id, 'Base', bases_tuple_id, dict_base_id);
    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    bases_base_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (bases_base_tuple_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (bases_base_tuple_id, ARRAY[type_base_id]);
    type_sub_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_sub_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_sub_id, 'Sub', bases_base_tuple_id, dict_t_id);
    inst_sub_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_sub_id, type_sub_id);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_z_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inst_sub_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64006a005300', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF res_id IS NULL AND public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Bytecode LOAD_ATTR("z") on Sub instance raised but "z" in base';
    END IF;
    IF res_id IS DISTINCT FROM value_z_id THEN
        RAISE EXCEPTION 'FAIL: Bytecode LOAD_ATTR("z") expected value_z id %, got %', value_z_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Bytecode obj.z (Sub, z in Base) → value';

    -- ------------------------------------------------------------------------
    -- Test 10: Bytecode — LOAD_ATTR("missing") → AttributeError
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 10: Bytecode LOAD_ATTR("missing") → AttributeError...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_missing_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inst_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64006a005300', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    res_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF res_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Bytecode LOAD_ATTR("missing") should return NULL, got %', res_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Bytecode LOAD_ATTR("missing") should set exception';
    END IF;
    SELECT exc_type_id INTO got_exc_type_id FROM public.py_thread_state WHERE id = current_setting('elytra.thread_state_id')::uuid;
    IF got_exc_type_id IS DISTINCT FROM ID_ATTRIBUTE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: Bytecode expected AttributeError, got exc_type_id %', got_exc_type_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Bytecode obj.missing → AttributeError';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'LOAD_ATTR Phase 2 integration: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
