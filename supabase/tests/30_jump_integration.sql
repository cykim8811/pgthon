-- ============================================================================
-- Test: Jump Bytecode Integration
--
-- Purpose:
--   Phase 2(240400) 구현 검증. py_eval_frame으로 JUMP_FORWARD(110),
--   POP_JUMP_FORWARD_IF_FALSE(114) 동작 확인.
--   - JUMP_FORWARD: LOAD_CONST 0, JUMP_FORWARD 2, (건너뜀) LOAD_CONST 1, RETURN → const0 반환
--   - POP_JUMP_FORWARD_IF_FALSE: 1<2(True) → 점프 안 함 → 1 반환; 1>2(False) → 점프 → 99 반환
--
-- Bytecode (Python 3.11 jrel: operand = words to skip, 1 word = 2 bytes)
--   JUMP_FORWARD 2: next_i = i + 2 + 2*2 = i+6. So skip 4 bytes = next 2-byte instruction + 2 bytes.
--   LOAD_CONST 0, JUMP_FORWARD 2, LOAD_CONST 1, RETURN_VALUE
--   = 100,0, 110,2, 100,1, 83,0  →  \x64006E0264015300
--
-- Usage:
--   Run after migration 240400. If any assertion fails, exception is raised.
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_STR_TYPE    uuid := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';

    test_count int := 0;
    pass_count int := 0;

    frame_id uuid;
    code_obj_id uuid;
    co_code_id uuid;
    co_names_id uuid;
    co_consts_id uuid;
    empty_tuple_id uuid;
    empty_str_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;

    const0_id uuid;
    const1_id uuid;
    result_id uuid;
    result_num numeric;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Jump Bytecode Integration Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup (same pattern as 28_compare_op_integration)
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
    INSERT INTO public.py_object (id, ob_type) VALUES (code_obj_id, ID_CODE_TYPE);
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

    RAISE NOTICE '  ✓ Test environment setup complete';
    RAISE NOTICE '';

    -- Test 1: JUMP_FORWARD — LOAD_CONST 0 (1), JUMP_FORWARD 1 (skip 1 word = 2 bytes = LOAD_CONST 1), RETURN_VALUE → 1
    RAISE NOTICE 'Test 1: JUMP_FORWARD skips LOAD_CONST 1, returns const0 (1)...';
    test_count := test_count + 1;

    const0_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);

    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 99);

    co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- 100,0 LOAD_CONST 0; 110,1 JUMP_FORWARD 1 word (skip 2 bytes = LOAD_CONST 1); 100,1 LOAD_CONST 1; 83,0 RETURN_VALUE
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x64006E0164015300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: JUMP_FORWARD bytecode returned NULL';
    END IF;
    IF result_id IS DISTINCT FROM const0_id THEN
        RAISE EXCEPTION 'FAIL: JUMP_FORWARD should return const0 (1), got %', result_id;
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 1 THEN
        RAISE EXCEPTION 'FAIL: JUMP_FORWARD result value %, expected 1', result_num;
    END IF;
    RAISE NOTICE '  ✓ JUMP_FORWARD returns 1 (skipped 99)';
    pass_count := pass_count + 1;

    -- Test 2: POP_JUMP_FORWARD_IF_FALSE — 1<2 → True → no jump → return 1; 1>2 → False → jump → return 99
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: POP_JUMP_FORWARD_IF_FALSE when True (1<2) -> no jump, return 1...';
    test_count := test_count + 1;

    -- Bytecode: LOAD_CONST 0 (1), LOAD_CONST 1 (2), COMPARE_OP 0 (<), POP_JUMP_FORWARD_IF_FALSE 2, LOAD_CONST 0 (1), RETURN_VALUE
    -- If 1<2 is True, we don't jump, so we fall through to next instruction which is LOAD_CONST 0... but we need to lay out so that "no jump" runs LOAD_CONST 0 (1) and RETURN; "jump" skips to LOAD_CONST 1 (99) and RETURN.
    -- Layout: [0-1] LOAD_CONST 0 (1), [2-3] LOAD_CONST 1 (2), [4-5] COMPARE_OP 0, [6-7] POP_JUMP_FORWARD_IF_FALSE 2 (skip 4 bytes -> next at 10), [8-9] LOAD_CONST 0 (1) [fall-through], [10-11] RETURN_VALUE.
    -- So when we don't jump: after POP_JUMP we're at 8, so we run LOAD_CONST 0 (push 1), then 10 RETURN. When we jump: next_i = 6+2+4 = 12. So we go to 12. So we need: at 12 we have RETURN_VALUE? So bytecode length at least 14. Layout: 0 LOAD_CONST 0, 2 LOAD_CONST 1, 4 COMPARE_OP 0, 6 POP_JUMP_FORWARD_IF_FALSE 2 (jump to 6+2+4=12), 8 LOAD_CONST 0, 10 LOAD_CONST 1 (99), 12 RETURN_VALUE. So when no jump we do 8 LOAD_CONST 0 (1), 10 ... we need 10 to be RETURN_VALUE to return 1. So: 8 LOAD_CONST 0, 10 RETURN_VALUE. When jump we go to 12... so 12 RETURN_VALUE. So we need two RETURN_VALUE? No - when we jump we want to skip "LOAD_CONST 0, RETURN_VALUE" and land on "LOAD_CONST 1 (99), RETURN_VALUE". So: [0-1] LOAD_CONST 0 (1), [2-3] LOAD_CONST 1 (2), [4-5] COMPARE_OP 0, [6-7] POP_JUMP_FORWARD_IF_FALSE 2 -> next 6+2+4=12. [8-9] LOAD_CONST 0 (1), [10-11] RETURN_VALUE. [12-13] LOAD_CONST 1 (99), [14-15] RETURN_VALUE. So when True we don't jump: i=8 LOAD_CONST 0, i=10 RETURN_VALUE -> return 1. When False we jump to 12: LOAD_CONST 1 (99), RETURN_VALUE -> return 99. So consts: [0]=1, [1]=2, [2]=99. So we need 3 constants. co_consts = [const_1, const_2, const_99]. Bytecode: 64 00 (LOAD_CONST 0), 64 01 (LOAD_CONST 1), 6B 00 (COMPARE_OP 0), 72 02 (114,2 POP_JUMP_FORWARD_IF_FALSE 2), 64 00 (LOAD_CONST 0), 53 00 (RETURN_VALUE), 64 02 (LOAD_CONST 2), 53 00 (RETURN_VALUE). So hex: 640064016B0072026400530064025300. Let me check: 72 is 114 in decimal. Yes. So E'\\x640064016B0072026400530064025300'.
    co_consts_id := gen_random_uuid();
    const0_id := gen_random_uuid();
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 2);
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, 99);

    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, result_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016B0072026400530064025300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: POP_JUMP (1<2 True) returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 1 THEN
        RAISE EXCEPTION 'FAIL: 1<2 True should return 1, got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ POP_JUMP_FORWARD_IF_FALSE (1<2 True) returns 1';
    pass_count := pass_count + 1;

    -- Test 3: POP_JUMP_FORWARD_IF_FALSE when False (1>2) -> jump, return 99
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: POP_JUMP_FORWARD_IF_FALSE when False (1>2) -> jump, return 99...';
    test_count := test_count + 1;

    -- Same co_consts: [1, 2, 99]. Bytecode: LOAD_CONST 0 (1), LOAD_CONST 1 (2), COMPARE_OP 4 (GT), POP_JUMP_FORWARD_IF_FALSE 2, LOAD_CONST 0, RETURN_VALUE, LOAD_CONST 2 (99), RETURN_VALUE.
    -- 64 00 64 01 6B 04 72 02 64 00 53 00 64 02 53 00
    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016B0472026400530064025300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: POP_JUMP (1>2 False) returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 99 THEN
        RAISE EXCEPTION 'FAIL: 1>2 False should jump and return 99, got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ POP_JUMP_FORWARD_IF_FALSE (1>2 False) returns 99';
    pass_count := pass_count + 1;

    -- Test 4: POP_JUMP_FORWARD_IF_TRUE when True (1<2) -> jump, return 99
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: POP_JUMP_FORWARD_IF_TRUE when True (1<2) -> jump, return 99...';
    test_count := test_count + 1;

    co_consts_id := gen_random_uuid();
    const0_id := gen_random_uuid();
    const1_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const0_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const0_id, 1);
    INSERT INTO public.py_object (id, ob_type) VALUES (const1_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const1_id, 2);
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, 99);

    INSERT INTO public.py_object (id, ob_type) VALUES (co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_consts_id, ARRAY[const0_id, const1_id, result_id]);

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    -- LOAD_CONST 0,1 COMPARE_OP 0 (<) POP_JUMP_FORWARD_IF_TRUE 2 LOAD_CONST 0 RETURN_VALUE LOAD_CONST 2 RETURN_VALUE. 115=0x73.
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016B0073026400530064025300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id, co_consts = co_consts_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: POP_JUMP_FORWARD_IF_TRUE (1<2 True) returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 99 THEN
        RAISE EXCEPTION 'FAIL: 1<2 True should jump and return 99, got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ POP_JUMP_FORWARD_IF_TRUE (1<2 True) returns 99';
    pass_count := pass_count + 1;

    -- Test 5: POP_JUMP_FORWARD_IF_TRUE when False (1>2) -> no jump, return 1
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: POP_JUMP_FORWARD_IF_TRUE when False (1>2) -> no jump, return 1...';
    test_count := test_count + 1;

    co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (co_code_id, E'\\x640064016B0473026400530064025300'::bytea);

    UPDATE public.py_code_object SET co_code = co_code_id WHERE ob_base = code_obj_id;
    UPDATE public.py_frame_object SET f_valuestack = array[]::uuid[], f_lasti = 0 WHERE ob_base = frame_id;

    result_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF result_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: POP_JUMP_FORWARD_IF_TRUE (1>2 False) returned NULL';
    END IF;
    SELECT long_value INTO result_num FROM public.py_long_object WHERE ob_base = result_id;
    IF result_num IS NULL OR result_num <> 1 THEN
        RAISE EXCEPTION 'FAIL: 1>2 False should not jump and return 1, got %', result_num;
    END IF;
    RAISE NOTICE '  ✓ POP_JUMP_FORWARD_IF_TRUE (1>2 False) returns 1';
    pass_count := pass_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total: %  Passed: %', test_count, pass_count;
    RAISE NOTICE '========================================';
    IF pass_count <> test_count THEN
        RAISE EXCEPTION 'FAIL: % test(s) failed', test_count - pass_count;
    END IF;
    RAISE NOTICE '✓ All Jump bytecode integration tests passed!';
END $$;
