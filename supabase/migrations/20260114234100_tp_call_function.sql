-- ============================================================================
-- Migration: tp_call handler for user-defined functions (function type)
-- Created: 2026-01-14 23:41:00
--
-- Purpose:
--   Implements py_call_function, the tp_call handler for user-defined
--   functions (PyFunctionObject). This is equivalent to CPython's
--   _PyFunction_Vectorcall / function_call.
--
--   When a user-defined function is called:
--   1. Read func_code, func_globals, func_defaults from py_function_object
--   2. Create a new frame with f_code, f_globals, f_locals, f_builtins
--   3. Map positional args to f_fastlocals slots (matching co_varnames order)
--   4. Fill missing positional args from func_defaults (rightmost parameters)
--   5. Handle keyword arguments if kwargs_id is provided
--   6. Call py_eval_frame(new_frame) and return its result
--
-- Depends: function_object_schema, python_bootstrap, ceval_core, ceval_eval_frame
-- ============================================================================

-- py_call_function: tp_call handler for 'function' type objects.
-- Signature matches tp_call convention: (obj_id UUID, args UUID[], kwargs_id UUID) RETURNS UUID.
CREATE OR REPLACE FUNCTION public.py_call_function(
    func_obj_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';

    v_func_code UUID;
    v_func_globals UUID;
    v_func_defaults UUID;
    v_func_kwdefaults UUID;

    v_co_argcount INTEGER;
    v_co_varnames UUID;
    v_varnames_items UUID[];

    v_defaults_items UUID[];
    v_defaults_count INTEGER;
    v_num_positional INTEGER;
    v_num_missing INTEGER;
    v_defaults_start INTEGER;

    v_new_frame_id UUID;
    v_new_locals_id UUID;
    v_builtins_dict_id UUID;

    v_fastlocals UUID[];
    v_result UUID;
    i INTEGER;

    -- kwargs handling
    v_kw_keys UUID[];
    v_kw_key UUID;
    v_kw_value UUID;
    v_varname_str TEXT;
    v_kwname_str TEXT;
    v_slot_idx INTEGER;
    v_found BOOLEAN;
BEGIN
    -- Read function object fields
    SELECT func_code, func_globals, func_defaults, func_kwdefaults
    INTO v_func_code, v_func_globals, v_func_defaults, v_func_kwdefaults
    FROM public.py_function_object
    WHERE ob_base = func_obj_id;

    IF v_func_code IS NULL THEN
        RAISE EXCEPTION 'py_call_function: Function object % does not exist or has no code', func_obj_id;
    END IF;

    -- Read code object fields
    SELECT co_argcount, co_varnames
    INTO v_co_argcount, v_co_varnames
    FROM public.py_code_object
    WHERE ob_base = v_func_code;

    -- Read varnames tuple
    SELECT ob_item INTO v_varnames_items
    FROM public.py_tuple_object
    WHERE ob_base = v_co_varnames;

    IF v_varnames_items IS NULL THEN
        v_varnames_items := array[]::uuid[];
    END IF;

    -- Initialize f_fastlocals with NULLs for co_argcount slots
    v_fastlocals := array_fill(NULL::uuid, ARRAY[GREATEST(v_co_argcount, 1)]);
    IF v_co_argcount = 0 THEN
        v_fastlocals := array[]::uuid[];
    END IF;

    -- Map positional args to f_fastlocals
    v_num_positional := COALESCE(array_length(args, 1), 0);
    FOR i IN 1..LEAST(v_num_positional, v_co_argcount) LOOP
        v_fastlocals[i] := args[i];
    END LOOP;

    -- Fill missing positional args from func_defaults (rightmost parameters)
    IF v_num_positional < v_co_argcount AND v_func_defaults IS NOT NULL THEN
        SELECT ob_item INTO v_defaults_items
        FROM public.py_tuple_object
        WHERE ob_base = v_func_defaults;

        v_defaults_count := COALESCE(array_length(v_defaults_items, 1), 0);
        -- defaults cover the rightmost co_argcount parameters
        -- defaults[0] corresponds to parameter (co_argcount - defaults_count)
        FOR i IN (v_num_positional + 1)..v_co_argcount LOOP
            -- parameter index i (1-based) maps to default index:
            -- default_idx = i - (co_argcount - defaults_count)
            v_defaults_start := v_co_argcount - v_defaults_count;
            IF i > v_defaults_start THEN
                v_fastlocals[i] := v_defaults_items[i - v_defaults_start];
            END IF;
        END LOOP;
    END IF;

    -- Handle keyword arguments
    IF kwargs_id IS NOT NULL THEN
        SELECT array_agg(me_key) INTO v_kw_keys
        FROM public.py_dict_entry
        WHERE dict_id = kwargs_id;

        IF v_kw_keys IS NOT NULL THEN
            FOR i IN 1..array_length(v_kw_keys, 1) LOOP
                v_kw_key := v_kw_keys[i];
                SELECT me_value INTO v_kw_value
                FROM public.py_dict_entry
                WHERE dict_id = kwargs_id AND me_key = v_kw_key;

                SELECT str_value INTO v_kwname_str
                FROM public.py_unicode_object
                WHERE ob_base = v_kw_key;

                -- Find matching slot in co_varnames
                v_found := FALSE;
                FOR v_slot_idx IN 1..v_co_argcount LOOP
                    SELECT str_value INTO v_varname_str
                    FROM public.py_unicode_object
                    WHERE ob_base = v_varnames_items[v_slot_idx];

                    IF v_varname_str = v_kwname_str THEN
                        v_fastlocals[v_slot_idx] := v_kw_value;
                        v_found := TRUE;
                        EXIT;
                    END IF;
                END LOOP;

                IF NOT v_found THEN
                    PERFORM public.py_err_set_type_error(
                        'got an unexpected keyword argument ''' || COALESCE(v_kwname_str, '?') || ''''
                    );
                    RETURN NULL;
                END IF;
            END LOOP;
        END IF;
    END IF;

    -- Get builtins dict from builtins module
    SELECT md_dict INTO v_builtins_dict_id
    FROM public.py_module_object
    WHERE ob_base = ID_BUILTINS_MODULE;

    IF v_builtins_dict_id IS NULL THEN
        v_builtins_dict_id := v_func_globals;  -- fallback
    END IF;

    -- Create new locals dict
    v_new_locals_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_new_locals_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (v_new_locals_id);

    -- Create new frame
    v_new_frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_new_frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins, f_fastlocals)
    VALUES (v_new_frame_id, v_func_code, v_func_globals, v_new_locals_id, v_builtins_dict_id, v_fastlocals);

    -- Execute the function body
    v_result := public.py_eval_frame(
      current_setting('elytra.thread_state_id')::uuid,
      v_new_frame_id
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Register tp_call for function type
DO $$
DECLARE
    ID_FUNCTION_TYPE UUID := '00000000-0000-4000-a000-000000000017';
BEGIN
    UPDATE public.py_type_object
    SET tp_call = 'py_call_function'::regproc
    WHERE ob_base = ID_FUNCTION_TYPE;
END $$;
