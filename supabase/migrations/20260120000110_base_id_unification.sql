-- =====================================================
-- Migration: Base ID Unification
-- Description: Align schema with Python object model by
--              treating py_object.id (Base ID) as the only
--              public object identifier, and making all
--              references use Base IDs instead of table IDs.
-- =====================================================

--------------------------------------------------------
-- 1. SCHEMA FIXES: change FKs to point to Base IDs
--------------------------------------------------------

-- 1.1 py_function_object: func_code / func_globals
ALTER TABLE public.py_function_object
  DROP CONSTRAINT IF EXISTS py_function_object_func_code_fkey;

ALTER TABLE public.py_function_object
  DROP CONSTRAINT IF EXISTS py_function_object_func_globals_fkey;

-- func_code should reference the *code object's base id* (py_object.id)
ALTER TABLE public.py_function_object
  ALTER COLUMN func_code TYPE uuid;

ALTER TABLE public.py_function_object
  ADD CONSTRAINT py_function_object_func_code_fkey
  FOREIGN KEY (func_code) REFERENCES public.py_object(id) NOT VALID;

-- func_globals should reference the *dict object's base id* (py_object.id)
ALTER TABLE public.py_function_object
  ALTER COLUMN func_globals TYPE uuid;

ALTER TABLE public.py_function_object
  ADD CONSTRAINT py_function_object_func_globals_fkey
  FOREIGN KEY (func_globals) REFERENCES public.py_object(id) NOT VALID;


-- 1.2 py_type_object.tp_dict : point to dict base id
ALTER TABLE public.py_type_object
  DROP CONSTRAINT IF EXISTS py_type_object_tp_dict_fkey;

ALTER TABLE public.py_type_object
  ALTER COLUMN tp_dict TYPE uuid;

ALTER TABLE public.py_type_object
  ADD CONSTRAINT py_type_object_tp_dict_fkey
  FOREIGN KEY (tp_dict) REFERENCES public.py_object(id) NOT VALID;


-- 1.3 py_instance_object.in_dict : point to dict base id
ALTER TABLE public.py_instance_object
  DROP CONSTRAINT IF EXISTS py_instance_object_in_dict_fkey;

ALTER TABLE public.py_instance_object
  ALTER COLUMN in_dict TYPE uuid;

ALTER TABLE public.py_instance_object
  ADD CONSTRAINT py_instance_object_in_dict_fkey
  FOREIGN KEY (in_dict) REFERENCES public.py_object(id) NOT VALID;


-- 1.4 py_dict_entry.dict_id : point to dict base id
ALTER TABLE public.py_dict_entry
  DROP CONSTRAINT IF EXISTS py_dict_entry_dict_id_fkey;

ALTER TABLE public.py_dict_entry
  ALTER COLUMN dict_id TYPE uuid;

ALTER TABLE public.py_dict_entry
  ADD CONSTRAINT py_dict_entry_dict_id_fkey
  FOREIGN KEY (dict_id) REFERENCES public.py_object(id) NOT VALID;


--------------------------------------------------------
-- 2. DATA MIGRATION: convert existing table IDs to Base IDs
--------------------------------------------------------

DO $$
DECLARE
BEGIN
  -- 2.1 func_code: py_code_object.id -> py_code_object.ob_base
  UPDATE public.py_function_object f
  SET func_code = c.ob_base
  FROM public.py_code_object c
  WHERE f.func_code IS NOT NULL
    AND f.func_code = c.id;

  -- 2.2 func_globals: py_dict_object.id -> py_dict_object.ob_base
  UPDATE public.py_function_object f
  SET func_globals = d.ob_base
  FROM public.py_dict_object d
  WHERE f.func_globals IS NOT NULL
    AND f.func_globals = d.id;

  -- 2.3 tp_dict: py_dict_object.id -> py_dict_object.ob_base
  UPDATE public.py_type_object t
  SET tp_dict = d.ob_base
  FROM public.py_dict_object d
  WHERE t.tp_dict IS NOT NULL
    AND t.tp_dict = d.id;

  -- 2.4 in_dict: py_dict_object.id -> py_dict_object.ob_base
  UPDATE public.py_instance_object i
  SET in_dict = d.ob_base
  FROM public.py_dict_object d
  WHERE i.in_dict IS NOT NULL
    AND i.in_dict = d.id;

  -- 2.5 dict_entry.dict_id: py_dict_object.id -> py_dict_object.ob_base
  UPDATE public.py_dict_entry e
  SET dict_id = d.ob_base
  FROM public.py_dict_object d
  WHERE e.dict_id = d.id;
