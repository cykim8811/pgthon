-- ============================================================================
-- Test: VM Closure Opcodes (CPython 3.11)
--   MAKE_CELL(135), LOAD_CLOSURE(136), LOAD_DEREF(137),
--   STORE_DEREF(138), DELETE_DEREF(139), COPY_FREE_VARS(149)
--
-- Purpose:
--   Test the closure/cell variable mechanism. Outer functions create cells
--   for variables captured by inner functions. Inner functions access those
--   cells via LOAD_DEREF/STORE_DEREF.
--
-- Tests:
--   1. Function existence checks
--   2. Simple closure: outer() { x=10; def inner(): return x; return inner() } → 10
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_INT_TYPE    uuid := '00000000-0000-4000-a000-000000000004';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_BYTES_TYPE  uuid := '00000000-0000-4000-a000-000000000012';
    ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';
    ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_BUILTINS_MODULE uuid := '00000000-0000-4000-b000-000000000002';

    test_count int := 0;
    pass_count int := 0;

    -- Shared helpers
    empty_tuple_id uuid;
    empty_str_id uuid;

    -- Inner function code objects
    inner_co_code_id uuid;
    inner_co_consts_id uuid;
    inner_co_names_id uuid;
    inner_co_varnames_id uuid;
    inner_co_cellvars_id uuid;
    inner_co_freevars_id uuid;
    inner_code_obj_id uuid;

    -- Outer function code objects
    outer_co_code_id uuid;
    outer_co_consts_id uuid;
    outer_co_names_id uuid;
    outer_co_varnames_id uuid;
    outer_co_cellvars_id uuid;
    outer_co_freevars_id uuid;
    outer_code_obj_id uuid;

    -- Constants
    const_10_id uuid;
    qualname_id uuid;

    -- Variable name strings
    var_inner_id uuid;
    var_x_id uuid;

    -- Frame setup
    frame_id uuid;
    locals_dict_id uuid;
    globals_dict_id uuid;
    builtins_dict_id uuid;

    -- Results
    res_id uuid;
    res_val numeric;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VM Closure Opcodes Test (CPython 3.11)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup shared objects
    empty_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (empty_tuple_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (empty_tuple_id, array[]::uuid[]);
    empty_str_id := public.py_str_from_text('');

    -- Create constants
    const_10_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (const_10_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (const_10_id, 10);

    qualname_id := public.py_str_from_text('outer.<locals>.inner');

    -- Variable name strings
    var_inner_id := public.py_str_from_text('inner');
    var_x_id := public.py_str_from_text('x');

    RAISE NOTICE '  Setup complete';
    RAISE NOTICE '';

    -- ================================================================
    -- Test 1: Opcode functions exist
    -- ================================================================
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_make_cell') THEN
        RAISE EXCEPTION 'FAIL: py_opcode_MAKE_CELL does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_load_closure') THEN
        RAISE EXCEPTION 'FAIL: py_opcode_LOAD_CLOSURE does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_load_deref') THEN
        RAISE EXCEPTION 'FAIL: py_opcode_LOAD_DEREF does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_store_deref') THEN
        RAISE EXCEPTION 'FAIL: py_opcode_STORE_DEREF does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_delete_deref') THEN
        RAISE EXCEPTION 'FAIL: py_opcode_DELETE_DEREF does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_opcode_copy_free_vars') THEN
        RAISE EXCEPTION 'FAIL: py_opcode_COPY_FREE_VARS does not exist';
    END IF;
    RAISE NOTICE '  Test 1 PASS: All closure opcode functions exist';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 2: Simple closure — outer() { x=10; def inner(): return x; return inner() } → 10
    --
    -- inner bytecode: COPY_FREE_VARS 1 | RESUME 0 | LOAD_DEREF 0 | RETURN_VALUE
    -- inner: co_consts=(), co_varnames=(), co_cellvars=(), co_freevars=('x',), co_nlocals=0
    --
    -- outer bytecode: MAKE_CELL 0 | RESUME 0 | LOAD_CONST 0 (10) | STORE_DEREF 0 |
    --   LOAD_CLOSURE 0 | BUILD_TUPLE 1 | LOAD_CONST 1 (inner_code) | LOAD_CONST 2 (qualname) |
    --   MAKE_FUNCTION 8 | STORE_FAST 0 (inner) |
    --   PUSH_NULL | LOAD_FAST 0 (inner) | PRECALL 0 | CALL 0 | RETURN_VALUE
    -- outer: co_consts=(10, inner_code, qualname), co_varnames=('inner',),
    --        co_cellvars=('x',), co_nlocals=1
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- Build inner code object
    inner_co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (inner_co_consts_id, array[]::uuid[]);

    inner_co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (inner_co_names_id, array[]::uuid[]);

    inner_co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (inner_co_varnames_id, array[]::uuid[]);

    inner_co_cellvars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_cellvars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (inner_co_cellvars_id, array[]::uuid[]);

    inner_co_freevars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_freevars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (inner_co_freevars_id, ARRAY[var_x_id]);

    inner_co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (inner_co_code_id, decode('9501970089005300', 'hex'));

    inner_code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (inner_code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (inner_code_obj_id, inner_co_code_id, inner_co_consts_id, inner_co_names_id, empty_str_id, empty_str_id, 0, inner_co_varnames_id, inner_co_cellvars_id, inner_co_freevars_id, 0);

    -- Build outer code object
    outer_co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (outer_co_consts_id, ARRAY[const_10_id, inner_code_obj_id]);

    outer_co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (outer_co_names_id, array[]::uuid[]);

    outer_co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (outer_co_varnames_id, ARRAY[var_inner_id]);

    outer_co_cellvars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_cellvars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (outer_co_cellvars_id, ARRAY[var_x_id]);

    outer_co_freevars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_freevars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (outer_co_freevars_id, array[]::uuid[]);

    -- outer bytecode: MAKE_CELL 1 | RESUME 0 | LOAD_CONST 0 | STORE_DEREF 1 |
    --   LOAD_CLOSURE 1 | BUILD_TUPLE 1 | LOAD_CONST 1 |
    --   MAKE_FUNCTION 8 | STORE_FAST 0 | PUSH_NULL | LOAD_FAST 0 | PRECALL 0 | CALL 0 | RETURN_VALUE
    -- (CPython 3.11: args are absolute fastlocals indices; x cell is at nlocals+0 = 1)
    outer_co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (outer_co_code_id, decode('8701970064008a0188016601640184087d0002007c00a600ab005300', 'hex'));

    outer_code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (outer_code_obj_id, outer_co_code_id, outer_co_consts_id, outer_co_names_id, empty_str_id, empty_str_id, 0, outer_co_varnames_id, outer_co_cellvars_id, outer_co_freevars_id, 1);

    -- Create frame for outer
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    SELECT md_dict INTO builtins_dict_id FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, outer_code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    -- Execute outer
    res_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: closure test raised exception';
    END IF;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: closure test returned NULL';
    END IF;
    SELECT long_value INTO res_val FROM public.py_long_object WHERE ob_base = res_id;
    IF res_val IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'FAIL: closure expected 10, got %', res_val;
    END IF;
    RAISE NOTICE '  Test 2 PASS: closure captures x=10, inner() returns 10';
    pass_count := pass_count + 1;

    -- ================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE 'All closure opcode tests passed!';
END $$;
