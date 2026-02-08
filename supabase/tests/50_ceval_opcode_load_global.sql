-- ============================================================================
-- Test: VM LOAD_GLOBAL Opcode Test (CPython 3.11 opcode 116)
--
-- Purpose:
--   Tests that LOAD_GLOBAL opcode handler works correctly. This verifies:
--   - py_opcode_LOAD_GLOBAL loads from globals then builtins only (no locals)
--   - Namespace lookup order: globals → builtins (locals ignored)
--   - Values are pushed onto the evaluation stack
--   - Index validation works correctly
--   - NameError is raised when name is not found
--
-- Usage:
--   Run this file after migrations to verify LOAD_GLOBAL opcode implementation.
-- ============================================================================

DO $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_LEN_FUNCTION UUID := '00000000-0000-4000-b000-000000000003';
    
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    
    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_names_id UUID;
    co_consts_id UUID;
    
    const0_id UUID;
    name0_str_id UUID;
    len_str_id UUID;
    loaded_obj_id UUID;
    exc_type_id UUID;
    stack_size INTEGER;
    
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
    real_builtins_dict_id UUID;
    
    error_message TEXT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM LOAD_GLOBAL Opcode Test (CPython 3.11 opcode 116)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- Setup
    RAISE NOTICE 'Setting up test environment...';
    
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 42);
    
    name0_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name0_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name0_str_id, 'x');
    
    SELECT ob_base INTO len_str_id FROM public.py_unicode_object WHERE str_value = 'len' LIMIT 1;
    IF len_str_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: ''len'' string not found in bootstrap.';
    END IF;
    
    SELECT md_dict INTO real_builtins_dict_id FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;
    IF real_builtins_dict_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: __builtins__ module dict not found.';
    END IF;
    
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    
    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
    
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, array[]::uuid[]);
    
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    
    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);
    
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id]);
    
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x'::bytea);
    
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
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';
    
    -- Test 1: py_opcode_LOAD_GLOBAL exists
    RAISE NOTICE 'Test 1: Function exists...';
    test_count := test_count + 1;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_load_global'
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    ) THEN
        RAISE EXCEPTION 'FAIL: py_opcode_LOAD_GLOBAL function does not exist';
    END IF;
    RAISE NOTICE '  ✓ py_opcode_LOAD_GLOBAL function exists';
    pass_count := pass_count + 1;
    
    -- Test 2: LOAD_GLOBAL loads from globals
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: LOAD_GLOBAL loads from globals...';
    test_count := test_count + 1;
    INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
    VALUES (globals_dict_id, name0_str_id, const0_id, public.py_object_hash(name0_str_id));
    
    PERFORM public.py_opcode_LOAD_GLOBAL(frame_id, 0);
    
    SELECT array_length(f_valuestack, 1) INTO stack_size FROM public.py_frame_object WHERE ob_base = frame_id;
    IF stack_size != 1 THEN
        RAISE EXCEPTION 'FAIL: Stack size after LOAD_GLOBAL is %, expected 1', stack_size;
    END IF;
    SELECT f_valuestack[1] INTO loaded_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF loaded_obj_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Loaded value is %, expected % (const0_id)', loaded_obj_id, const0_id;
    END IF;
    RAISE NOTICE '  ✓ LOAD_GLOBAL correctly loads from globals';
    pass_count := pass_count + 1;
    
    -- Test 3: LOAD_GLOBAL loads from builtins when not in globals
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: LOAD_GLOBAL loads from builtins when not in globals...';
    test_count := test_count + 1;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[] WHERE ob_base = frame_id;
    DELETE FROM public.py_dict_entry WHERE dict_id = globals_dict_id AND me_key = len_str_id;
    UPDATE public.py_frame_object SET f_builtins = real_builtins_dict_id WHERE ob_base = frame_id;
    UPDATE public.py_tuple_object SET ob_item = ARRAY[len_str_id] WHERE ob_base = co_names_id;
    
    PERFORM public.py_opcode_LOAD_GLOBAL(frame_id, 0);
    
    SELECT array_length(f_valuestack, 1) INTO stack_size FROM public.py_frame_object WHERE ob_base = frame_id;
    IF stack_size != 1 THEN
        RAISE EXCEPTION 'FAIL: Stack size after LOAD_GLOBAL is %, expected 1', stack_size;
    END IF;
    SELECT f_valuestack[1] INTO loaded_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF loaded_obj_id != ID_LEN_FUNCTION THEN
        RAISE EXCEPTION 'FAIL: Loaded value is %, expected ID_LEN_FUNCTION', loaded_obj_id;
    END IF;
    RAISE NOTICE '  ✓ LOAD_GLOBAL correctly loads from builtins';
    pass_count := pass_count + 1;
    
    -- Test 4: LOAD_GLOBAL ignores locals (globals takes precedence over locals)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: LOAD_GLOBAL ignores locals (returns global value)...';
    test_count := test_count + 1;
    DECLARE
        locals_value_id UUID;
        globals_value_id UUID;
    BEGIN
        locals_value_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (locals_value_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (locals_value_id, 100);
        
        globals_value_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (globals_value_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (globals_value_id, 200);
        
        UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[] WHERE ob_base = frame_id;
        DELETE FROM public.py_dict_entry WHERE dict_id = locals_dict_id AND me_key = name0_str_id;
        DELETE FROM public.py_dict_entry WHERE dict_id = globals_dict_id AND me_key = name0_str_id;
        
        INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
        VALUES (locals_dict_id, name0_str_id, locals_value_id, public.py_object_hash(name0_str_id));
        INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
        VALUES (globals_dict_id, name0_str_id, globals_value_id, public.py_object_hash(name0_str_id));
        
        UPDATE public.py_tuple_object SET ob_item = ARRAY[name0_str_id] WHERE ob_base = co_names_id;
        
        PERFORM public.py_opcode_LOAD_GLOBAL(frame_id, 0);
        
        SELECT f_valuestack[1] INTO loaded_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
        IF loaded_obj_id != globals_value_id THEN
            RAISE EXCEPTION 'FAIL: LOAD_GLOBAL should return global value (%), got %', globals_value_id, loaded_obj_id;
        END IF;
        IF loaded_obj_id = locals_value_id THEN
            RAISE EXCEPTION 'FAIL: LOAD_GLOBAL must not use locals';
        END IF;
    END;
    RAISE NOTICE '  ✓ LOAD_GLOBAL correctly ignores locals (globals → builtins only)';
    pass_count := pass_count + 1;
    
    -- Test 5: LOAD_GLOBAL raises NameError when name not found
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: LOAD_GLOBAL raises NameError when name not found...';
    test_count := test_count + 1;
    DECLARE
        unknown_str_id UUID;
    BEGIN
        unknown_str_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (unknown_str_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (unknown_str_id, 'nonexistent_var_xyz');
        
        UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[] WHERE ob_base = frame_id;
        UPDATE public.py_tuple_object SET ob_item = ARRAY[unknown_str_id] WHERE ob_base = co_names_id;
        
        PERFORM public.py_err_clear();
        PERFORM public.py_opcode_LOAD_GLOBAL(frame_id, 0);
        IF NOT public.py_err_occurred() THEN
            RAISE EXCEPTION 'FAIL: LOAD_GLOBAL did not raise NameError for undefined name';
        END IF;
    END;
    SELECT g.exc_type_id INTO exc_type_id FROM public.py_err_get_raised() g LIMIT 1;
    IF exc_type_id IS DISTINCT FROM '00000000-0000-4000-a000-000000000024' THEN
        RAISE EXCEPTION 'FAIL: LOAD_GLOBAL should set NameError, got exc_type_id %', exc_type_id;
    END IF;
    PERFORM public.py_err_clear();
    RAISE NOTICE '  ✓ LOAD_GLOBAL correctly raises NameError when name not found';
    pass_count := pass_count + 1;
    
    -- Test 6: LOAD_GLOBAL index validation
    RAISE NOTICE '';
    RAISE NOTICE 'Test 6: LOAD_GLOBAL index validation...';
    test_count := test_count + 1;
    BEGIN
        PERFORM public.py_opcode_LOAD_GLOBAL(frame_id, -1);
        RAISE EXCEPTION 'FAIL: LOAD_GLOBAL did not raise for negative index';
    EXCEPTION WHEN OTHERS THEN
        error_message := SQLERRM;
        IF error_message NOT LIKE 'LOAD_GLOBAL: name_index must be non-negative%' THEN
            RAISE EXCEPTION 'FAIL: LOAD_GLOBAL wrong exception for negative index: %', error_message;
        END IF;
    END;
    BEGIN
        PERFORM public.py_opcode_LOAD_GLOBAL(frame_id, 999);
        RAISE EXCEPTION 'FAIL: LOAD_GLOBAL did not raise for out of range index';
    EXCEPTION WHEN OTHERS THEN
        error_message := SQLERRM;
        IF error_message NOT LIKE 'LOAD_GLOBAL: Index % out of range for co_names tuple%' THEN
            RAISE EXCEPTION 'FAIL: LOAD_GLOBAL wrong exception for out of range: %', error_message;
        END IF;
    END;
    RAISE NOTICE '  ✓ LOAD_GLOBAL correctly validates index';
    pass_count := pass_count + 1;
    
    -- Summary
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total tests: %', test_count;
    RAISE NOTICE 'Passed: %', pass_count;
    RAISE NOTICE 'Failed: %', fail_count;
    RAISE NOTICE '';
    IF fail_count > 0 THEN
        RAISE EXCEPTION 'Test suite failed: % out of % tests failed', fail_count, test_count;
    END IF;
    RAISE NOTICE 'All tests passed! ✓';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Test failed with error:';
        RAISE NOTICE '%', SQLERRM;
        RAISE NOTICE '========================================';
        RAISE;
END $$;