END;
$$;

-- Validate constraints after data migration
ALTER TABLE public.py_function_object VALIDATE CONSTRAINT py_function_object_func_code_fkey;
ALTER TABLE public.py_function_object VALIDATE CONSTRAINT py_function_object_func_globals_fkey;
ALTER TABLE public.py_type_object VALIDATE CONSTRAINT py_type_object_tp_dict_fkey;
ALTER TABLE public.py_instance_object VALIDATE CONSTRAINT py_instance_object_in_dict_fkey;
ALTER TABLE public.py_dict_entry VALIDATE CONSTRAINT py_dict_entry_dict_id_fkey;


--------------------------------------------------------
-- 3. FUNCTION FIXES: operate purely on Base IDs
--------------------------------------------------------

-- 3.1 vm_dict_set_item: p_dict_id is now always Base ID
CREATE OR REPLACE FUNCTION public.vm_dict_set_item(
    p_dict_id uuid,
    p_key_str text,
    p_value_id uuid
)
RETURNS void AS $$
DECLARE
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    v_key_obj uuid;
    v_key_base uuid;
    v_existing uuid;
BEGIN
    -- Check if key already exists (dict_id is Base ID)
    SELECT e.me_key
    INTO v_existing
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = p_dict_id
      AND u.str_value = p_key_str
    LIMIT 1;

    IF v_existing IS NOT NULL THEN
        -- Update existing entry
        UPDATE public.py_dict_entry
        SET me_value = p_value_id
        WHERE dict_id = p_dict_id
          AND me_key = v_existing;
    ELSE
        -- Create new key string object
        v_key_base := gen_random_uuid();
        v_key_obj := gen_random_uuid();

        INSERT INTO public.py_object (id, ob_type) VALUES (v_key_base, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value)
        VALUES (v_key_obj, v_key_base, p_key_str);

        -- Insert new entry, dict_id uses Base ID
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value)
        VALUES (gen_random_uuid(), p_dict_id, v_key_base, p_value_id);

        -- Update usage count on underlying dict_object via ob_base
        UPDATE public.py_dict_object
        SET ma_used = ma_used + 1
        WHERE ob_base = p_dict_id;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- 3.2 vm_dict_get_item: p_dict_id is Base ID
CREATE OR REPLACE FUNCTION public.vm_dict_get_item(p_dict_id uuid, p_key_str text)
RETURNS uuid AS $$
DECLARE
    v_val_id uuid;
BEGIN
    SELECT e.me_value
    INTO v_val_id
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = p_dict_id
      AND u.str_value = p_key_str
    LIMIT 1;

    RETURN v_val_id;
END;
$$ LANGUAGE plpgsql;


-- 3.3 vm_lookup_in_type: tp_dict is Base ID, dict_entry.dict_id is Base ID
CREATE OR REPLACE FUNCTION public.vm_lookup_in_type(type_id uuid, attr_name text)
RETURNS uuid AS $$
DECLARE
    v_dict_base uuid;
    v_value_id uuid;
    ID_OBJ_TYPE uuid := '00000000-0000-4000-a000-000000000001';
