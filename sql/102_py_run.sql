-- ============================================================================
-- Migration: py_run RPC — Pgthon Python Playground
-- 20260114242000
--
-- Four functions for the playground frontend:
--   1. py_create_const(JSONB) → UUID — create a py_object from JSON
--   2. py_create_code_object(JSONB) → UUID — create a full code object
--   3. py_object_to_jsonb(UUID) → JSONB — serialize a py_object to JSON
--   4. py_run(JSONB) → JSONB — main RPC entry point
-- ============================================================================

-- ============================================================================
-- 1. py_create_const: Create a primitive py_object from JSON descriptor
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_create_const(p_const JSONB)
RETURNS UUID AS $$
DECLARE
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_FLOAT_TYPE  UUID := '00000000-0000-4000-a000-000000000009';
    ID_BYTES_TYPE  UUID := '00000000-0000-4000-a000-000000000012';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_NONE_SINGLETON UUID := '00000000-0000-4000-b000-000000000001';
    ID_TRUE_SINGLETON UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_SINGLETON UUID := '00000000-0000-4000-b000-000000000011';

    v_type TEXT;
    new_id UUID;
    v_items JSONB;
    v_item_ids UUID[];
    i INTEGER;
BEGIN
    v_type := p_const->>'type';

    -- none → singleton
    IF v_type = 'none' THEN
        RETURN ID_NONE_SINGLETON;
    END IF;

    -- bool → singletons
    IF v_type = 'bool' THEN
        IF (p_const->>'value')::boolean THEN
            RETURN ID_TRUE_SINGLETON;
        ELSE
            RETURN ID_FALSE_SINGLETON;
        END IF;
    END IF;

    -- int
    IF v_type = 'int' THEN
        new_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (new_id, ID_INT_TYPE);
        INSERT INTO public.py_long_object (ob_base, long_value) VALUES (new_id, (p_const->>'value')::numeric);
        RETURN new_id;
    END IF;

    -- float
    IF v_type = 'float' THEN
        new_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (new_id, ID_FLOAT_TYPE);
        INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (new_id, (p_const->>'value')::double precision);
        RETURN new_id;
    END IF;

    -- str
    IF v_type = 'str' THEN
        RETURN public.py_str_from_text(p_const->>'value');
    END IF;

    -- bytes
    IF v_type = 'bytes' THEN
        new_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (new_id, ID_BYTES_TYPE);
        INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (new_id, decode(p_const->>'value', 'hex'));
        RETURN new_id;
    END IF;

    -- tuple (recursive)
    IF v_type = 'tuple' THEN
        v_items := p_const->'items';
        v_item_ids := ARRAY[]::UUID[];
        FOR i IN 0..jsonb_array_length(v_items) - 1 LOOP
            v_item_ids := array_append(v_item_ids, public.py_create_const(v_items->i));
        END LOOP;
        new_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (new_id, ID_TUPLE_TYPE);
        INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (new_id, v_item_ids);
        RETURN new_id;
    END IF;

    -- code (recursive — nested code objects in consts)
    IF v_type = 'code' THEN
        RETURN public.py_create_code_object(p_const->'value');
    END IF;

    -- frozenset, ellipsis, or unknown → fallback to None
    RETURN ID_NONE_SINGLETON;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 2. py_create_code_object: Create a full py_code_object from JSON
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_create_code_object(p_code JSONB)
RETURNS UUID AS $$
DECLARE
    ID_BYTES_TYPE  UUID := '00000000-0000-4000-a000-000000000012';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_CODE_TYPE   UUID := '00000000-0000-4000-a000-000000000019';

    v_co_code_id UUID;
    v_co_consts_id UUID;
    v_co_names_id UUID;
    v_co_varnames_id UUID;
    v_co_cellvars_id UUID;
    v_co_freevars_id UUID;
    v_co_filename_id UUID;
    v_co_name_id UUID;
    v_code_obj_id UUID;

    v_const_ids UUID[];
    v_name_ids UUID[];
    v_arr JSONB;
    i INTEGER;
