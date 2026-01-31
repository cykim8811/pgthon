-- ============================================================================
-- Test: Jump — py_object_istrue (PyObject_IsTrue)
--
-- Purpose:
--   Phase 1(240300) 이후 py_object_istrue가 CPython truth testing 규칙에 맞게
--   동작하는지 검증. 싱글톤·int·str·float·list·tuple·dict·기본값.
--
-- Usage:
--   Run after migration 20260114240300_py_object_istrue.sql.
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE  uuid := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE     uuid := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE     uuid := '00000000-0000-4000-a000-000000000004';
    ID_FLOAT_TYPE   uuid := '00000000-0000-4000-a000-00000000000a';
    ID_LIST_TYPE    uuid := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE    uuid := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE   uuid := '00000000-0000-4000-a000-000000000007';
    ID_TRUE_OBJ    uuid := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ   uuid := '00000000-0000-4000-b000-000000000011';
    ID_NONE_OBJ    uuid := '00000000-0000-4000-b000-000000000001';
    ID_NOT_IMPLEMENTED_OBJ uuid := '00000000-0000-4000-b000-000000000012';

    test_count integer := 0;
    pass_count integer := 0;
    obj_id uuid;
    ist bool;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Jump (py_object_istrue) Slots Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Singletons
    RAISE NOTICE 'Test 1: True singleton -> true';
    test_count := test_count + 1;
    IF NOT public.py_object_istrue(ID_TRUE_OBJ) THEN
        RAISE EXCEPTION 'FAIL: py_object_istrue(True) should be true';
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ True -> true';

    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: False/None/NotImplemented -> false';
    test_count := test_count + 1;
    IF public.py_object_istrue(ID_FALSE_OBJ) OR public.py_object_istrue(ID_NONE_OBJ) OR public.py_object_istrue(ID_NOT_IMPLEMENTED_OBJ) THEN
        RAISE EXCEPTION 'FAIL: py_object_istrue(False/None/NotImplemented) should be false';
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ False/None/NotImplemented -> false';

    -- int: 0 -> false, 1 -> true
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: int 0 -> false, 1 -> true';
    test_count := test_count + 1;
    obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (obj_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (obj_id, 0);
    IF public.py_object_istrue(obj_id) THEN
        RAISE EXCEPTION 'FAIL: py_object_istrue(0) should be false';
    END IF;
    UPDATE public.py_long_object SET long_value = 1 WHERE ob_base = obj_id;
    IF NOT public.py_object_istrue(obj_id) THEN
        RAISE EXCEPTION 'FAIL: py_object_istrue(1) should be true';
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ int 0 -> false, 1 -> true';

    -- str: '' -> false, 'x' -> true
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: str '''' -> false, ''x'' -> true';
    test_count := test_count + 1;
    obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (obj_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (obj_id, '');
    IF public.py_object_istrue(obj_id) THEN
        RAISE EXCEPTION 'FAIL: py_object_istrue('''') should be false';
    END IF;
    UPDATE public.py_unicode_object SET str_value = 'x' WHERE ob_base = obj_id;
    IF NOT public.py_object_istrue(obj_id) THEN
        RAISE EXCEPTION 'FAIL: py_object_istrue(''x'') should be true';
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ str '''' -> false, ''x'' -> true';

    -- list: empty -> false, non-empty -> true
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: list empty -> false, non-empty -> true';
    test_count := test_count + 1;
    obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (obj_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item) VALUES (obj_id, array[]::uuid[]);
    IF public.py_object_istrue(obj_id) THEN
        RAISE EXCEPTION 'FAIL: py_object_istrue([]) should be false';
    END IF;
    UPDATE public.py_list_object SET ob_item = array[obj_id] WHERE ob_base = obj_id;
    IF NOT public.py_object_istrue(obj_id) THEN
        RAISE EXCEPTION 'FAIL: py_object_istrue([x]) should be true';
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ list empty -> false, non-empty -> true';

    -- dict: empty -> false
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: dict empty -> false';
    test_count := test_count + 1;
    obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (obj_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (obj_id);
    IF public.py_object_istrue(obj_id) THEN
        RAISE EXCEPTION 'FAIL: py_object_istrue({{}}) should be false';
    END IF;
    pass_count := pass_count + 1;
    RAISE NOTICE '  ✓ dict empty -> false';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total: %  Passed: %', test_count, pass_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'FAIL: % test(s) failed', test_count - pass_count;
    END IF;
    RAISE NOTICE '✓ All py_object_istrue tests passed!';
END $$;