BEGIN
    -- 1. Look in current Type's tp_dict (Base ID of dict)
    SELECT tp_dict INTO v_dict_base
    FROM public.py_type_object
    WHERE id = type_id;

    -- Search in dict by string key
    SELECT e.me_value
    INTO v_value_id
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = v_dict_base
      AND u.str_value = attr_name
    LIMIT 1;

    IF v_value_id IS NOT NULL THEN
        RETURN v_value_id;
    END IF;

    -- 2. Fallback to 'object' type (simplified MRO)
    IF type_id <> ID_OBJ_TYPE THEN
        RETURN public.vm_lookup_in_type(ID_OBJ_TYPE, attr_name);
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- 3.4 vm_call: func_code now stores code Base ID; adjust lookups
CREATE OR REPLACE FUNCTION public.vm_call(
    callable_id uuid,
    args uuid[],
    p_caller_frame_id uuid DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
    v_type_id uuid;
    v_native_name text;

    ID_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000008';
    ID_JS_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000012';
    ID_METHOD_TYPE uuid := '00000000-0000-4000-a000-000000000013';
    ID_DCT_TYPE uuid := '00000000-0000-4000-a000-000000000006';

    -- Bound Method variables
    v_im_func uuid;
    v_im_self uuid;
    v_new_args uuid[];

    -- Bytecode function variables
    v_code_base_id uuid; -- Base ID of code object
    v_locals_base uuid;
    v_locals_internal uuid;
    v_varnames_base uuid;
    v_arg_name_uuid uuid;
    v_arg_name_str text;
    i integer;
    v_arg_count integer;
    v_frame_id uuid;  -- Frame object (Base ID)
    v_result uuid;

    -- Instance Call
    v_call_method uuid;
BEGIN
    -- 1. Get Type of Callable
    v_type_id := public.vm_get_type(callable_id);

    -----------------------------------------------------------------
    -- 2. BOUND METHOD: Unwrap and prepend self to args
    -----------------------------------------------------------------
    IF v_type_id = ID_METHOD_TYPE THEN
        SELECT im_func, im_self
        INTO v_im_func, v_im_self
        FROM public.py_bound_method_object
        WHERE ob_base = callable_id;

        v_new_args := array_prepend(v_im_self, args);
        RETURN public.vm_call(v_im_func, v_new_args, p_caller_frame_id);
    END IF;

    -----------------------------------------------------------------
    -- 3. NATIVE FUNCTION: Dispatch to native implementation
    -----------------------------------------------------------------
    IF v_type_id = ID_JS_FNC_TYPE THEN
        SELECT fn_name
        INTO v_native_name
        FROM public.py_builtin_function_object
        WHERE ob_base = callable_id;

        RETURN public.vm_native_dispatch(v_native_name, args);
    END IF;

    -----------------------------------------------------------------
    -- 4. PYTHON BYTECODE FUNCTION: Create locals and run frame
    -----------------------------------------------------------------
    IF v_type_id = ID_FNC_TYPE THEN
        -- Get code Base ID directly from func_code
        SELECT func_code
        INTO v_code_base_id
        FROM public.py_function_object
        WHERE ob_base = callable_id;

        -- Create locals dictionary (Base ID + internal row)
        v_locals_base := gen_random_uuid();
        v_locals_internal := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type)
        VALUES (v_locals_base, ID_DCT_TYPE);
        INSERT INTO public.py_dict_object (id, ob_base, ma_used)
        VALUES (v_locals_internal, v_locals_base, 0);

        -- Get varnames and argcount via code table row (by ob_base)
        SELECT c.co_varnames, c.co_argcount
        INTO v_varnames_base, v_arg_count
        FROM public.py_code_object c
        WHERE c.ob_base = v_code_base_id;

        -- Bind arguments to locals
        IF array_length(args, 1) > 0 THEN
            FOR i IN 1..array_length(args, 1) LOOP
                -- Get argument name from varnames tuple (0-indexed)
                v_arg_name_uuid := public.vm_tuple_getitem(v_varnames_base, i - 1);
                SELECT str_value
                INTO v_arg_name_str
                FROM public.py_unicode_object
                WHERE ob_base = v_arg_name_uuid;

                -- Set in locals (dict Base ID)
                PERFORM public.vm_dict_set_item(v_locals_base, v_arg_name_str, args[i]);
            END LOOP;
        END IF;

        -- Create Frame Object (all Base IDs)
        v_frame_id := public.vm_create_frame(
            v_code_base_id,
            v_locals_base,
            NULL,  -- globals
            NULL,  -- builtins
            p_caller_frame_id
        );

        -- Set current frame context
        PERFORM public.vm_set_current_frame(v_frame_id);

        -- Run frame with code and locals Base IDs
        v_result := public.vm_run_frame(v_code_base_id, v_locals_base, NULL, v_frame_id);

        -- Restore previous frame
        IF p_caller_frame_id IS NOT NULL THEN
            PERFORM public.vm_set_current_frame(p_caller_frame_id);
        END IF;

        RETURN v_result;
    END IF;

    -----------------------------------------------------------------
    -- 5. INSTANCE CALL (__call__)
    -----------------------------------------------------------------
    BEGIN
        v_call_method := public.vm_getattr(callable_id, '__call__');
        IF v_call_method IS NOT NULL THEN
            RETURN public.vm_call(v_call_method, args, p_caller_frame_id);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RAISE EXCEPTION 'TypeError: Object % is not callable', callable_id;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------
-- End of Migration
--------------------------------------------------------