BEGIN
    -- co_code (bytecode as bytes)
    v_co_code_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_co_code_id, ID_BYTES_TYPE);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value)
    VALUES (v_co_code_id, decode(p_code->>'bytecode', 'hex'));

    -- co_consts (tuple of py_create_const results)
    v_arr := p_code->'consts';
    v_const_ids := ARRAY[]::UUID[];
    IF v_arr IS NOT NULL AND jsonb_array_length(v_arr) > 0 THEN
        FOR i IN 0..jsonb_array_length(v_arr) - 1 LOOP
            v_const_ids := array_append(v_const_ids, public.py_create_const(v_arr->i));
        END LOOP;
    END IF;
    v_co_consts_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_co_consts_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (v_co_consts_id, v_const_ids);

    -- co_names (tuple of strings)
    v_arr := p_code->'names';
    v_name_ids := ARRAY[]::UUID[];
    IF v_arr IS NOT NULL AND jsonb_array_length(v_arr) > 0 THEN
        FOR i IN 0..jsonb_array_length(v_arr) - 1 LOOP
            v_name_ids := array_append(v_name_ids, public.py_str_from_text(v_arr->>i));
        END LOOP;
    END IF;
    v_co_names_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_co_names_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (v_co_names_id, v_name_ids);

    -- co_varnames (tuple of strings)
    v_arr := p_code->'varnames';
    v_name_ids := ARRAY[]::UUID[];
    IF v_arr IS NOT NULL AND jsonb_array_length(v_arr) > 0 THEN
        FOR i IN 0..jsonb_array_length(v_arr) - 1 LOOP
            v_name_ids := array_append(v_name_ids, public.py_str_from_text(v_arr->>i));
        END LOOP;
    END IF;
    v_co_varnames_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_co_varnames_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (v_co_varnames_id, v_name_ids);

    -- co_cellvars (tuple of strings)
    v_arr := p_code->'cellvars';
    v_name_ids := ARRAY[]::UUID[];
    IF v_arr IS NOT NULL AND jsonb_array_length(v_arr) > 0 THEN
        FOR i IN 0..jsonb_array_length(v_arr) - 1 LOOP
            v_name_ids := array_append(v_name_ids, public.py_str_from_text(v_arr->>i));
        END LOOP;
    END IF;
    v_co_cellvars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_co_cellvars_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (v_co_cellvars_id, v_name_ids);

    -- co_freevars (tuple of strings)
    v_arr := p_code->'freevars';
    v_name_ids := ARRAY[]::UUID[];
    IF v_arr IS NOT NULL AND jsonb_array_length(v_arr) > 0 THEN
        FOR i IN 0..jsonb_array_length(v_arr) - 1 LOOP
            v_name_ids := array_append(v_name_ids, public.py_str_from_text(v_arr->>i));
        END LOOP;
    END IF;
    v_co_freevars_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_co_freevars_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (v_co_freevars_id, v_name_ids);

    -- co_filename, co_name
    v_co_filename_id := public.py_str_from_text(COALESCE(p_code->>'filename', '<pgthon>'));
    v_co_name_id := public.py_str_from_text(COALESCE(p_code->>'name', '<module>'));

    -- INSERT code object
    v_code_obj_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_code_obj_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (
        ob_base, co_code, co_consts, co_names, co_filename, co_name,
        co_argcount, co_varnames, co_cellvars, co_freevars,
        co_nlocals, co_stacksize, co_flags,
        co_exceptiontable
    ) VALUES (
        v_code_obj_id,
        v_co_code_id,
        v_co_consts_id,
        v_co_names_id,
        v_co_filename_id,
        v_co_name_id,
        COALESCE((p_code->>'argcount')::integer, 0),
        v_co_varnames_id,
        v_co_cellvars_id,
        v_co_freevars_id,
        COALESCE((p_code->>'nlocals')::integer, NULL),
        COALESCE((p_code->>'stacksize')::integer, NULL),
        COALESCE((p_code->>'flags')::integer, 0),
        CASE WHEN p_code->>'exceptiontable' IS NOT NULL
             THEN decode(p_code->>'exceptiontable', 'hex')
             ELSE NULL END
    );

    RETURN v_code_obj_id;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 3. py_object_to_jsonb: Serialize a py_object to JSON for the response
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_object_to_jsonb(obj_id UUID)
RETURNS JSONB AS $$
DECLARE
    ID_STR_TYPE    UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_FLOAT_TYPE  UUID := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE   UUID := '00000000-0000-4000-a000-000000000013';
    ID_NONE_TYPE   UUID := '00000000-0000-4000-a000-000000000008';
    ID_LIST_TYPE   UUID := '00000000-0000-4000-a000-000000000005';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';

    v_type_id UUID;
    v_int_val NUMERIC;
    v_float_val DOUBLE PRECISION;
    v_str_val TEXT;
    v_bool_val BOOLEAN;
    v_items UUID[];
    v_result JSONB;
    v_arr JSONB := '[]'::jsonb;
    i INTEGER;

    v_key UUID;
    v_value UUID;
    v_key_text TEXT;
    v_repr_id UUID;
    v_repr_text TEXT;
