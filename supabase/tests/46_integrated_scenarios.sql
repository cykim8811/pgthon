-- ============================================================================
-- Test: Integrated Scenarios (LOAD_ATTR, STORE_ATTR, Bound Method, Type.attr)
--
-- Purpose:
--   지금까지 추가한 기능들(LOAD_ATTR, STORE_ATTR, 타입 객체 속성, Bound Method 등)을
--   조합한 통합 시나리오 검증. 다양한 시나리오에서 한 번에 성공해야 함.
--
-- Scenarios:
--   1. 한 프레임: STORE_ATTR(obj.x=42) 후 LOAD_ATTR(obj.x) RETURN_VALUE → 42
--   2. Type.attr vs inst.attr: getattr(T,"x")→1, getattr(inst,"x")→1; STORE_ATTR inst.x=2 후 getattr(inst,"x")→2
--   3. Bytecode Class.attr 호출: LOAD_CONST(T), LOAD_ATTR("f"), LOAD_CONST("hi"), PRECALL(1) CALL(1) → len("hi")=2
--   4. Bytecode Bound method 호출: inst.f("hi") → TypeError (bound method가 len(inst,"hi")로 호출되어 인자 2개 → len은 METH_O 1개)
--   5. 서브클래스: Sub 인스턴스에서 base "a", sub "b" 조회 후 STORE_ATTR sub_inst.a=77, LOAD_ATTR → 77
--   6. 인스턴스 shadowing: type x=10, instance y=20; bytecode로 x,y 조회 후 inst.x=99 저장, x 조회 → 99
--   7. getattr(Type, "nonexistent") → AttributeError
--   8. 클래스 속성 쓰기 후 인스턴스 조회: bytecode C.x=1 실행 후 getattr(inst,"x") → 1 (인스턴스 __dict__ 없음, 타입에서 조회)
--   9. 클래스 속성 + 인스턴스 shadowing: C.x=1 → getattr(inst,"x")→1 → setattr(inst,"x",2) → getattr(inst,"x")→2
--  10. DELETE_ATTR 통합: obj.x=42, bytecode DELETE_ATTR("x"), getattr(obj,"x") → AttributeError
--  11. DELETE_ATTR + class fallback: C.x=1, inst.x=2 (shadow), del inst.x, getattr(inst,"x")→1 (타입에서 다시 조회)
--
-- Usage:
--   Run after Phase 48. If any assertion fails, exception is raised.
--   규칙: 테스트 실패 시 코드 수정 없이 멈추고 사용자에게 실패만 알린다.
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE   uuid := '00000000-0000-4000-a000-000000000001';
    ID_TYPE_TYPE     uuid := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE      uuid := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE      uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE     uuid := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE    uuid := '00000000-0000-4000-a000-000000000007';
    ID_BYTES_TYPE    uuid := '00000000-0000-4000-a000-000000000012';
    ID_ATTRIBUTE_ERROR_TYPE uuid := '00000000-0000-4000-a000-000000000027';
    ID_TYPE_ERROR_TYPE     uuid := '00000000-0000-4000-a000-000000000022';
    ID_LEN_FUNCTION  uuid := '00000000-0000-4000-b000-000000000003';
    ID_BUILTINS_MODULE uuid := '00000000-0000-4000-b000-000000000002';

    test_count int := 0;
    pass_count int := 0;

    bases_tuple_id uuid;
    dict_empty_id uuid;
    dict_t_id uuid;
    value_1_id uuid;
    value_2_id uuid;
    value_42_id uuid;
    value_77_id uuid;
    value_99_id uuid;
    value_10_id uuid;
    value_20_id uuid;
    name_x_id uuid;
    name_y_id uuid;
    name_f_id uuid;
    name_a_id uuid;
    name_b_id uuid;
    name_nonexistent_id uuid;
    type_t_id uuid;
    type_base_id uuid;
    type_sub_id uuid;
    inst_id uuid;
    inst_sub_id uuid;
    dict_inst_id uuid;
    dict_base_id uuid;
    bases_base_tuple_id uuid;
    res_id uuid;
    got_exc_type_id uuid;
    result_num bigint;
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
    real_builtins_dict_id uuid;
    str_hi_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Integrated Scenarios Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    SELECT tp_bases INTO bases_tuple_id FROM public.py_type_object WHERE ob_base = ID_INT_TYPE LIMIT 1;
    IF bases_tuple_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: tp_bases (object,) not found';
    END IF;

    SELECT md_dict INTO real_builtins_dict_id FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE LIMIT 1;
    IF real_builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ dict not found';
    END IF;

    name_x_id := public.py_str_from_text('x');
    name_y_id := public.py_str_from_text('y');
    name_f_id := public.py_str_from_text('f');
    name_a_id := public.py_str_from_text('a');
    name_b_id := public.py_str_from_text('b');
    name_nonexistent_id := public.py_str_from_text('nonexistent');

    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    empty_str_id := public.py_str_from_text('');

    value_1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_1_id, 1);
    value_2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_2_id, 2);
    value_42_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_42_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_42_id, 42);
    value_77_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_77_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_77_id, 77);
    value_99_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_99_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_99_id, 99);
    value_10_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_10_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_10_id, 10);
    value_20_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (value_20_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (value_20_id, 20);
    str_hi_id := public.py_str_from_text('hi');

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);

    -- ========================================================================
    -- Scenario 1: 한 프레임에서 STORE_ATTR(obj.x=42) 후 LOAD_ATTR(obj.x) RETURN → 42
    -- CPython 고증: STORE_ATTR 전 스택 TOS=owner, SECOND=value (docs/STORE_ATTR_DESIGN.md §1.1).
    -- Bytecode: LOAD_CONST(42), LOAD_CONST(inst), STORE_ATTR("x"); LOAD_CONST(inst), LOAD_ATTR("x"), RETURN_VALUE
    -- ========================================================================
    RAISE NOTICE 'Scenario 1: STORE_ATTR then LOAD_ATTR in one frame → 42...';
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
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_x_id]);
    -- CPython: value 먼저 push, owner 나중에 push → TOS=owner, SECOND=value
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[value_42_id, inst_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- LOAD_CONST 0 (value), LOAD_CONST 1 (owner), STORE_ATTR 0; LOAD_CONST 1 (inst), LOAD_ATTR 0, RETURN_VALUE
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064015f0064016a005300', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, real_builtins_dict_id);

    res_id := public.py_eval_frame(frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Scenario 1 py_eval_frame raised';
    END IF;
    IF res_id IS DISTINCT FROM value_42_id THEN
        RAISE EXCEPTION 'FAIL: Scenario 1 expected 42 id %, got %', value_42_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ STORE_ATTR then LOAD_ATTR in one frame → 42';

    -- ========================================================================
    -- Scenario 2: Type.attr vs inst.attr; STORE_ATTR 후 shadowing
    -- ========================================================================
    RAISE NOTICE 'Scenario 2: getattr(T,"x")→1, getattr(inst,"x")→1; STORE_ATTR inst.x=2; getattr(inst,"x")→2...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_x_id, value_1_id);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    res_id := public.py_object_getattr(type_t_id, name_x_id);
    IF res_id IS DISTINCT FROM value_1_id THEN
        RAISE EXCEPTION 'FAIL: getattr(T,"x") expected 1 id %, got %', value_1_id, res_id;
    END IF;
    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS DISTINCT FROM value_1_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"x") expected 1 id %, got %', value_1_id, res_id;
    END IF;
    PERFORM public.py_object_setattr(inst_id, name_x_id, value_2_id);
    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS DISTINCT FROM value_2_id THEN
        RAISE EXCEPTION 'FAIL: after setattr(inst,"x",2) getattr expected 2 id %, got %', value_2_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Type.attr / inst.attr / STORE_ATTR shadowing';

    -- ========================================================================
    -- Scenario 3: Bytecode Class.attr 호출 — LOAD_CONST(T), LOAD_ATTR("f"), LOAD_CONST("hi"), PRECALL(1) CALL(1) → 2
    -- ========================================================================
    RAISE NOTICE 'Scenario 3: Bytecode T.f("hi") → len("hi") = 2...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_f_id, ID_LEN_FUNCTION);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_f_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[type_t_id, str_hi_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- LOAD_CONST 0 (T), LOAD_ATTR 0 ("f"), LOAD_CONST 1 ("hi"), PRECALL 1, CALL 1, RETURN_VALUE (CPython 3.11)
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64006a006401a601ab015300', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, real_builtins_dict_id);

    res_id := public.py_eval_frame(frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Scenario 3 T.f("hi") raised';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = res_id;
    IF result_num IS NULL OR result_num <> 2 THEN
        RAISE EXCEPTION 'FAIL: Scenario 3 expected len("hi")=2, got %', result_num;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Bytecode T.f("hi") → 2';

    -- ========================================================================
    -- Scenario 4: Bytecode Bound method 호출 — inst.f("hi") → TypeError
    -- CPython: bound method는 im_func(im_self, *args) 호출. len(inst, "hi") → 인자 2개, len은 METH_O 1개 → TypeError.
    -- ========================================================================
    RAISE NOTICE 'Scenario 4: Bytecode inst.f("hi") (bound method) → TypeError...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_f_id, ID_LEN_FUNCTION);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_f_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inst_id, str_hi_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- LOAD_CONST 0 (inst), LOAD_ATTR 0 ("f"), LOAD_CONST 1 ("hi"), PRECALL 1, CALL 1, RETURN_VALUE (CPython 3.11)
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64006a006401a601ab015300', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, real_builtins_dict_id);

    res_id := public.py_eval_frame(frame_id);
    IF res_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Scenario 4 inst.f("hi") should return NULL (TypeError), got %', res_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Scenario 4 inst.f("hi") should set exception';
    END IF;
    SELECT exc_type_id INTO got_exc_type_id FROM public.py_exception_state WHERE id = (SELECT id FROM public.py_exception_state LIMIT 1);
    IF got_exc_type_id IS DISTINCT FROM ID_TYPE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: Scenario 4 expected TypeError, got exc_type_id %', got_exc_type_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Bytecode inst.f("hi") → TypeError';

    -- ========================================================================
    -- Scenario 5: 서브클래스 — Sub 인스턴스에서 base "a", sub "b" 조회; STORE_ATTR sub_inst.a=77 후 LOAD_ATTR → 77
    -- ========================================================================
    RAISE NOTICE 'Scenario 5: Sub instance getattr("a"), getattr("b"); STORE_ATTR a=77, getattr("a")→77...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_base_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_base_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_base_id);
    PERFORM public.py_dict_set_item(dict_base_id, name_a_id, value_1_id);
    type_base_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_base_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_base_id, 'Base', bases_tuple_id, dict_base_id);
    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_b_id, value_2_id);
    bases_base_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (bases_base_tuple_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (bases_base_tuple_id, ARRAY[type_base_id]);
    type_sub_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_sub_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_sub_id, 'Sub', bases_base_tuple_id, dict_t_id);
    inst_sub_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_sub_id, type_sub_id);
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_sub_id, dict_inst_id);

    res_id := public.py_object_getattr(inst_sub_id, name_a_id);
    IF res_id IS DISTINCT FROM value_1_id THEN
        RAISE EXCEPTION 'FAIL: getattr(sub_inst,"a") expected 1 id %, got %', value_1_id, res_id;
    END IF;
    res_id := public.py_object_getattr(inst_sub_id, name_b_id);
    IF res_id IS DISTINCT FROM value_2_id THEN
        RAISE EXCEPTION 'FAIL: getattr(sub_inst,"b") expected 2 id %, got %', value_2_id, res_id;
    END IF;
    PERFORM public.py_object_setattr(inst_sub_id, name_a_id, value_77_id);
    res_id := public.py_object_getattr(inst_sub_id, name_a_id);
    IF res_id IS DISTINCT FROM value_77_id THEN
        RAISE EXCEPTION 'FAIL: after setattr(sub_inst,"a",77) getattr expected 77 id %, got %', value_77_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ Subclass a/b + STORE_ATTR a=77';

    -- ========================================================================
    -- Scenario 6: 인스턴스 shadowing — type x=10, instance y=20; bytecode로 x,y 조회 후 inst.x=99, x 조회 → 99
    -- ========================================================================
    RAISE NOTICE 'Scenario 6: type x=10, instance y=20; bytecode LOAD_ATTR x,y; STORE_ATTR x=99; LOAD_ATTR x→99...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    PERFORM public.py_dict_set_item(dict_t_id, name_x_id, value_10_id);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    PERFORM public.py_dict_set_item(dict_inst_id, name_y_id, value_20_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS DISTINCT FROM value_10_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"x") expected 10 id %, got %', value_10_id, res_id;
    END IF;
    res_id := public.py_object_getattr(inst_id, name_y_id);
    IF res_id IS DISTINCT FROM value_20_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"y") expected 20 id %, got %', value_20_id, res_id;
    END IF;
    PERFORM public.py_object_setattr(inst_id, name_x_id, value_99_id);
    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS DISTINCT FROM value_99_id THEN
        RAISE EXCEPTION 'FAIL: after setattr(inst,"x",99) getattr expected 99 id %, got %', value_99_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ type x=10, instance y=20, STORE_ATTR x=99 → 99';

    -- ========================================================================
    -- Scenario 7: getattr(Type, "nonexistent") → AttributeError
    -- ========================================================================
    RAISE NOTICE 'Scenario 7: getattr(Type, "nonexistent") → AttributeError...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_t_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_t_id);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'T', bases_tuple_id, dict_t_id);

    res_id := public.py_object_getattr(type_t_id, name_nonexistent_id);
    IF res_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: getattr(T,"nonexistent") should return NULL, got %', res_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(T,"nonexistent") should set exception';
    END IF;
    SELECT exc_type_id INTO got_exc_type_id FROM public.py_exception_state WHERE id = (SELECT id FROM public.py_exception_state LIMIT 1);
    IF got_exc_type_id IS DISTINCT FROM ID_ATTRIBUTE_ERROR_TYPE THEN
        RAISE EXCEPTION 'FAIL: expected AttributeError, got exc_type_id %', got_exc_type_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ getattr(Type, "nonexistent") → AttributeError';

    -- ========================================================================
    -- Scenario 8: 클래스 속성 쓰기 후 인스턴스 조회 — bytecode C.x=1, then getattr(inst,"x") → 1
    -- C의 tp_dict에 setattr로 저장 후, 인스턴스(inst __dict__에 "x" 없음)에서 타입으로부터 x 조회.
    -- ========================================================================
    RAISE NOTICE 'Scenario 8: Bytecode C.x=1 then getattr(inst,"x") → 1 (class attr)...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_empty_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_empty_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_empty_id);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'C', bases_tuple_id, dict_empty_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_x_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[value_1_id, type_t_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('640064015f00', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, real_builtins_dict_id);

    res_id := public.py_eval_frame(frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Scenario 8 C.x=1 bytecode raised';
    END IF;
    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS DISTINCT FROM value_1_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"x") after C.x=1 expected 1 id %, got %', value_1_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ C.x=1 then getattr(inst,"x") → 1';

    -- ========================================================================
    -- Scenario 9: 클래스 속성 + 인스턴스 shadowing — C.x=1 → inst.x→1 → inst.x=2 → inst.x→2
    -- ========================================================================
    RAISE NOTICE 'Scenario 9: C.x=1, getattr(inst,"x")→1, setattr(inst,"x",2), getattr(inst,"x")→2...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_empty_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_empty_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_empty_id);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'C', bases_tuple_id, dict_empty_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    PERFORM public.py_object_setattr(type_t_id, name_x_id, value_1_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Scenario 9 setattr(C,"x",1) raised';
    END IF;
    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS DISTINCT FROM value_1_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"x") after C.x=1 expected 1 id %, got %', value_1_id, res_id;
    END IF;
    PERFORM public.py_object_setattr(inst_id, name_x_id, value_2_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Scenario 9 setattr(inst,"x",2) raised';
    END IF;
    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS DISTINCT FROM value_2_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"x") after inst.x=2 expected 2 id %, got %', value_2_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ C.x=1 → inst.x→1 → inst.x=2 → inst.x→2';

    -- ========================================================================
    -- Scenario 10: DELETE_ATTR 통합 — obj.x=42, bytecode DELETE_ATTR("x"), getattr(obj,"x") → AttributeError
    -- ========================================================================
    RAISE NOTICE 'Scenario 10: obj.x=42, bytecode DELETE_ATTR("x"), getattr(obj,"x") → AttributeError...';
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
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    PERFORM public.py_object_setattr(inst_id, name_x_id, value_42_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Scenario 10 setattr(inst,"x",42) raised';
    END IF;

    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name_x_id]);
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[inst_id]);
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('64006000', 'hex'));
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, empty_tuple_id, empty_tuple_id, empty_tuple_id);
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, real_builtins_dict_id);

    PERFORM public.py_eval_frame(frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Scenario 10 DELETE_ATTR("x") raised';
    END IF;
    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"x") after del expected NULL, got %', res_id;
    END IF;
    IF NOT public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"x") after del should set AttributeError';
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ obj.x=42, del obj.x, getattr(obj,"x") → AttributeError';

    -- ========================================================================
    -- Scenario 11: DELETE_ATTR + class fallback — C.x=1, inst.x=2 (shadow), del inst.x, getattr(inst,"x")→1
    -- ========================================================================
    RAISE NOTICE 'Scenario 11: C.x=1, inst.x=2, del inst.x, getattr(inst,"x")→1 (class attr again)...';
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    dict_empty_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_empty_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_empty_id);
    type_t_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (type_t_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (type_t_id, 'C', bases_tuple_id, dict_empty_id);
    inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_t_id);
    dict_inst_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_inst_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_inst_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (inst_id, dict_inst_id);

    PERFORM public.py_object_setattr(type_t_id, name_x_id, value_1_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Scenario 11 setattr(C,"x",1) raised';
    END IF;
    PERFORM public.py_object_setattr(inst_id, name_x_id, value_2_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Scenario 11 setattr(inst,"x",2) raised';
    END IF;
    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS DISTINCT FROM value_2_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"x") after inst.x=2 expected 2 id %, got %', value_2_id, res_id;
    END IF;
    PERFORM public.py_object_delattr(inst_id, name_x_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Scenario 11 delattr(inst,"x") raised';
    END IF;
    res_id := public.py_object_getattr(inst_id, name_x_id);
    IF res_id IS DISTINCT FROM value_1_id THEN
        RAISE EXCEPTION 'FAIL: getattr(inst,"x") after del inst.x expected 1 (class attr) id %, got %', value_1_id, res_id;
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ C.x=1, inst.x=2, del inst.x, inst.x → 1';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'Integrated scenarios: % test(s) failed', test_count - pass_count;
    END IF;
END;
$$;
