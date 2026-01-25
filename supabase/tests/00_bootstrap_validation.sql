-- ============================================================================
-- Test: Bootstrap Validation
-- 
-- Purpose:
--   Validates that the CPython bootstrap migration correctly created all
--   builtin types, singletons, and their relationships. This test verifies:
--   - Builtin types exist with correct UUIDs and names
--   - Each object has the correct ob_type
--   - Inheritance structure (tp_bases) is correct
--   - tp_dict assignments are correct
--   - None singleton is properly created
--
-- Usage:
--   Run this file after migrations to verify bootstrap integrity.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

DO $$
DECLARE
    -- Builtin Type UUIDs (from bootstrap migration)
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYPE_TYPE   UUID := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE    UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_FLOAT_TYPE  UUID := '00000000-0000-4000-a000-000000000009';
    ID_LIST_TYPE   UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_NONE_TYPE   UUID := '00000000-0000-4000-a000-000000000008';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    ID_MODULE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_NONE_OBJ    UUID := '00000000-0000-4000-b000-000000000001';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_LEN_FUNCTION UUID := '00000000-0000-4000-b000-000000000003';

    -- Test counters
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    
    -- Helper variables
    actual_ob_type UUID;
    actual_tp_name TEXT;
    actual_tp_bases UUID;
    actual_tp_dict UUID;
    tuple_bases_id UUID;
    tuple_content UUID[];
    type_count INTEGER;
    -- Variables for len function test
    len_ml_name UUID;
    len_ml_flags INTEGER;
    len_ml_doc UUID;
    len_m_self UUID;
    len_m_module UUID;
    len_name_str TEXT;
    len_doc_str TEXT;
    builtins_dict_id UUID;
    len_key_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Bootstrap Validation Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- Test 1: Verify builtin types exist in py_object
    -- ========================================================================
    RAISE NOTICE 'Test 1: Verifying builtin types exist...';
    test_count := test_count + 1;
    
    SELECT COUNT(*) INTO type_count
    FROM public.py_object
    WHERE id IN (ID_OBJECT_TYPE, ID_TYPE_TYPE, ID_STR_TYPE, ID_INT_TYPE, 
                 ID_FLOAT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE,
                 ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, ID_MODULE_TYPE);
    
    IF type_count = 11 THEN
        RAISE NOTICE '  ✓ All 11 builtin types exist in py_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 11 builtin types, found %', type_count;
    END IF;

    -- ========================================================================
    -- Test 2: Verify type names are correct
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Verifying type names...';
    
    -- object
    test_count := test_count + 1;
    SELECT tp_name INTO actual_tp_name FROM public.py_type_object WHERE ob_base = ID_OBJECT_TYPE;
    IF actual_tp_name = 'object' THEN
        RAISE NOTICE '  ✓ object type has correct name';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: object type name is "%", expected "object"', actual_tp_name;
    END IF;
    
    -- type
    test_count := test_count + 1;
    SELECT tp_name INTO actual_tp_name FROM public.py_type_object WHERE ob_base = ID_TYPE_TYPE;
    IF actual_tp_name = 'type' THEN
        RAISE NOTICE '  ✓ type type has correct name';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: type type name is "%", expected "type"', actual_tp_name;
    END IF;
    
    -- str, int, float, list, dict, tuple, NoneType, builtin_function_or_method, module
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count
    FROM public.py_type_object
    WHERE ob_base IN (ID_STR_TYPE, ID_INT_TYPE, ID_FLOAT_TYPE, ID_LIST_TYPE, 
                      ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, ID_MODULE_TYPE)
      AND tp_name IN ('str', 'int', 'float', 'list', 'dict', 'tuple', 'NoneType', 'builtin_function_or_method', 'module');
    
    IF type_count = 9 THEN
        RAISE NOTICE '  ✓ All other builtin types have correct names';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 9 types with correct names, found %', type_count;
    END IF;

    -- ========================================================================
    -- Test 3: Verify ob_type for type objects (all should be 'type')
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Verifying ob_type for type objects...';
    test_count := test_count + 1;
    
    SELECT COUNT(*) INTO type_count
    FROM public.py_object
    WHERE id IN (ID_OBJECT_TYPE, ID_TYPE_TYPE, ID_STR_TYPE, ID_INT_TYPE, 
                 ID_FLOAT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE,
                 ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, ID_MODULE_TYPE)
      AND ob_type = ID_TYPE_TYPE;
    
    IF type_count = 11 THEN
        RAISE NOTICE '  ✓ All type objects have ob_type = type';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 11 type objects with ob_type=type, found %', type_count;
    END IF;

    -- ========================================================================
    -- Test 4: Verify 'type' type has itself as ob_type (metaclass)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Verifying type type has itself as ob_type...';
    test_count := test_count + 1;
    
    SELECT ob_type INTO actual_ob_type FROM public.py_object WHERE id = ID_TYPE_TYPE;
    IF actual_ob_type = ID_TYPE_TYPE THEN
        RAISE NOTICE '  ✓ type type has itself as ob_type (metaclass behavior)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: type type ob_type is %, expected %', actual_ob_type, ID_TYPE_TYPE;
    END IF;

    -- ========================================================================
    -- Test 5: Verify None singleton exists and has correct type
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Verifying None singleton...';
    
    -- None object exists in py_object
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count FROM public.py_object WHERE id = ID_NONE_OBJ;
    IF type_count = 1 THEN
        RAISE NOTICE '  ✓ None object exists in py_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: None object not found in py_object';
    END IF;
    
    -- None object has correct ob_type
    test_count := test_count + 1;
    SELECT ob_type INTO actual_ob_type FROM public.py_object WHERE id = ID_NONE_OBJ;
    IF actual_ob_type = ID_NONE_TYPE THEN
        RAISE NOTICE '  ✓ None object has ob_type = NoneType';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: None object ob_type is %, expected %', actual_ob_type, ID_NONE_TYPE;
    END IF;
    
    -- None object exists in py_none_object
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count FROM public.py_none_object WHERE ob_base = ID_NONE_OBJ;
    IF type_count = 1 THEN
        RAISE NOTICE '  ✓ None object exists in py_none_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: None object not found in py_none_object';
    END IF;

    -- ========================================================================
    -- Test 6: Verify inheritance structure (tp_bases)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: Verifying inheritance structure...';
    
    -- object has no base class (tp_bases is NULL)
    test_count := test_count + 1;
    SELECT tp_bases INTO actual_tp_bases FROM public.py_type_object WHERE ob_base = ID_OBJECT_TYPE;
    IF actual_tp_bases IS NULL THEN
        RAISE NOTICE '  ✓ object has no base class (tp_bases is NULL)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: object tp_bases is %, expected NULL', actual_tp_bases;
    END IF;
    
    -- Find the tp_bases tuple ID (should be shared by type and other types)
    SELECT tp_bases INTO tuple_bases_id FROM public.py_type_object WHERE ob_base = ID_TYPE_TYPE;
    
    -- type inherits from object
    test_count := test_count + 1;
    IF tuple_bases_id IS NOT NULL THEN
        RAISE NOTICE '  ✓ type has tp_bases (inherits from object)';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: type tp_bases is NULL, expected tuple';
    END IF;
    
    -- Verify tp_bases tuple contains only object
    test_count := test_count + 1;
    SELECT ob_item INTO tuple_content FROM public.py_tuple_object WHERE ob_base = tuple_bases_id;
    IF tuple_content = ARRAY[ID_OBJECT_TYPE] THEN
        RAISE NOTICE '  ✓ tp_bases tuple contains only object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: tp_bases tuple content is %, expected [%]', tuple_content, ID_OBJECT_TYPE;
    END IF;
    
    -- Verify tp_bases tuple has correct ob_type
    test_count := test_count + 1;
    SELECT ob_type INTO actual_ob_type FROM public.py_object WHERE id = tuple_bases_id;
    IF actual_ob_type = ID_TUPLE_TYPE THEN
        RAISE NOTICE '  ✓ tp_bases tuple has ob_type = tuple';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: tp_bases tuple ob_type is %, expected %', actual_ob_type, ID_TUPLE_TYPE;
    END IF;
    
    -- All other types inherit from object (share the same tp_bases tuple)
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count
    FROM public.py_type_object
    WHERE ob_base IN (ID_STR_TYPE, ID_INT_TYPE, ID_FLOAT_TYPE, ID_LIST_TYPE, 
                      ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE)
      AND tp_bases = tuple_bases_id;
    
    IF type_count = 7 THEN
        RAISE NOTICE '  ✓ All other builtin types inherit from object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 7 types inheriting from object, found %', type_count;
    END IF;

    -- ========================================================================
    -- Test 7: Verify tp_dict assignments
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 7: Verifying tp_dict assignments...';
    
    -- Each type should have a tp_dict
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count
    FROM public.py_type_object
    WHERE ob_base IN (ID_OBJECT_TYPE, ID_TYPE_TYPE, ID_STR_TYPE, ID_INT_TYPE, 
                      ID_FLOAT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE)
      AND tp_dict IS NOT NULL;
    
    IF type_count = 9 THEN
        RAISE NOTICE '  ✓ All types have tp_dict assigned';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 9 types with tp_dict, found %', type_count;
    END IF;
    
    -- Each tp_dict should be a dict object (have ob_type = dict)
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count
    FROM public.py_type_object t
    JOIN public.py_object o ON t.tp_dict = o.id
    WHERE t.ob_base IN (ID_OBJECT_TYPE, ID_TYPE_TYPE, ID_STR_TYPE, ID_INT_TYPE, 
                        ID_FLOAT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE)
      AND o.ob_type = ID_DICT_TYPE;
    
    IF type_count = 9 THEN
        RAISE NOTICE '  ✓ All tp_dict objects have ob_type = dict';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 9 tp_dict objects with ob_type=dict, found %', type_count;
    END IF;
    
    -- Each tp_dict should exist in py_dict_object
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count
    FROM public.py_type_object t
    JOIN public.py_dict_object d ON t.tp_dict = d.ob_base
    WHERE t.ob_base IN (ID_OBJECT_TYPE, ID_TYPE_TYPE, ID_STR_TYPE, ID_INT_TYPE, 
                        ID_FLOAT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE);
    
    IF type_count = 9 THEN
        RAISE NOTICE '  ✓ All tp_dict objects exist in py_dict_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 9 tp_dict objects in py_dict_object, found %', type_count;
    END IF;

    -- ========================================================================
    -- Test 8: Verify shared-PK inheritance structure
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 8: Verifying shared-PK inheritance...';
    
    -- Each type object's ob_base should equal its py_object.id
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count
    FROM public.py_type_object t
    JOIN public.py_object o ON t.ob_base = o.id
    WHERE t.ob_base IN (ID_OBJECT_TYPE, ID_TYPE_TYPE, ID_STR_TYPE, ID_INT_TYPE, 
                        ID_FLOAT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE,
                        ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, ID_MODULE_TYPE);
    
    IF type_count = 11 THEN
        RAISE NOTICE '  ✓ All type objects use shared-PK inheritance correctly';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: Shared-PK inheritance verification failed, found % matches', type_count;
    END IF;

    -- ========================================================================
    -- Test 9: Verify builtin_function_or_method type
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 9: Verifying builtin_function_or_method type...';
    
    -- Verify type name
    test_count := test_count + 1;
    SELECT tp_name INTO actual_tp_name FROM public.py_type_object WHERE ob_base = ID_BUILTIN_FUNCTION_OR_METHOD_TYPE;
    IF actual_tp_name = 'builtin_function_or_method' THEN
        RAISE NOTICE '  ✓ builtin_function_or_method type has correct name';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: builtin_function_or_method type name is "%", expected "builtin_function_or_method"', actual_tp_name;
    END IF;
    
    -- Verify ob_type
    test_count := test_count + 1;
    SELECT ob_type INTO actual_ob_type FROM public.py_object WHERE id = ID_BUILTIN_FUNCTION_OR_METHOD_TYPE;
    IF actual_ob_type = ID_TYPE_TYPE THEN
        RAISE NOTICE '  ✓ builtin_function_or_method type has ob_type = type';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: builtin_function_or_method type ob_type is %, expected %', actual_ob_type, ID_TYPE_TYPE;
    END IF;
    
    -- Verify inheritance (inherits from object)
    test_count := test_count + 1;
    SELECT tp_bases INTO actual_tp_bases FROM public.py_type_object WHERE ob_base = ID_BUILTIN_FUNCTION_OR_METHOD_TYPE;
    IF actual_tp_bases IS NOT NULL THEN
        -- Check that tp_bases tuple contains object
        SELECT ob_item INTO tuple_content FROM public.py_tuple_object WHERE ob_base = actual_tp_bases;
        IF array_length(tuple_content, 1) = 1 AND tuple_content[1] = ID_OBJECT_TYPE THEN
            RAISE NOTICE '  ✓ builtin_function_or_method type inherits from object';
            pass_count := pass_count + 1;
        ELSE
            RAISE EXCEPTION 'FAIL: builtin_function_or_method type tp_bases does not contain object';
        END IF;
    ELSE
        RAISE EXCEPTION 'FAIL: builtin_function_or_method type tp_bases is NULL';
    END IF;

    -- ========================================================================
    -- Test 10: Verify module type
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 10: Verifying module type...';
    
    -- Verify type name
    test_count := test_count + 1;
    SELECT tp_name INTO actual_tp_name FROM public.py_type_object WHERE ob_base = ID_MODULE_TYPE;
    IF actual_tp_name = 'module' THEN
        RAISE NOTICE '  ✓ module type has correct name';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: module type name is "%", expected "module"', actual_tp_name;
    END IF;
    
    -- Verify ob_type
    test_count := test_count + 1;
    SELECT ob_type INTO actual_ob_type FROM public.py_object WHERE id = ID_MODULE_TYPE;
    IF actual_ob_type = ID_TYPE_TYPE THEN
        RAISE NOTICE '  ✓ module type has ob_type = type';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: module type ob_type is %, expected %', actual_ob_type, ID_TYPE_TYPE;
    END IF;

    -- ========================================================================
    -- Test 11: Verify __builtins__ module
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 11: Verifying __builtins__ module...';
    
    -- Verify module exists
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count
    FROM public.py_object
    WHERE id = ID_BUILTINS_MODULE;
    
    IF type_count = 1 THEN
        RAISE NOTICE '  ✓ __builtins__ module exists in py_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: __builtins__ module does not exist';
    END IF;
    
    -- Verify module ob_type
    test_count := test_count + 1;
    SELECT ob_type INTO actual_ob_type FROM public.py_object WHERE id = ID_BUILTINS_MODULE;
    IF actual_ob_type = ID_MODULE_TYPE THEN
        RAISE NOTICE '  ✓ __builtins__ module has ob_type = module';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: __builtins__ module ob_type is %, expected %', actual_ob_type, ID_MODULE_TYPE;
    END IF;
    
    -- Verify module object exists
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count
    FROM public.py_module_object
    WHERE ob_base = ID_BUILTINS_MODULE;
    
    IF type_count = 1 THEN
        RAISE NOTICE '  ✓ __builtins__ module object exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: __builtins__ module object does not exist';
    END IF;
    
    -- Verify module md_dict and md_name are set
    test_count := test_count + 1;
    SELECT md_dict, md_name INTO actual_tp_dict, actual_tp_name
    FROM public.py_module_object
    WHERE ob_base = ID_BUILTINS_MODULE;
    
    IF actual_tp_dict IS NOT NULL AND actual_tp_name IS NOT NULL THEN
        RAISE NOTICE '  ✓ __builtins__ module has md_dict and md_name set';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: __builtins__ module md_dict or md_name is NULL';
    END IF;

    -- ========================================================================
    -- Test 12: Verify len builtin function
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 12: Verifying len builtin function...';
    
    -- Verify len function exists in py_object
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count
    FROM public.py_object
    WHERE id = ID_LEN_FUNCTION;
    
    IF type_count = 1 THEN
        RAISE NOTICE '  ✓ len function exists in py_object';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: len function does not exist';
    END IF;
    
    -- Verify len function ob_type
    test_count := test_count + 1;
    SELECT ob_type INTO actual_ob_type FROM public.py_object WHERE id = ID_LEN_FUNCTION;
    IF actual_ob_type = ID_BUILTIN_FUNCTION_OR_METHOD_TYPE THEN
        RAISE NOTICE '  ✓ len function has ob_type = builtin_function_or_method';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: len function ob_type is %, expected %', actual_ob_type, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE;
    END IF;
    
    -- Verify len function object exists
    test_count := test_count + 1;
    SELECT COUNT(*) INTO type_count
    FROM public.py_cfunction_object
    WHERE ob_base = ID_LEN_FUNCTION;
    
    IF type_count = 1 THEN
        RAISE NOTICE '  ✓ len function object exists';
        pass_count := pass_count + 1;
    ELSE
        RAISE EXCEPTION 'FAIL: len function object does not exist';
    END IF;
    
    -- Verify len function m_ml_name, m_ml_flags, m_ml_doc
    test_count := test_count + 1;
    SELECT m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module
    INTO len_ml_name, len_ml_flags, len_ml_doc, len_m_self, len_m_module
    FROM public.py_cfunction_object
    WHERE ob_base = ID_LEN_FUNCTION;
    
    IF len_ml_name IS NULL THEN
        RAISE EXCEPTION 'FAIL: len function m_ml_name is NULL';
    END IF;
    
    IF len_ml_flags IS NULL OR len_ml_flags != 8 THEN
        RAISE EXCEPTION 'FAIL: len function m_ml_flags is %, expected 8 (METH_O)', len_ml_flags;
    END IF;
    
    IF len_ml_doc IS NULL THEN
        RAISE EXCEPTION 'FAIL: len function m_ml_doc is NULL';
    END IF;
    
    IF len_m_self IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: len function m_self is not NULL (expected NULL for unbound function)';
    END IF;
    
    IF len_m_module != ID_BUILTINS_MODULE THEN
        RAISE EXCEPTION 'FAIL: len function m_module is %, expected %', len_m_module, ID_BUILTINS_MODULE;
    END IF;
    
    -- Verify function name string
    SELECT str_value INTO len_name_str
    FROM public.py_unicode_object
    WHERE ob_base = len_ml_name;
    
    IF len_name_str != 'len' THEN
        RAISE EXCEPTION 'FAIL: len function m_ml_name string is "%", expected "len"', len_name_str;
    END IF;
    
    -- Verify function docstring
    SELECT str_value INTO len_doc_str
    FROM public.py_unicode_object
    WHERE ob_base = len_ml_doc;
    
    IF len_doc_str != 'Return the number of items in a container.' THEN
        RAISE EXCEPTION 'FAIL: len function m_ml_doc string is "%", expected "Return the number of items in a container."', len_doc_str;
    END IF;
    
    RAISE NOTICE '  ✓ len function has correct m_ml_name, m_ml_flags (METH_O), m_ml_doc, m_self (NULL), m_module';
    pass_count := pass_count + 1;
    
    -- Verify len function is registered in __builtins__ module dict
    test_count := test_count + 1;
    -- Get __builtins__ module dict
    SELECT md_dict INTO builtins_dict_id
    FROM public.py_module_object
    WHERE ob_base = ID_BUILTINS_MODULE;
    
    -- Find "len" key in the dict
    SELECT me_key INTO len_key_id
    FROM public.py_dict_entry
    WHERE dict_id = builtins_dict_id
    AND me_value = ID_LEN_FUNCTION;
    
    IF len_key_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: len function is not registered in __builtins__ module dict';
    END IF;
    
    -- Verify the key is the "len" string
    SELECT str_value INTO len_name_str
    FROM public.py_unicode_object
    WHERE ob_base = len_key_id;
    
    IF len_name_str != 'len' THEN
        RAISE EXCEPTION 'FAIL: len function dict key is "%", expected "len"', len_name_str;
    END IF;
    
    RAISE NOTICE '  ✓ len function is registered in __builtins__ module dict';
    pass_count := pass_count + 1;

    -- ========================================================================
    -- Test Summary
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total tests: %', test_count;
    RAISE NOTICE 'Passed: %', pass_count;
    RAISE NOTICE 'Failed: %', fail_count;
    RAISE NOTICE '';
    
    IF fail_count = 0 THEN
        RAISE NOTICE '✓ All tests passed! Bootstrap is valid.';
    ELSE
        RAISE EXCEPTION '✗ % test(s) failed. Bootstrap validation failed.', fail_count;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Test Failed';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Error: %', SQLERRM;
        RAISE NOTICE '';
        RAISE NOTICE 'Tests completed: %', test_count;
        RAISE NOTICE 'Passed: %', pass_count;
        RAISE NOTICE 'Failed: %', fail_count;
        RAISE;
END $$;
