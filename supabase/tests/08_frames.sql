-- =====================================================
-- Test 08: Frame Objects
-- Description: Test frame creation, introspection, and sys functions
-- =====================================================

DO $$
DECLARE
    v_code_id uuid;
    v_locals_id uuid;
    v_frame_id uuid;
    v_frame_info jsonb;
    v_back_frame uuid;
    v_res uuid;
    v_val bigint;
    
    ID_OBJ_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_DICT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
BEGIN
    RAISE NOTICE 'Testing Frame Objects...';

    -------------------------------------------------------
    -- 1. Test Frame Creation
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Frame Creation ===';
    
    -- Create simple code
    v_code_id := public.vm_assemble('LOAD_CONST 42
RETURN_VALUE', 'test_func');
    
    -- Create locals
    v_locals_id := public.vm_create_str('test_locals'); -- Just a dummy object for testing
    
    -- Create frame
    v_frame_id := public.vm_create_frame(
        v_code_id,
        v_locals_id,
        NULL  -- globals
    );
    
    PERFORM public.test_assert(v_frame_id IS NOT NULL, 'Frame should be created');
    
    v_frame_info := public.vm_get_frame_info(v_frame_id);
    PERFORM public.test_assert_eq_str(v_frame_info->>'code_name', 'test_func', 'Frame should point to correct code');
    PERFORM public.test_assert(v_frame_info->>'f_back' IS NULL, 'Root frame back should be NULL');

    -------------------------------------------------------
    -- 2. Test Execution with Frame Update
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Frame Execution & Context ===';
    
    -- Set as current frame
    PERFORM public.vm_set_current_frame(v_frame_id);
    PERFORM public.test_assert(public.vm_get_current_frame() = v_frame_id, 'Execution context should store current frame');
    
    -- Run frame (this will also update lasti)
    v_res := public.vm_run_frame(v_code_id, v_locals_id, NULL, v_frame_id);
    v_val := public.vm_get_int_value(v_res);
    PERFORM public.test_assert_eq_int(v_val, 42, 'Execution result should be correct');
    
    -- Check if lasti was updated
    v_frame_info := public.vm_get_frame_info(v_frame_id);
    PERFORM public.test_assert((v_frame_info->>'f_lasti')::integer > 0, 'Frame lasti should be updated after execution');

    -------------------------------------------------------
    -- 3. Test sys_getframe
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing sys_getframe ===';
    
    PERFORM public.test_assert(public.sys_getframe(0) = v_frame_id, 'sys_getframe(0) should return current frame');
    
    -- Create a child frame
    v_back_frame := v_frame_id;
    v_frame_id := public.vm_create_frame(v_code_id, v_locals_id, NULL, NULL, v_back_frame);
    PERFORM public.vm_set_current_frame(v_frame_id);
    
    PERFORM public.test_assert(public.sys_getframe(0) = v_frame_id, 'sys_getframe(0) should return new current frame');
    PERFORM public.test_assert(public.sys_getframe(1) = v_back_frame, 'sys_getframe(1) should return caller frame');

    -------------------------------------------------------
    -- 4. Test Traceback Formatting
    -------------------------------------------------------
    RAISE NOTICE E'\n=== Testing Traceback ===';
    DECLARE
        v_traceback text;
    BEGIN
        v_traceback := public.vm_format_traceback(v_frame_id);
        RAISE NOTICE 'Formatted Traceback:%', v_traceback;
        PERFORM public.test_assert(v_traceback LIKE '%Traceback%', 'Traceback should contain header');
        PERFORM public.test_assert(v_traceback LIKE '%test_func%', 'Traceback should contain function names');
    END;

    RAISE NOTICE E'\n✅ PASS: 08_frames';
END $$;
