-- ============================================================================
-- Test: Builtin Type Constructors (int/str/float/bool/list/tuple/dict)
--
-- Tests:
--   1. int() → 0, int(42) → 42, int('123') → 123, int(3.7) → 3, int(True) → 1
--   2. str() → "", str(42) → "42", str(True) → "True"
--   3. float() → 0.0, float(42) → 42.0, float('3.14') → 3.14
--   4. bool() → False, bool(0) → False, bool(1) → True, bool("") → False, bool("hi") → True
--   5. list() → [], list((1,2,3)) → [1,2,3]
--   6. tuple() → (), tuple([1,2,3]) → (1,2,3)
--   7. dict() → {}
--   8. Bytecode: return int('42') via LOAD_NAME + CALL
-- ============================================================================

DO $$
DECLARE
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE    UUID := '00000000-0000-4000-a000-000000000003';
    ID_FLOAT_TYPE  UUID := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE   UUID := '00000000-0000-4000-a000-000000000013';
    ID_LIST_TYPE   UUID := '00000000-0000-4000-a000-000000000005';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';
    ID_BYTES_TYPE  UUID := '00000000-0000-4000-a000-000000000012';
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_NONE_OBJ    UUID := '00000000-0000-4000-b000-000000000001';
    ID_TRUE_OBJ    UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ   UUID := '00000000-0000-4000-b000-000000000011';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';

    test_count INT := 0;
    pass_count INT := 0;

    -- Temp variables
    v_result UUID;
    v_int_val NUMERIC;
    v_str_val TEXT;
    v_float_val DOUBLE PRECISION;
    v_list_items UUID[];
    v_tuple_items UUID[];

    -- Args
    v_arg UUID;
    v_arg2 UUID;
    v_arg3 UUID;

    -- For bytecode test
    builtins_dict_id UUID;
    co_code_id UUID;
    co_consts_id UUID;
    co_names_id UUID;
    code_obj_id UUID;
    co_varnames_id UUID;
    co_cellvars_id UUID;
    co_freevars_id UUID;
    empty_str_id UUID;
    frame_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    str_int_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Type Constructors Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ================================================================
    -- Test 1: int() constructors
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- int() → 0
    v_result := public.py_object_call(ID_INT_TYPE, ARRAY[]::uuid[], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: int() raised error'; END IF;
    SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = v_result;
    IF v_int_val IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'FAIL: int() expected 0, got %', v_int_val; END IF;

    -- int(42) → 42
    v_arg := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_arg, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_arg, 42);
    v_result := public.py_object_call(ID_INT_TYPE, ARRAY[v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: int(42) raised error'; END IF;
    SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = v_result;
    IF v_int_val IS DISTINCT FROM 42 THEN RAISE EXCEPTION 'FAIL: int(42) expected 42, got %', v_int_val; END IF;

    -- int('123') → 123
    v_arg := public.py_str_from_text('123');
    v_result := public.py_object_call(ID_INT_TYPE, ARRAY[v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: int("123") raised error'; END IF;
    SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = v_result;
    IF v_int_val IS DISTINCT FROM 123 THEN RAISE EXCEPTION 'FAIL: int("123") expected 123, got %', v_int_val; END IF;

    -- int(3.7) → 3
    v_arg := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_arg, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (v_arg, 3.7);
    v_result := public.py_object_call(ID_INT_TYPE, ARRAY[v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: int(3.7) raised error'; END IF;
    SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = v_result;
    IF v_int_val IS DISTINCT FROM 3 THEN RAISE EXCEPTION 'FAIL: int(3.7) expected 3, got %', v_int_val; END IF;

    -- int(True) → 1
    v_result := public.py_object_call(ID_INT_TYPE, ARRAY[ID_TRUE_OBJ], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: int(True) raised error'; END IF;
    SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = v_result;
    IF v_int_val IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FAIL: int(True) expected 1, got %', v_int_val; END IF;

    RAISE NOTICE '  ✓ Test 1: int() constructors (0-arg, int, str, float, bool)';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 2: str() constructors
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- str() → ""
    v_result := public.py_object_call(ID_STR_TYPE, ARRAY[]::uuid[], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: str() raised error'; END IF;
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_result;
    IF v_str_val IS DISTINCT FROM '' THEN RAISE EXCEPTION 'FAIL: str() expected "", got "%"', v_str_val; END IF;

    -- str(42) → "42"
    v_arg := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_arg, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_arg, 42);
    v_result := public.py_object_call(ID_STR_TYPE, ARRAY[v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: str(42) raised error'; END IF;
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_result;
    IF v_str_val IS DISTINCT FROM '42' THEN RAISE EXCEPTION 'FAIL: str(42) expected "42", got "%"', v_str_val; END IF;

    -- str(True) → "True"
    v_result := public.py_object_call(ID_STR_TYPE, ARRAY[ID_TRUE_OBJ], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: str(True) raised error'; END IF;
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_result;
    IF v_str_val IS DISTINCT FROM 'True' THEN RAISE EXCEPTION 'FAIL: str(True) expected "True", got "%"', v_str_val; END IF;

    RAISE NOTICE '  ✓ Test 2: str() constructors (0-arg, int, bool)';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 3: float() constructors
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- float() → 0.0
    v_result := public.py_object_call(ID_FLOAT_TYPE, ARRAY[]::uuid[], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: float() raised error'; END IF;
    SELECT ob_fval INTO v_float_val FROM public.py_float_object WHERE ob_base = v_result;
    IF v_float_val IS DISTINCT FROM 0.0 THEN RAISE EXCEPTION 'FAIL: float() expected 0.0, got %', v_float_val; END IF;

    -- float(42) → 42.0
    v_arg := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_arg, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_arg, 42);
    v_result := public.py_object_call(ID_FLOAT_TYPE, ARRAY[v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: float(42) raised error'; END IF;
    SELECT ob_fval INTO v_float_val FROM public.py_float_object WHERE ob_base = v_result;
    IF v_float_val IS DISTINCT FROM 42.0 THEN RAISE EXCEPTION 'FAIL: float(42) expected 42.0, got %', v_float_val; END IF;

    -- float('3.14') → 3.14
    v_arg := public.py_str_from_text('3.14');
    v_result := public.py_object_call(ID_FLOAT_TYPE, ARRAY[v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: float("3.14") raised error'; END IF;
    SELECT ob_fval INTO v_float_val FROM public.py_float_object WHERE ob_base = v_result;
    IF v_float_val IS DISTINCT FROM 3.14 THEN RAISE EXCEPTION 'FAIL: float("3.14") expected 3.14, got %', v_float_val; END IF;

    RAISE NOTICE '  ✓ Test 3: float() constructors (0-arg, int, str)';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 4: bool() constructors
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- bool() → False
    v_result := public.py_object_call(ID_BOOL_TYPE, ARRAY[]::uuid[], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: bool() raised error'; END IF;
    IF v_result IS DISTINCT FROM ID_FALSE_OBJ THEN RAISE EXCEPTION 'FAIL: bool() expected False'; END IF;

    -- bool(0) → False
    v_arg := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_arg, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_arg, 0);
    v_result := public.py_object_call(ID_BOOL_TYPE, ARRAY[v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: bool(0) raised error'; END IF;
    IF v_result IS DISTINCT FROM ID_FALSE_OBJ THEN RAISE EXCEPTION 'FAIL: bool(0) expected False'; END IF;

    -- bool(1) → True
    v_arg := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_arg, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_arg, 1);
    v_result := public.py_object_call(ID_BOOL_TYPE, ARRAY[v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: bool(1) raised error'; END IF;
    IF v_result IS DISTINCT FROM ID_TRUE_OBJ THEN RAISE EXCEPTION 'FAIL: bool(1) expected True'; END IF;

    -- bool("") → False
    v_arg := public.py_str_from_text('');
    v_result := public.py_object_call(ID_BOOL_TYPE, ARRAY[v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: bool("") raised error'; END IF;
    IF v_result IS DISTINCT FROM ID_FALSE_OBJ THEN RAISE EXCEPTION 'FAIL: bool("") expected False'; END IF;

    -- bool("hi") → True
    v_arg := public.py_str_from_text('hi');
    v_result := public.py_object_call(ID_BOOL_TYPE, ARRAY[v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: bool("hi") raised error'; END IF;
    IF v_result IS DISTINCT FROM ID_TRUE_OBJ THEN RAISE EXCEPTION 'FAIL: bool("hi") expected True'; END IF;

    RAISE NOTICE '  ✓ Test 4: bool() constructors (0-arg, int 0/1, str ""/nonempty)';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 5: list() constructors
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- list() → []
    v_result := public.py_object_call(ID_LIST_TYPE, ARRAY[]::uuid[], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: list() raised error'; END IF;
    SELECT ob_item INTO v_list_items FROM public.py_list_object WHERE ob_base = v_result;
    IF COALESCE(array_length(v_list_items, 1), 0) != 0 THEN RAISE EXCEPTION 'FAIL: list() not empty'; END IF;

    -- list((1,2,3)) → [1,2,3]
    v_arg := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_arg, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_arg, 1);
    v_arg2 := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_arg2, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_arg2, 2);
    v_arg3 := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_arg3, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_arg3, 3);

    -- Create tuple (1,2,3)
    DECLARE
        v_tuple_id UUID := gen_random_uuid();
    BEGIN
        INSERT INTO public.py_object (id, ob_type) VALUES (v_tuple_id, ID_TUPLE_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (v_tuple_id, ARRAY[v_arg, v_arg2, v_arg3]);

        v_result := public.py_object_call(ID_LIST_TYPE, ARRAY[v_tuple_id], NULL);
        IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: list((1,2,3)) raised error'; END IF;
        SELECT ob_item INTO v_list_items FROM public.py_list_object WHERE ob_base = v_result;
        IF COALESCE(array_length(v_list_items, 1), 0) != 3 THEN RAISE EXCEPTION 'FAIL: list((1,2,3)) length expected 3, got %', COALESCE(array_length(v_list_items, 1), 0); END IF;
    END;

    RAISE NOTICE '  ✓ Test 5: list() constructors (0-arg, from tuple)';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 6: tuple() constructors
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- tuple() → ()
    v_result := public.py_object_call(ID_TUPLE_TYPE, ARRAY[]::uuid[], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: tuple() raised error'; END IF;
    SELECT ob_item INTO v_tuple_items FROM public.py_tuple_object WHERE ob_base = v_result;
    IF COALESCE(array_length(v_tuple_items, 1), 0) != 0 THEN RAISE EXCEPTION 'FAIL: tuple() not empty'; END IF;

    -- tuple([1,2,3]) → (1,2,3)
    DECLARE
        v_list_id UUID := gen_random_uuid();
    BEGIN
        INSERT INTO public.py_object (id, ob_type) VALUES (v_list_id, ID_LIST_TYPE);
        INSERT INTO public.py_list_object (ob_base, ob_item) VALUES (v_list_id, ARRAY[v_arg, v_arg2, v_arg3]);

        v_result := public.py_object_call(ID_TUPLE_TYPE, ARRAY[v_list_id], NULL);
        IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: tuple([1,2,3]) raised error'; END IF;
        SELECT ob_item INTO v_tuple_items FROM public.py_tuple_object WHERE ob_base = v_result;
        IF COALESCE(array_length(v_tuple_items, 1), 0) != 3 THEN RAISE EXCEPTION 'FAIL: tuple([1,2,3]) length expected 3, got %', COALESCE(array_length(v_tuple_items, 1), 0); END IF;
    END;

    RAISE NOTICE '  ✓ Test 6: tuple() constructors (0-arg, from list)';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 7: dict() constructor
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- dict() → {}
    v_result := public.py_object_call(ID_DICT_TYPE, ARRAY[]::uuid[], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: dict() raised error'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_dict_object WHERE ob_base = v_result) THEN
        RAISE EXCEPTION 'FAIL: dict() did not create dict object';
    END IF;

    RAISE NOTICE '  ✓ Test 7: dict() constructor (0-arg)';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 8: Bytecode: return int('42')
    -- RESUME 0 | PUSH_NULL | LOAD_NAME 0 (int) | LOAD_CONST 0 ('42') | PRECALL 1 | CALL 1 | RETURN_VALUE
    -- Hex: 9700020065006400a601ab015300
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    SELECT md_dict INTO builtins_dict_id FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    empty_str_id := public.py_str_from_text('');
    str_int_id := public.py_str_from_text('int');

    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, ARRAY[]::uuid[]);
    co_cellvars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_cellvars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_cellvars_id, ARRAY[]::uuid[]);
    co_freevars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_freevars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_freevars_id, ARRAY[]::uuid[]);

    -- co_consts: ('42',)
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[public.py_str_from_text('42')]);

    -- co_names: (int,)
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[str_int_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, decode('9700020065006400a601ab015300', 'hex'));

    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, co_cellvars_id, co_freevars_id, 0);

    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    v_result := public.py_eval_frame(frame_id);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: int("42") bytecode raised error'; END IF;
    IF v_result IS NULL THEN RAISE EXCEPTION 'FAIL: int("42") bytecode returned NULL'; END IF;
    SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = v_result;
    IF v_int_val IS DISTINCT FROM 42 THEN RAISE EXCEPTION 'FAIL: int("42") bytecode expected 42, got %', v_int_val; END IF;

    RAISE NOTICE '  ✓ Test 8: Bytecode int("42") → 42';
    pass_count := pass_count + 1;

    -- ================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE 'All type constructor tests passed!';
END $$;
