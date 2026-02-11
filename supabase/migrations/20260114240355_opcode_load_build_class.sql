-- ============================================================================
-- Migration: LOAD_BUILD_CLASS (71) + __build_class__ + type() 3-arg form
-- 20260114240355
--
-- LOAD_BUILD_CLASS: Pushes __build_class__ builtin onto stack.
--
-- __build_class__(body_func, name, *bases):
--   1. Create empty namespace dict
--   2. Execute body_func with namespace as f_locals
--   3. Call metaclass(name, bases, namespace) to create class
--
-- type(name, bases, dict) — 3-arg form:
--   Creates a new type object with the given name, bases tuple, and dict.
--
-- Depends: ceval_core, tp_call_slot, bootstrap
-- ============================================================================

-- ============================================================================
-- py_builtin_build_class: __build_class__(body_func, name, *bases)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_builtin_build_class(
    func_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_TYPE_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';

    v_nargs INTEGER;
    v_body_func UUID;
    v_name_obj UUID;
    v_name_str TEXT;
    v_bases UUID[];
    v_bases_tuple_id UUID;
    v_namespace_id UUID;
    v_builtins_dict_id UUID;

    -- For executing body function
    v_func_code UUID;
    v_func_globals UUID;
    v_frame_id UUID;
    v_locals_id UUID;
    v_dummy_result UUID;

    -- For creating the class
    v_new_type_id UUID;
    v_new_dict_id UUID;
    v_tp_bases_id UUID;
    i INTEGER;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);
    IF v_nargs < 2 THEN
        PERFORM public.py_err_set_type_error('__build_class__: not enough arguments');
        RETURN NULL;
    END IF;

    v_body_func := args[1];
    v_name_obj := args[2];

    SELECT str_value INTO v_name_str FROM public.py_unicode_object WHERE ob_base = v_name_obj;
    IF v_name_str IS NULL THEN
        PERFORM public.py_err_set_type_error('__build_class__: name must be a string');
        RETURN NULL;
    END IF;

    -- Collect bases (args[3..])
    v_bases := ARRAY[]::uuid[];
    FOR i IN 3..v_nargs LOOP
        v_bases := array_append(v_bases, args[i]);
    END LOOP;

    -- If no bases specified, default to (object,)
    IF array_length(v_bases, 1) IS NULL OR array_length(v_bases, 1) = 0 THEN
        v_bases := ARRAY[ID_OBJECT_TYPE];
    END IF;

    -- Create bases tuple
    v_bases_tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_bases_tuple_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (v_bases_tuple_id, v_bases);

    -- Create empty namespace dict
    v_namespace_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_namespace_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (v_namespace_id);

    -- Execute body function with namespace as f_locals
    SELECT func_code, func_globals INTO v_func_code, v_func_globals
    FROM public.py_function_object WHERE ob_base = v_body_func;

    IF v_func_code IS NULL THEN
        PERFORM public.py_err_set_type_error('__build_class__: body is not a function');
        RETURN NULL;
    END IF;

    SELECT md_dict INTO v_builtins_dict_id
    FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;
    IF v_builtins_dict_id IS NULL THEN
        v_builtins_dict_id := v_func_globals;
    END IF;

    v_frame_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_frame_id, ID_OBJECT_TYPE);
    INSERT INTO public.py_frame_object (ob_base, f_code, f_globals, f_locals, f_builtins)
    VALUES (v_frame_id, v_func_code, v_func_globals, v_namespace_id, v_builtins_dict_id);

    -- Execute body — ignore return value (body should populate namespace via STORE_NAME)
    v_dummy_result := public.py_eval_frame(
      current_setting('elytra.thread_state_id')::uuid,
      v_frame_id
    );
    IF public.py_err_occurred() THEN
        RETURN NULL;
    END IF;

    -- Create the new type: type(name, bases, namespace)
    -- Create new dict for tp_dict (copy from namespace)
    v_new_dict_id := v_namespace_id; -- Reuse namespace as tp_dict

    -- Create new type object
    v_new_type_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_new_type_id, ID_TYPE_TYPE);
    INSERT INTO public.py_type_object (ob_base, tp_name, tp_bases, tp_dict)
    VALUES (v_new_type_id, v_name_str, v_bases_tuple_id, v_new_dict_id);

    RETURN v_new_type_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register __build_class__ in builtins
-- ============================================================================
DO $$
DECLARE
    ID_BUILD_CLASS_FUNCTION UUID := '00000000-0000-4000-b000-000000000007';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

    builtins_dict_id UUID;
    str_name_id UUID;
    str_doc_id UUID;
BEGIN
    SELECT md_dict INTO builtins_dict_id
    FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    str_name_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_name_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_name_id, '__build_class__');

    str_doc_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_doc_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_doc_id, '__build_class__(func, name, /, *bases) -> class');

    INSERT INTO public.py_object (id, ob_type) VALUES (ID_BUILD_CLASS_FUNCTION, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_BUILD_CLASS_FUNCTION, str_name_id, 1, str_doc_id, NULL, ID_BUILTINS_MODULE, 'py_builtin_build_class'::regproc);

    PERFORM public.py_dict_set_item(builtins_dict_id, str_name_id, ID_BUILD_CLASS_FUNCTION);
END $$;

-- ============================================================================
-- LOAD_BUILD_CLASS opcode (71): Push __build_class__ onto stack
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_BUILD_CLASS(frame_id UUID)
RETURNS VOID AS $$
DECLARE
    ID_BUILD_CLASS_FUNCTION UUID := '00000000-0000-4000-b000-000000000007';
BEGIN
    PERFORM public.py_stack_push(frame_id, ID_BUILD_CLASS_FUNCTION);
END;
$$ LANGUAGE plpgsql;
