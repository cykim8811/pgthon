-- ============================================================================
-- Test: Instance Creation (py_type_tp_call, __init__, attribute access)
--
-- Tests:
--   1. py_type_tp_call exists and type type has tp_call registered
--   2. Direct SQL: calling a user-defined type creates an instance
--   3. Instance has correct ob_type and py_instance_object row
--   4. Bytecode: class Dog with __init__(self, name) → d = Dog("Rex") → d.name == "Rex"
-- ============================================================================

SELECT set_config('elytra.thread_state_id', '00000000-0000-4000-e000-000000000030', false);

DO $$
DECLARE
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE    UUID := '00000000-0000-4000-a000-000000000003';
    ID_BYTES_TYPE  UUID := '00000000-0000-4000-a000-000000000012';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000019';
    ID_TYPE_TYPE   UUID := '00000000-0000-4000-a000-000000000002';
    ID_NONE_OBJ    UUID := '00000000-0000-4000-b000-000000000001';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';

    test_count INT := 0;
    pass_count INT := 0;

    -- Shared helpers
    empty_str_id UUID;
    co_varnames_id UUID;
    co_cellvars_id UUID;
    co_freevars_id UUID;
    builtins_dict_id UUID;

    -- For creating a simple class (no __init__)
    v_class_type_id UUID;
    v_bases_tuple_id UUID;
    v_class_dict_id UUID;

    -- For instance creation test
    v_instance_id UUID;
    v_inst_type UUID;
    v_in_dict UUID;

    -- For bytecode test (class Dog with __init__)
    -- __init__ code
    init_co_code_id UUID;
    init_co_consts_id UUID;
    init_co_names_id UUID;
    init_code_obj_id UUID;
    init_co_varnames_id UUID;

    -- Class body code
    body_co_code_id UUID;
    body_co_consts_id UUID;
    body_co_names_id UUID;
    body_code_obj_id UUID;

    -- Outer code
    outer_co_code_id UUID;
    outer_co_consts_id UUID;
    outer_co_names_id UUID;
    outer_code_obj_id UUID;

    -- Frame
    frame_id UUID;
    locals_dict_id UUID;
    globals_dict_id UUID;

    -- Strings
    str_dog_id UUID;
    str_name_id UUID;
    str_init_id UUID;
    str_init_qualname_id UUID;
    str_d_id UUID;
    str_rex_id UUID;

    -- Results
    res_id UUID;
    res_str TEXT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Instance Creation Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Setup shared objects
    empty_str_id := public.py_str_from_text('');

    co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_varnames_id, ARRAY[]::uuid[]);

    co_cellvars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_cellvars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_cellvars_id, ARRAY[]::uuid[]);

    co_freevars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (co_freevars_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (co_freevars_id, ARRAY[]::uuid[]);

    SELECT md_dict INTO builtins_dict_id FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    str_dog_id := public.py_str_from_text('Dog');
    str_name_id := public.py_str_from_text('name');
    str_init_id := public.py_str_from_text('__init__');
    str_init_qualname_id := public.py_str_from_text('Dog.__init__');
    str_d_id := public.py_str_from_text('d');
    str_rex_id := public.py_str_from_text('Rex');

    -- ================================================================
    -- Test 1: py_type_tp_call exists and type type has tp_call
    -- ================================================================
    test_count := test_count + 1;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'py_type_tp_call') THEN
        RAISE EXCEPTION 'FAIL: py_type_tp_call does not exist';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.py_type_object
        WHERE ob_base = ID_TYPE_TYPE AND tp_call IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'FAIL: type type does not have tp_call registered';
    END IF;
    RAISE NOTICE '  ✓ Test 1: py_type_tp_call exists and type.tp_call is set';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 2: Direct SQL — create a simple class, then instantiate it
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- Create a simple class (like: class Simple: pass)
    v_bases_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_bases_tuple_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (v_bases_tuple_id, ARRAY[ID_OBJECT_TYPE]);

    v_class_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_class_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (v_class_dict_id);

    v_class_type_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_class_type_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (v_class_type_id, 'Simple', v_bases_tuple_id, v_class_dict_id);

    -- Instantiate: Simple()
    v_instance_id := public.py_object_call(v_class_type_id, ARRAY[]::uuid[], NULL);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Simple() raised exception';
    END IF;
    IF v_instance_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: Simple() returned NULL';
    END IF;

    -- Check instance has correct ob_type
    SELECT ob_type INTO v_inst_type FROM public.py_object WHERE id = v_instance_id;
    IF v_inst_type IS DISTINCT FROM v_class_type_id THEN
        RAISE EXCEPTION 'FAIL: instance ob_type expected %, got %', v_class_type_id, v_inst_type;
    END IF;

    -- Check instance has py_instance_object row
    SELECT in_dict INTO v_in_dict FROM public.py_instance_object WHERE ob_base = v_instance_id;
    IF v_in_dict IS NULL THEN
        RAISE EXCEPTION 'FAIL: instance has no py_instance_object row';
    END IF;

    RAISE NOTICE '  ✓ Test 2: Simple() creates instance with correct type and __dict__';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 3: Bytecode end-to-end
    --   class Dog:
    --       def __init__(self, name):
    --           self.name = name
    --   d = Dog("Rex")
    --   d.name  → "Rex"
    -- ================================================================
    test_count := test_count + 1;
    PERFORM public.py_err_clear();

    -- Build __init__ code object
    -- co_varnames: (self, name)
    init_co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (init_co_varnames_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (init_co_varnames_id, ARRAY[
        public.py_str_from_text('self'),
        str_name_id
    ]);

    -- co_consts: (None,)
    init_co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (init_co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (init_co_consts_id, ARRAY[ID_NONE_OBJ]);

    -- co_names: (name,)  — used by STORE_ATTR
    init_co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (init_co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (init_co_names_id, ARRAY[str_name_id]);

    -- Bytecode: RESUME 0 | LOAD_FAST 1 | LOAD_FAST 0 | STORE_ATTR 0 | LOAD_CONST 0 | RETURN_VALUE
    -- Hex: 97007c017c005f0064005300
    init_co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (init_co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (init_co_code_id, decode('97007c017c005f0064005300', 'hex'));

    init_code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (init_code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (init_code_obj_id, init_co_code_id, init_co_consts_id, init_co_names_id, empty_str_id, str_init_id, 2, init_co_varnames_id, co_cellvars_id, co_freevars_id, 2);

    -- Build class body code object
    -- co_consts: (init_code, 'Dog.__init__' qualname, None)
    body_co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (body_co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (body_co_consts_id, ARRAY[init_code_obj_id, ID_NONE_OBJ]);

    -- co_names: (__init__,)
    body_co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (body_co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (body_co_names_id, ARRAY[str_init_id]);

    -- Bytecode: RESUME 0 | LOAD_CONST 0 | MAKE_FUNCTION 0 | STORE_NAME 0 | LOAD_CONST 1 | RETURN_VALUE
    -- Hex: 9700640084005a0064015300
    body_co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (body_co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (body_co_code_id, decode('9700640084005a0064015300', 'hex'));

    body_code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (body_code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (body_code_obj_id, body_co_code_id, body_co_consts_id, body_co_names_id, empty_str_id, str_dog_id, 0, co_varnames_id, co_cellvars_id, co_freevars_id, 0);

    -- Build outer code object
    -- co_consts: (body_code, 'Dog' name, 'Rex')
    outer_co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_consts_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (outer_co_consts_id, ARRAY[body_code_obj_id, str_dog_id, str_rex_id]);

    -- co_names: (Dog, d, name)
    outer_co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_names_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (outer_co_names_id, ARRAY[str_dog_id, str_d_id, str_name_id]);

    -- Bytecode (36 bytes):
    -- RESUME 0 | PUSH_NULL | LOAD_BUILD_CLASS |
    -- LOAD_CONST 0 | MAKE_FUNCTION 0 | LOAD_CONST 1 | PRECALL 2 | CALL 2 | STORE_NAME 0 |
    -- PUSH_NULL | LOAD_NAME 0 | LOAD_CONST 2 | PRECALL 1 | CALL 1 | STORE_NAME 1 |
    -- LOAD_NAME 1 | LOAD_ATTR 2 | RETURN_VALUE
    outer_co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (outer_co_code_id,
        decode('970002004700640084006401a602ab025a00020065006402a601ab015a0165016a025300', 'hex'));

    outer_code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (outer_code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (ob_base, co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars, co_nlocals)
    VALUES (outer_code_obj_id, outer_co_code_id, outer_co_consts_id, outer_co_names_id, empty_str_id, empty_str_id, 0, co_varnames_id, co_cellvars_id, co_freevars_id, 0);

    -- Create frame
    locals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (locals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (locals_dict_id);
    globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (globals_dict_id);

    frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (frame_id, outer_code_obj_id, globals_dict_id, locals_dict_id, builtins_dict_id);

    -- Execute
    res_id := public.py_eval_frame('00000000-0000-4000-e000-000000000030'::uuid, frame_id);
    IF public.py_err_occurred() THEN
        RAISE EXCEPTION 'FAIL: Dog() bytecode raised exception';
    END IF;
    IF res_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: Dog() bytecode returned NULL';
    END IF;

    -- res_id should be the string "Rex"
    SELECT str_value INTO res_str FROM public.py_unicode_object WHERE ob_base = res_id;
    IF res_str IS DISTINCT FROM 'Rex' THEN
        RAISE EXCEPTION 'FAIL: d.name expected "Rex", got "%"', res_str;
    END IF;

    RAISE NOTICE '  ✓ Test 3: class Dog __init__ + Dog("Rex").name == "Rex"';
    pass_count := pass_count + 1;

    -- ================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE 'All instance creation tests passed!';
END $$;