BEGIN
    IF obj_id IS NULL THEN
        RETURN jsonb_build_object('type', 'none');
    END IF;

    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = obj_id;

    -- none
    IF v_type_id = ID_NONE_TYPE THEN
        RETURN jsonb_build_object('type', 'none');
    END IF;

    -- bool (check before int)
    IF v_type_id = ID_BOOL_TYPE THEN
        SELECT bool_value INTO v_bool_val FROM public.py_bool_object WHERE ob_base = obj_id;
        RETURN jsonb_build_object('type', 'bool', 'value', v_bool_val);
    END IF;

    -- int
    IF v_type_id = ID_INT_TYPE THEN
        SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = obj_id;
        RETURN jsonb_build_object('type', 'int', 'value', v_int_val);
    END IF;

    -- float
    IF v_type_id = ID_FLOAT_TYPE THEN
        SELECT ob_fval INTO v_float_val FROM public.py_float_object WHERE ob_base = obj_id;
        RETURN jsonb_build_object('type', 'float', 'value', v_float_val);
    END IF;

    -- str
    IF v_type_id = ID_STR_TYPE THEN
        SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = obj_id;
        RETURN jsonb_build_object('type', 'str', 'value', v_str_val);
    END IF;

    -- list
    IF v_type_id = ID_LIST_TYPE THEN
        SELECT ob_item INTO v_items FROM public.py_list_object WHERE ob_base = obj_id;
        FOR i IN 1..COALESCE(array_length(v_items, 1), 0) LOOP
            v_arr := v_arr || public.py_object_to_jsonb(v_items[i]);
        END LOOP;
        RETURN jsonb_build_object('type', 'list', 'items', v_arr);
    END IF;

    -- tuple
    IF v_type_id = ID_TUPLE_TYPE THEN
        SELECT ob_item INTO v_items FROM public.py_tuple_object WHERE ob_base = obj_id;
        FOR i IN 1..COALESCE(array_length(v_items, 1), 0) LOOP
            v_arr := v_arr || public.py_object_to_jsonb(v_items[i]);
        END LOOP;
        RETURN jsonb_build_object('type', 'tuple', 'items', v_arr);
    END IF;

    -- dict
    IF v_type_id = ID_DICT_TYPE THEN
        v_result := '{}'::jsonb;
        FOR v_key, v_value IN
            SELECT me_key, me_value FROM public.py_dict_entry WHERE dict_id = obj_id ORDER BY id
        LOOP
            -- Get a string representation of the key
            v_repr_id := public.py_object_repr(v_key);
            SELECT str_value INTO v_key_text FROM public.py_unicode_object WHERE ob_base = v_repr_id;
            v_result := jsonb_set(v_result, ARRAY[COALESCE(v_key_text, '???')], public.py_object_to_jsonb(v_value));
        END LOOP;
        RETURN jsonb_build_object('type', 'dict', 'entries', v_result);
    END IF;

    -- Fallback: use py_object_repr to get a string representation
    v_repr_id := public.py_object_repr(obj_id);
    SELECT str_value INTO v_repr_text FROM public.py_unicode_object WHERE ob_base = v_repr_id;
    RETURN jsonb_build_object('type', 'object', 'repr', COALESCE(v_repr_text, '<unknown>'));
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 4. py_run: Main RPC entry point
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_run(p_code JSONB)
RETURNS JSONB
SECURITY DEFINER
AS $$
DECLARE
    ID_DICT_TYPE       UUID := '00000000-0000-4000-a000-000000000006';
    ID_OBJECT_TYPE     UUID := '00000000-0000-4000-a000-000000000001';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';

    v_ts_id UUID;
    v_code_obj_id UUID;
    v_globals_dict_id UUID;
    v_locals_dict_id UUID;
    v_builtins_dict_id UUID;
    v_frame_id UUID;
    v_result_id UUID;
    v_mode TEXT;

    v_result_json JSONB;
    v_globals_json JSONB := '{}'::jsonb;
    v_error_json JSONB := 'null'::jsonb;

    -- For reading exception state
    v_exc_type_id UUID;
    v_exc_value_id UUID;
    v_exc_type_name TEXT;
    v_exc_msg_text TEXT;

    -- For globals iteration
    v_key UUID;
    v_value UUID;
    v_key_text TEXT;
