-- ============================================================================
-- Migration: py_type_tp_call — Make type objects callable
-- 20260114240356
--
-- In CPython, type.__call__(cls, *args, **kwargs) handles:
--   1. type(x) — 1-arg form: return type of x
--   2. type(name, bases, dict) — 3-arg form: create new type
--   3. int/str/float/bool/list/tuple/dict(*args) — builtin type constructors
--   4. Foo(*args) — user-defined class instance creation: create instance, call __init__
--
-- This is the tp_call registered on the 'type' metaclass. Since all types
-- (both builtin and user-defined) have ob_type = type, calling ANY type goes
-- through this function. Builtin types dispatch to their constructor functions;
-- user-defined types create instances with __init__.
--
-- Depends: 234000 (tp_call_slot), 240355 (build_class), 235000 (tp_hash_slot)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_type_tp_call(
    type_obj UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_TYPE_TYPE   UUID := '00000000-0000-4000-a000-000000000002';
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE    UUID := '00000000-0000-4000-a000-000000000003';
    ID_FLOAT_TYPE  UUID := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE   UUID := '00000000-0000-4000-a000-000000000013';
    ID_LIST_TYPE   UUID := '00000000-0000-4000-a000-000000000005';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';
    ID_NONE_OBJ    UUID := '00000000-0000-4000-b000-000000000001';

    v_nargs INTEGER;

    -- For type(x) — 1-arg form
    v_result_type UUID;

    -- For type(name, bases, dict) — 3-arg form
    v_name_obj UUID;
    v_name_str TEXT;
    v_bases_obj UUID;
    v_dict_obj UUID;
    v_new_type_id UUID;

    -- For instance creation
    v_instance_id UUID;
    v_instance_dict_id UUID;
    v_init_name_id UUID;
    v_init_func_id UUID;
    v_init_args UUID[];
    v_init_result UUID;
    i INTEGER;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);

    -- ====================================================================
    -- Case 1: type(x) — return the type of x
    -- Only when type_obj IS the type metaclass itself (not a subclass call)
    -- ====================================================================
    IF type_obj = ID_TYPE_TYPE AND v_nargs = 1 AND kwargs_id IS NULL THEN
        SELECT ob_type INTO v_result_type FROM public.py_object WHERE id = args[1];
        IF v_result_type IS NULL THEN
            PERFORM public.py_err_set_type_error('type() argument has no type');
            RETURN NULL;
        END IF;
        RETURN v_result_type;
    END IF;

    -- ====================================================================
    -- Case 2: type(name, bases, dict) — create a new type dynamically
    -- Only when type_obj IS the type metaclass itself
    -- ====================================================================
    IF type_obj = ID_TYPE_TYPE AND v_nargs = 3 THEN
        v_name_obj := args[1];
        v_bases_obj := args[2];
        v_dict_obj := args[3];

        SELECT str_value INTO v_name_str FROM public.py_unicode_object WHERE ob_base = v_name_obj;
        IF v_name_str IS NULL THEN
            PERFORM public.py_err_set_type_error('type() argument 1 must be str');
            RETURN NULL;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM public.py_tuple_object WHERE ob_base = v_bases_obj) THEN
            PERFORM public.py_err_set_type_error('type() argument 2 must be tuple');
            RETURN NULL;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM public.py_dict_object WHERE ob_base = v_dict_obj) THEN
            PERFORM public.py_err_set_type_error('type() argument 3 must be dict');
            RETURN NULL;
        END IF;

        v_new_type_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (v_new_type_id, ID_TYPE_TYPE);
        INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
        VALUES (v_new_type_id, v_name_str, v_bases_obj, v_dict_obj);

        RETURN v_new_type_id;
    END IF;

    -- ====================================================================
    -- Case 3: Builtin type constructors
    -- Dispatch to the specific constructor function for builtin types.
    -- These are defined in 240357_builtin_type_constructors.sql.
    -- ====================================================================
    IF type_obj = ID_INT_TYPE THEN
        RETURN public.py_int_tp_call(type_obj, args, kwargs_id);
    ELSIF type_obj = ID_STR_TYPE THEN
        RETURN public.py_str_tp_call(type_obj, args, kwargs_id);
    ELSIF type_obj = ID_FLOAT_TYPE THEN
        RETURN public.py_float_tp_call(type_obj, args, kwargs_id);
    ELSIF type_obj = ID_BOOL_TYPE THEN
        RETURN public.py_bool_tp_call(type_obj, args, kwargs_id);
    ELSIF type_obj = ID_LIST_TYPE THEN
        RETURN public.py_list_tp_call(type_obj, args, kwargs_id);
    ELSIF type_obj = ID_TUPLE_TYPE THEN
        RETURN public.py_tuple_tp_call(type_obj, args, kwargs_id);
    ELSIF type_obj = ID_DICT_TYPE THEN
        RETURN public.py_dict_tp_call(type_obj, args, kwargs_id);
    END IF;

    -- ====================================================================
    -- Case 4: User-defined class instance creation — Foo(*args)
    -- type_obj is a type (has py_type_object row), create an instance of it
    -- ====================================================================
    IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = type_obj) THEN
        PERFORM public.py_err_set_type_error('cannot create instance: not a type');
        RETURN NULL;
    END IF;

    -- Create the instance object
    v_instance_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_instance_id, type_obj);

    -- Create instance __dict__
    v_instance_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_instance_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (v_instance_dict_id);
    INSERT INTO public.py_instance_object (ob_base, in_dict) VALUES (v_instance_id, v_instance_dict_id);

    -- Look up __init__ in the type's MRO
    v_init_name_id := public.py_str_from_text('__init__');
    v_init_func_id := public.lookup_attr_in_type_and_bases(type_obj, v_init_name_id);

    IF v_init_func_id IS NOT NULL THEN
        -- Build args for __init__: (instance, *original_args)
        v_init_args := ARRAY[v_instance_id];
        FOR i IN 1..v_nargs LOOP
            v_init_args := array_append(v_init_args, args[i]);
        END LOOP;

        -- Call __init__
        v_init_result := public.py_object_call(v_init_func_id, v_init_args, kwargs_id);
        IF public.py_err_occurred() THEN
            RETURN NULL;
        END IF;
    END IF;

    RETURN v_instance_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register tp_call on the 'type' type so type objects are callable
-- ============================================================================
DO $$
DECLARE
    ID_TYPE_TYPE UUID := '00000000-0000-4000-a000-000000000002';
BEGIN
    UPDATE public.py_type_object
    SET tp_call = 'py_type_tp_call'::regproc
    WHERE ob_base = ID_TYPE_TYPE;
END $$;
