-- ============================================================================
-- Test: Common Builtins (isinstance, hasattr, getattr, setattr, id)
--
-- Tests:
--   1. isinstance(42, int) → True, isinstance(42, str) → False
--   2. isinstance with inheritance: isinstance(True, int) → True
--   3. isinstance with tuple: isinstance(42, (str, int)) → True
--   4. hasattr on instance with attribute → True, without → False
--   5. getattr with default: getattr(obj, 'missing', 99) → 99
--   6. setattr on instance, then getattr confirms value
--   7. id(obj) returns an int
--   8. Type objects are in builtins (int, str, float, etc.)
-- ============================================================================

SELECT set_config('pgthon.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE    UUID := '00000000-0000-4000-a000-000000000003';
    ID_FLOAT_TYPE  UUID := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE   UUID := '00000000-0000-4000-a000-000000000013';
    ID_LIST_TYPE   UUID := '00000000-0000-4000-a000-000000000005';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYPE_TYPE   UUID := '00000000-0000-4000-a000-000000000002';
    ID_NONE_OBJ    UUID := '00000000-0000-4000-b000-000000000001';
    ID_TRUE_OBJ    UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ   UUID := '00000000-0000-4000-b000-000000000011';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';

    -- Builtin function IDs
    ID_ISINSTANCE_FUNCTION UUID := '00000000-0000-4000-b000-000000000008';
    ID_HASATTR_FUNCTION    UUID := '00000000-0000-4000-b000-000000000009';
    ID_GETATTR_FUNCTION    UUID := '00000000-0000-4000-b000-00000000000a';
    ID_SETATTR_FUNCTION    UUID := '00000000-0000-4000-b000-00000000000b';
    ID_ID_FUNCTION         UUID := '00000000-0000-4000-b000-00000000000c';

    test_count INT := 0;
    pass_count INT := 0;

    v_result UUID;
    v_int_val NUMERIC;
    v_arg UUID;
    v_str_name UUID;
    v_str_val TEXT;
    builtins_dict_id UUID;

    -- For instance tests
    v_class_id UUID;
    v_bases_tuple UUID;
    v_class_dict UUID;
    v_instance_id UUID;
    v_inst_dict UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Common Builtins Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    SELECT md_dict INTO builtins_dict_id FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    -- ================================================================
    -- Test 1: isinstance(42, int) → True, isinstance(42, str) → False
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    v_arg := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_arg, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_arg, 42);

    -- isinstance(42, int) → True
    v_result := public.py_builtin_isinstance(ID_ISINSTANCE_FUNCTION, ARRAY[v_arg, ID_INT_TYPE], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: isinstance(42, int) raised error'; END IF;
    IF v_result IS DISTINCT FROM ID_TRUE_OBJ THEN RAISE EXCEPTION 'FAIL: isinstance(42, int) expected True'; END IF;

    -- isinstance(42, str) → False
    v_result := public.py_builtin_isinstance(ID_ISINSTANCE_FUNCTION, ARRAY[v_arg, ID_STR_TYPE], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: isinstance(42, str) raised error'; END IF;
    IF v_result IS DISTINCT FROM ID_FALSE_OBJ THEN RAISE EXCEPTION 'FAIL: isinstance(42, str) expected False'; END IF;

    RAISE NOTICE '  ✓ Test 1: isinstance(42, int) → True, isinstance(42, str) → False';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 2: isinstance with inheritance: isinstance(True, object) → True
    -- (bool's tp_bases includes object)
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    v_result := public.py_builtin_isinstance(ID_ISINSTANCE_FUNCTION, ARRAY[ID_TRUE_OBJ, ID_OBJECT_TYPE], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: isinstance(True, object) raised error'; END IF;
    IF v_result IS DISTINCT FROM ID_TRUE_OBJ THEN RAISE EXCEPTION 'FAIL: isinstance(True, object) expected True'; END IF;

    RAISE NOTICE '  ✓ Test 2: isinstance(True, object) → True (inheritance)';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 3: isinstance with tuple: isinstance(42, (str, int)) → True
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    DECLARE
        v_type_tuple UUID := gen_random_uuid();
    BEGIN
        INSERT INTO public.py_object (id, ob_type) VALUES (v_type_tuple, ID_TUPLE_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (v_type_tuple, ARRAY[ID_STR_TYPE, ID_INT_TYPE]);

        v_result := public.py_builtin_isinstance(ID_ISINSTANCE_FUNCTION, ARRAY[v_arg, v_type_tuple], NULL);
        IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: isinstance(42, (str, int)) raised error'; END IF;
        IF v_result IS DISTINCT FROM ID_TRUE_OBJ THEN RAISE EXCEPTION 'FAIL: isinstance(42, (str, int)) expected True'; END IF;
    END;

    RAISE NOTICE '  ✓ Test 3: isinstance(42, (str, int)) → True (tuple of types)';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 4: hasattr on instance
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- Create a simple class with attribute 'x' in tp_dict
    v_bases_tuple := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_bases_tuple, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (v_bases_tuple, ARRAY[ID_OBJECT_TYPE]);

    v_class_dict := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_class_dict, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (v_class_dict);

    -- Store x=100 in class dict
    DECLARE
        v_x_key UUID := public.py_str_from_text('x');
        v_x_val UUID := gen_random_uuid();
    BEGIN
        INSERT INTO public.py_object (id, ob_type) VALUES (v_x_val, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_x_val, 100);
        PERFORM public.py_dict_set_item(v_class_dict, v_x_key, v_x_val);

        v_class_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (v_class_id, ID_TYPE_TYPE);
        INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
        VALUES (v_class_id, 'TestClass', v_bases_tuple, v_class_dict);

        -- Create instance
        v_instance_id := public.py_object_call(v_class_id, ARRAY[]::uuid[], NULL);
        IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: TestClass() raised error'; END IF;

        -- hasattr(instance, 'x') → True (inherited from class)
        v_result := public.py_builtin_hasattr(ID_HASATTR_FUNCTION, ARRAY[v_instance_id, v_x_key], NULL);
        IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: hasattr(inst, "x") raised error'; END IF;
        IF v_result IS DISTINCT FROM ID_TRUE_OBJ THEN RAISE EXCEPTION 'FAIL: hasattr(inst, "x") expected True'; END IF;

        -- hasattr(instance, 'missing') → False
        v_str_name := public.py_str_from_text('missing');
        v_result := public.py_builtin_hasattr(ID_HASATTR_FUNCTION, ARRAY[v_instance_id, v_str_name], NULL);
        IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: hasattr(inst, "missing") raised error'; END IF;
        IF v_result IS DISTINCT FROM ID_FALSE_OBJ THEN RAISE EXCEPTION 'FAIL: hasattr(inst, "missing") expected False'; END IF;
    END;

    RAISE NOTICE '  ✓ Test 4: hasattr (True for class attr, False for missing)';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 5: getattr with default
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- getattr(instance, 'missing', 99) → 99
    v_str_name := public.py_str_from_text('missing');
    v_arg := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_arg, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_arg, 99);

    v_result := public.py_builtin_getattr(ID_GETATTR_FUNCTION, ARRAY[v_instance_id, v_str_name, v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: getattr(inst, "missing", 99) raised error'; END IF;
    SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = v_result;
    IF v_int_val IS DISTINCT FROM 99 THEN RAISE EXCEPTION 'FAIL: getattr default expected 99, got %', v_int_val; END IF;

    RAISE NOTICE '  ✓ Test 5: getattr(inst, "missing", 99) → 99';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 6: setattr then getattr
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    v_str_name := public.py_str_from_text('color');
    v_arg := public.py_str_from_text('red');

    -- setattr(instance, 'color', 'red')
    v_result := public.py_builtin_setattr(ID_SETATTR_FUNCTION, ARRAY[v_instance_id, v_str_name, v_arg], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: setattr(inst, "color", "red") raised error'; END IF;
    IF v_result IS DISTINCT FROM ID_NONE_OBJ THEN RAISE EXCEPTION 'FAIL: setattr should return None'; END IF;

    -- getattr(instance, 'color') → 'red'
    v_result := public.py_builtin_getattr(ID_GETATTR_FUNCTION, ARRAY[v_instance_id, v_str_name], NULL);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: getattr(inst, "color") raised error'; END IF;
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_result;
    IF v_str_val IS DISTINCT FROM 'red' THEN RAISE EXCEPTION 'FAIL: getattr expected "red", got "%"', v_str_val; END IF;

    RAISE NOTICE '  ✓ Test 6: setattr(inst, "color", "red") → getattr(inst, "color") == "red"';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 7: id(obj) returns an int
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    v_result := public.py_builtin_id(v_instance_id);
    IF public.py_err_occurred() THEN RAISE EXCEPTION 'FAIL: id(obj) raised error'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = v_result) THEN
        RAISE EXCEPTION 'FAIL: id(obj) did not return an int';
    END IF;

    RAISE NOTICE '  ✓ Test 7: id(obj) returns an int object';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 8: Type objects are in builtins dict
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- Check int is in builtins
    v_str_name := public.py_str_from_text('int');
    v_result := public.py_dict_get_item(builtins_dict_id, v_str_name);
    IF v_result IS DISTINCT FROM ID_INT_TYPE THEN
        RAISE EXCEPTION 'FAIL: builtins["int"] expected %, got %', ID_INT_TYPE, v_result;
    END IF;

    -- Check str is in builtins
    v_str_name := public.py_str_from_text('str');
    v_result := public.py_dict_get_item(builtins_dict_id, v_str_name);
    IF v_result IS DISTINCT FROM ID_STR_TYPE THEN
        RAISE EXCEPTION 'FAIL: builtins["str"] expected %, got %', ID_STR_TYPE, v_result;
    END IF;

    -- Check float is in builtins
    v_str_name := public.py_str_from_text('float');
    v_result := public.py_dict_get_item(builtins_dict_id, v_str_name);
    IF v_result IS DISTINCT FROM ID_FLOAT_TYPE THEN
        RAISE EXCEPTION 'FAIL: builtins["float"] expected %, got %', ID_FLOAT_TYPE, v_result;
    END IF;

    -- Check bool is in builtins
    v_str_name := public.py_str_from_text('bool');
    v_result := public.py_dict_get_item(builtins_dict_id, v_str_name);
    IF v_result IS DISTINCT FROM ID_BOOL_TYPE THEN
        RAISE EXCEPTION 'FAIL: builtins["bool"] expected %, got %', ID_BOOL_TYPE, v_result;
    END IF;

    RAISE NOTICE '  ✓ Test 8: int/str/float/bool are registered in builtins dict';
    pass_count := pass_count + 1;

    -- ================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE 'All common builtins tests passed!';
END $$;