BEGIN
    -- Create a fresh thread state for this execution
    -- Reuse the bootstrapped runtime and interpreter
    v_ts_id := gen_random_uuid();
    INSERT INTO public.py_thread_state (id, interp_id)
    VALUES (v_ts_id, '00000000-0000-4000-e000-000000000020');
    PERFORM set_config('pgthon.thread_state_id', v_ts_id::text, true);

    -- Clear any previous exceptions
    UPDATE public.py_thread_state
    SET exc_type_id = NULL, exc_value_id = NULL, exc_traceback_id = NULL
    WHERE id = v_ts_id;

    -- Create code object from JSON
    v_code_obj_id := public.py_create_code_object(p_code);

    -- Create globals dict; locals = globals at module level (exec mode)
    v_globals_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_globals_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (v_globals_dict_id);

    v_mode := COALESCE(p_code->>'mode', 'eval');
    IF v_mode = 'exec' THEN
        v_locals_dict_id := v_globals_dict_id;
    ELSE
        v_locals_dict_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (v_locals_dict_id, ID_DICT_TYPE);
        INSERT INTO public.py_dict_object (ob_base) VALUES (v_locals_dict_id);
    END IF;

    -- Get builtins dict from the builtins module
    SELECT md_dict INTO v_builtins_dict_id
    FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    -- Create frame
    v_frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (v_frame_id, v_code_obj_id, v_globals_dict_id, v_locals_dict_id, v_builtins_dict_id);

    -- Execute
    BEGIN
        v_result_id := public.py_eval_frame(v_ts_id, v_frame_id);

        -- Check for Python-level exceptions (set via py_err_set*)
        SELECT exc_type_id, exc_value_id INTO v_exc_type_id, v_exc_value_id
        FROM public.py_thread_state WHERE id = v_ts_id;

        IF v_exc_type_id IS NOT NULL THEN
            -- Extract exception type name
            SELECT tp_name INTO v_exc_type_name
            FROM public.py_type_object WHERE ob_base = v_exc_type_id;

            -- Extract exception message from ob_args[0] of the exception instance
            -- CPython: exc_value is a py_base_exception_object with ob_args tuple
            v_exc_msg_text := '';
            IF v_exc_value_id IS NOT NULL THEN
                SELECT t.str_value INTO v_exc_msg_text
                FROM public.py_base_exception_object e
                JOIN public.py_tuple_object args ON args.ob_base = e.ob_args
                JOIN public.py_unicode_object t ON t.ob_base = (args.ob_item)[1]
                WHERE e.ob_base = v_exc_value_id;

                IF v_exc_msg_text IS NULL THEN
                    v_exc_msg_text := COALESCE(v_exc_type_name, 'Error');
                END IF;
            END IF;

            v_error_json := jsonb_build_object(
                'type', COALESCE(v_exc_type_name, 'Exception'),
                'message', COALESCE(v_exc_msg_text, '')
            );
            v_result_json := 'null'::jsonb;
        ELSE
            v_result_json := public.py_object_to_jsonb(v_result_id);
        END IF;

    EXCEPTION WHEN OTHERS THEN
        -- PL/pgSQL-level exceptions (RAISE EXCEPTION from within the VM)
        v_error_json := jsonb_build_object(
            'type', 'InternalError',
            'message', SQLERRM
        );
        v_result_json := 'null'::jsonb;
    END;

    -- Collect globals (mode=exec: globals contain the side effects)
    IF v_mode = 'exec' THEN
        FOR v_key, v_value IN
            SELECT me_key, me_value FROM public.py_dict_entry WHERE dict_id = v_globals_dict_id ORDER BY id
        LOOP
            SELECT str_value INTO v_key_text FROM public.py_unicode_object WHERE ob_base = v_key;
            IF v_key_text IS NOT NULL AND LEFT(v_key_text, 2) != '__' THEN
                v_globals_json := jsonb_set(v_globals_json, ARRAY[v_key_text], public.py_object_to_jsonb(v_value));
            END IF;
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'result', v_result_json,
        'globals', v_globals_json,
        'error', v_error_json
    );
END;
$$ LANGUAGE plpgsql;
