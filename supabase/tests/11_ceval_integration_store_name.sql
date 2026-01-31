-- ============================================================================
-- Test: VM STORE_NAME Integration Test
-- 
-- Purpose:
--   Tests STORE_NAME opcode in realistic integration scenarios. This verifies:
--   - LOAD_CONST + STORE_NAME: 변수 할당 패턴
--   - 여러 변수 할당
--   - 변수 재할당
--   - STORE_NAME과 다른 opcode들의 조합
--   - Frame isolation (여러 frame에서 독립적인 locals)
--
--   All tests follow CPython's exact behavior and execution model.
--
-- Usage:
--   Run this file after migrations to verify STORE_NAME integration.
--   If any assertion fails, an exception will be raised with details.
-- ============================================================================

DO $$
DECLARE
    -- Builtin Type IDs (from bootstrap)
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    
    -- Test counters
    test_count INTEGER := 0;
    pass_count INTEGER := 0;
    fail_count INTEGER := 0;
    
    -- Frame and code objects
    frame_id UUID;
    code_obj_id UUID;
    co_code_id UUID;
    co_names_id UUID;
    co_consts_id UUID;
    
    -- Test constants
    const0_id UUID;
    const1_id UUID;
    const2_id UUID;
    
    -- Test name strings
    name0_str_id UUID;
    name1_str_id UUID;
    name2_str_id UUID;
    
    -- Test variables
    stored_value_id UUID;
    entry_count INTEGER;
    stack_size INTEGER;
    
    -- Helper variables
    empty_tuple_id UUID;
    empty_str_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;
    builtins_dict_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM STORE_NAME Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Setup: Create test objects and frame infrastructure
    -- ========================================================================
    RAISE NOTICE 'Setting up test environment...';
    
    -- Create test constants
    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 10);
    
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 20);
    
    const2_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const2_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const2_id, 30);
    
    -- Create name strings
    name0_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name0_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name0_str_id, 'x');
    
    name1_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name1_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name1_str_id, 'y');
    
    name2_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (name2_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (name2_str_id, 'z');
    
    -- Create empty tuple for various tuple fields
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    
    -- Create empty string
    empty_str_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_str_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (empty_str_id, '');
    
    -- Create namespace dicts
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);
    
    builtins_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (builtins_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (builtins_dict_id);
    
    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';
    
    -- ========================================================================
    -- Test 1: LOAD_CONST + STORE_NAME (변수 할당 패턴)
    -- ========================================================================
    RAISE NOTICE 'Test 1: LOAD_CONST + STORE_NAME (변수 할당 패턴)...';
    test_count := test_count + 1;
    
    -- Create names tuple
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id]);
    
    -- Create constants tuple
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    
    -- Create bytecode: LOAD_CONST(0) STORE_NAME(0)
    -- Bytecode: [100, 0, 90, 0]
    -- LOAD_CONST = 100, STORE_NAME = 90
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005a00'::bytea);
    
    -- Create code object
    code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars
    ) VALUES (
        code_obj_id, co_code_id, co_consts_id, co_names_id, empty_str_id, empty_str_id,
        0, empty_tuple_id, empty_tuple_id, empty_tuple_id
    );
    
    -- Create new locals dict for this test
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    -- Create frame
    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (
        ob_base, f_code, f_globals, f_locals, f_builtins
    ) VALUES (
        frame_id, code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id
    );
    
    -- Execute frame
    PERFORM public.py_eval_frame(frame_id);
    
    -- Verify value is stored in locals dict
    SELECT me_value INTO stored_value_id
    FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id
    AND me_key = name0_str_id;
    
    IF stored_value_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Stored value is %, expected % (const0_id)', stored_value_id, const0_id;
    END IF;
    -- Verify via dict API (hash-based lookup)
    stored_value_id := public.py_dict_get_item(locals_dict_id, name0_str_id);
    IF stored_value_id IS NULL OR stored_value_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: py_dict_get_item(locals,''x'') expected const0_id, got %', stored_value_id;
    END IF;
    
    -- Verify stack is empty
    SELECT array_length(f_valuestack, 1) INTO stack_size
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_size IS NOT NULL AND stack_size != 0 THEN
        RAISE EXCEPTION 'FAIL: Stack size is %, expected 0 (empty)', stack_size;
    END IF;
    
    RAISE NOTICE '  ✓ LOAD_CONST + STORE_NAME works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 2: 여러 변수 할당
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Multiple variable assignments...';
    test_count := test_count + 1;
    
    -- Create names tuple with 3 names
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id, name1_str_id, name2_str_id]);
    
    -- Create constants tuple with 3 constants
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, const2_id]);
    
    -- Create bytecode: LOAD_CONST(0) STORE_NAME(0) LOAD_CONST(1) STORE_NAME(1) LOAD_CONST(2) STORE_NAME(2)
    -- Bytecode: [100, 0, 90, 0, 100, 1, 90, 1, 100, 2, 90, 2]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005a0064015a0164025a02'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    
    -- Create new locals dict
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    -- Update frame
    UPDATE public.py_frame_object SET f_locals = locals_dict_id WHERE ob_base = frame_id;
    
    -- Execute frame
    PERFORM public.py_eval_frame(frame_id);
    
    -- Verify all three variables are stored
    SELECT me_value INTO stored_value_id
    FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id
    AND me_key = name0_str_id;
    
    IF stored_value_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Variable ''x'' value is %, expected %', stored_value_id, const0_id;
    END IF;
    
    SELECT me_value INTO stored_value_id
    FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id
    AND me_key = name1_str_id;
    
    IF stored_value_id != const1_id THEN
        RAISE EXCEPTION 'FAIL: Variable ''y'' value is %, expected %', stored_value_id, const1_id;
    END IF;
    
    SELECT me_value INTO stored_value_id
    FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id
    AND me_key = name2_str_id;
    
    IF stored_value_id != const2_id THEN
        RAISE EXCEPTION 'FAIL: Variable ''z'' value is %, expected %', stored_value_id, const2_id;
    END IF;
    
    -- Verify exactly 3 entries
    SELECT COUNT(*) INTO entry_count
    FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id;
    
    IF entry_count != 3 THEN
        RAISE EXCEPTION 'FAIL: Found % entries in locals dict, expected 3', entry_count;
    END IF;
    -- Verify via dict API
    IF public.py_dict_get_item(locals_dict_id, name0_str_id) != const0_id
       OR public.py_dict_get_item(locals_dict_id, name1_str_id) != const1_id
       OR public.py_dict_get_item(locals_dict_id, name2_str_id) != const2_id THEN
        RAISE EXCEPTION 'FAIL: py_dict_get_item(locals, x/y/z) should return stored values';
    END IF;
    
    RAISE NOTICE '  ✓ Multiple variable assignments work correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 3: 변수 재할당
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Variable reassignment...';
    test_count := test_count + 1;
    
    -- Create new constant for reassignment
    DECLARE
        new_const_id UUID;
        new_co_consts_id UUID;
        new_co_code_id UUID;
    BEGIN
        new_const_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (new_const_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (new_const_id, 999);
        
        -- Create constants tuple with new constant
        new_co_consts_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (new_co_consts_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (new_co_consts_id, ARRAY[new_const_id]);
        
        -- Create bytecode: LOAD_CONST(0) STORE_NAME(0) - reassign 'x'
        new_co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (new_co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (new_co_code_id, E'\\x64005a00'::bytea);
        
        -- Update code object
        UPDATE public.py_code_object SET co_code = new_co_code_id, co_consts = new_co_consts_id WHERE ob_base = code_obj_id;
        
        -- Execute frame (reassign variable 'x')
        PERFORM public.py_eval_frame(frame_id);
        
        -- Verify value is updated
        SELECT me_value INTO stored_value_id
        FROM public.py_dict_entry
        WHERE dict_id = locals_dict_id
        AND me_key = name0_str_id;
        
        IF stored_value_id != new_const_id THEN
            RAISE EXCEPTION 'FAIL: Reassigned value is %, expected % (new_const_id)', stored_value_id, new_const_id;
        END IF;
        stored_value_id := public.py_dict_get_item(locals_dict_id, name0_str_id);
        IF stored_value_id IS NULL OR stored_value_id != new_const_id THEN
            RAISE EXCEPTION 'FAIL: py_dict_get_item(locals,''x'') after reassign expected new_const_id, got %', stored_value_id;
        END IF;
        
        -- Verify still only 3 entries (no duplication)
        SELECT COUNT(*) INTO entry_count
        FROM public.py_dict_entry
        WHERE dict_id = locals_dict_id;
        
        IF entry_count != 3 THEN
            RAISE EXCEPTION 'FAIL: Found % entries after reassignment, expected 3 (no duplication)', entry_count;
        END IF;
    END;
    
    RAISE NOTICE '  ✓ Variable reassignment works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 4: Frame isolation (여러 frame에서 독립적인 locals)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Frame isolation (independent locals)...';
    test_count := test_count + 1;
    
    -- Create two frames with different locals dicts
    DECLARE
        first_frame_id UUID;
        first_locals_dict_id UUID;
        first_code_obj_id UUID;
        first_co_code_id UUID;
        first_co_consts_id UUID;
        first_co_names_id UUID;
        second_frame_id UUID;
        second_locals_dict_id UUID;
        second_code_obj_id UUID;
        second_co_code_id UUID;
        second_co_consts_id UUID;
        second_co_names_id UUID;
        first_stored_value UUID;
        second_stored_value UUID;
    BEGIN
        -- First frame setup
        first_co_names_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (first_co_names_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (first_co_names_id, ARRAY[name0_str_id]);
        
        first_co_consts_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (first_co_consts_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (first_co_consts_id, ARRAY[const0_id]);
        
        first_co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (first_co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (first_co_code_id, E'\\x64005a00'::bytea);
        
        first_code_obj_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (first_code_obj_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_code_object (
            ob_base, co_code, co_consts, co_names, co_filename, co_name,
            co_argcount, co_varnames, co_cellvars, co_freevars
        ) VALUES (
            first_code_obj_id, first_co_code_id, first_co_consts_id, first_co_names_id, empty_str_id, empty_str_id,
            0, empty_tuple_id, empty_tuple_id, empty_tuple_id
        );
        
        first_locals_dict_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (first_locals_dict_id, ID_DICT_TYPE);
        INSERT INTO public.py_dict_object (ob_base) VALUES (first_locals_dict_id);
        
        first_frame_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (first_frame_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_frame_object (
            ob_base, f_code, f_globals, f_locals, f_builtins
        ) VALUES (
            first_frame_id, first_code_obj_id, globals_dict_id, first_locals_dict_id, builtins_dict_id
        );
        
        -- Execute first frame
        PERFORM public.py_eval_frame(first_frame_id);
        
        -- Second frame setup (different constant, same name)
        second_co_names_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (second_co_names_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (second_co_names_id, ARRAY[name0_str_id]);
        
        second_co_consts_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (second_co_consts_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (second_co_consts_id, ARRAY[const1_id]);
        
        second_co_code_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (second_co_code_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (second_co_code_id, E'\\x64005a00'::bytea);
        
        second_code_obj_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (second_code_obj_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_code_object (
            ob_base, co_code, co_consts, co_names, co_filename, co_name,
            co_argcount, co_varnames, co_cellvars, co_freevars
        ) VALUES (
            second_code_obj_id, second_co_code_id, second_co_consts_id, second_co_names_id, empty_str_id, empty_str_id,
            0, empty_tuple_id, empty_tuple_id, empty_tuple_id
        );
        
        second_locals_dict_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (second_locals_dict_id, ID_DICT_TYPE);
        INSERT INTO public.py_dict_object (ob_base) VALUES (second_locals_dict_id);
        
        second_frame_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (second_frame_id, ID_OBJECT_TYPE);
        INSERT INTO public.py_frame_object (
            ob_base, f_code, f_globals, f_locals, f_builtins
        ) VALUES (
            second_frame_id, second_code_obj_id, globals_dict_id, second_locals_dict_id, builtins_dict_id
        );
        
        -- Execute second frame
        PERFORM public.py_eval_frame(second_frame_id);
        
        -- Verify frame isolation: each frame has its own value
        SELECT me_value INTO first_stored_value
        FROM public.py_dict_entry
        WHERE dict_id = first_locals_dict_id
        AND me_key = name0_str_id;
        
        IF first_stored_value != const0_id THEN
            RAISE EXCEPTION 'FAIL: First frame variable value is %, expected %', first_stored_value, const0_id;
        END IF;
        
        SELECT me_value INTO second_stored_value
        FROM public.py_dict_entry
        WHERE dict_id = second_locals_dict_id
        AND me_key = name0_str_id;
        
        IF second_stored_value != const1_id THEN
            RAISE EXCEPTION 'FAIL: Second frame variable value is %, expected %', second_stored_value, const1_id;
        END IF;
        IF public.py_dict_get_item(first_locals_dict_id, name0_str_id) != const0_id
           OR public.py_dict_get_item(second_locals_dict_id, name0_str_id) != const1_id THEN
            RAISE EXCEPTION 'FAIL: py_dict_get_item per-frame locals should return frame-specific values';
        END IF;
        
        -- Verify frames are independent (different values)
        IF first_stored_value = second_stored_value THEN
            RAISE EXCEPTION 'FAIL: Frames share the same value (no isolation)';
        END IF;
    END;
    
    RAISE NOTICE '  ✓ Frame isolation works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Test 5: 연속된 STORE_NAME (여러 변수에 같은 값 할당)
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: Consecutive STORE_NAME (assign same value to multiple variables)...';
    test_count := test_count + 1;
    
    -- Create names tuple with 2 names
    co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_names_id, ARRAY[name0_str_id, name1_str_id]);
    
    -- Create constants tuple with 1 constant
    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id]);
    
    -- Create bytecode: LOAD_CONST(0) STORE_NAME(0) LOAD_CONST(0) STORE_NAME(1)
    -- Bytecode: [100, 0, 90, 0, 100, 0, 90, 1]
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64005a0064005a01'::bytea);
    
    -- Update code object
    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id, co_names = co_names_id WHERE ob_base = code_obj_id;
    
    -- Create new locals dict
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    
    -- Update frame
    UPDATE public.py_frame_object SET f_locals = locals_dict_id WHERE ob_base = frame_id;
    
    -- Execute frame
    PERFORM public.py_eval_frame(frame_id);
    
    -- Verify both variables have the same value
    SELECT me_value INTO stored_value_id
    FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id
    AND me_key = name0_str_id;
    
    IF stored_value_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Variable ''x'' value is %, expected %', stored_value_id, const0_id;
    END IF;
    
    SELECT me_value INTO stored_value_id
    FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id
    AND me_key = name1_str_id;
    
    IF stored_value_id != const0_id THEN
        RAISE EXCEPTION 'FAIL: Variable ''y'' value is %, expected %', stored_value_id, const0_id;
    END IF;
    IF public.py_dict_get_item(locals_dict_id, name0_str_id) != const0_id
       OR public.py_dict_get_item(locals_dict_id, name1_str_id) != const0_id THEN
        RAISE EXCEPTION 'FAIL: py_dict_get_item(locals, x/y) should return const0_id';
    END IF;
    
    -- Verify exactly 2 entries
    SELECT COUNT(*) INTO entry_count
    FROM public.py_dict_entry
    WHERE dict_id = locals_dict_id;
    
    IF entry_count != 2 THEN
        RAISE EXCEPTION 'FAIL: Found % entries in locals dict, expected 2', entry_count;
    END IF;
    
    RAISE NOTICE '  ✓ Consecutive STORE_NAME works correctly';
    pass_count := pass_count + 1;
    
    -- ========================================================================
    -- Summary
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total tests: %', test_count;
    RAISE NOTICE 'Passed: %', pass_count;
    RAISE NOTICE 'Failed: %', fail_count;
    RAISE NOTICE '';
    
    IF fail_count > 0 THEN
        RAISE EXCEPTION 'Some tests failed. See details above.';
    END IF;
    
    RAISE NOTICE '✅ All STORE_NAME integration tests passed!';
    
END $$;
