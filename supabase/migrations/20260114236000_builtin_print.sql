-- ============================================================================
-- Migration: print() Builtin + py_object_str() Dispatcher
-- Created: 2026-01-14 22:51:00
--
-- Purpose:
--   Implements py_object_str() which converts any Python object to its string
--   representation (equivalent to CPython's PyObject_Str / tp_str).
--   Then implements print() builtin which joins args with ' ', outputs via
--   RAISE NOTICE (PostgreSQL equivalent of stdout), and returns None.
--
-- Depends: 225000 (builtin_functions), 223000 (bootstrap), 224300 (exception_setters)
-- ============================================================================

-- ============================================================================
-- py_object_str: Convert any Python object to its string representation
-- Returns a UUID to a new py_unicode_object, or the same object if already str.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_object_str(obj_id UUID)
RETURNS UUID AS $$
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
    v_str TEXT;
    v_int_val NUMERIC;
    v_float_val DOUBLE PRECISION;
    v_bool_val BOOLEAN;
    v_items UUID[];
    v_parts TEXT[];
    v_elem_str UUID;
    v_elem_text TEXT;
    i INTEGER;

    -- dict iteration
    v_keys UUID[];
    v_key UUID;
    v_value UUID;
    v_key_repr TEXT;
    v_val_repr TEXT;
BEGIN
    IF obj_id IS NULL THEN
        RETURN public.py_str_from_text('None');
    END IF;

    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = obj_id;

    -- str: return as-is
    IF v_type_id = ID_STR_TYPE THEN
        RETURN obj_id;
    END IF;

    -- bool: 'True' or 'False' (must check before int since bool subclasses int)
    IF v_type_id = ID_BOOL_TYPE THEN
        SELECT bool_value INTO v_bool_val FROM public.py_bool_object WHERE ob_base = obj_id;
        IF v_bool_val THEN
            RETURN public.py_str_from_text('True');
        ELSE
            RETURN public.py_str_from_text('False');
        END IF;
    END IF;

    -- int
    IF v_type_id = ID_INT_TYPE THEN
        SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = obj_id;
        RETURN public.py_str_from_text(v_int_val::text);
    END IF;

    -- float
    IF v_type_id = ID_FLOAT_TYPE THEN
        SELECT ob_fval INTO v_float_val FROM public.py_float_object WHERE ob_base = obj_id;
        -- CPython repr: use %g-like formatting
        IF v_float_val = floor(v_float_val) AND v_float_val < 1e16 AND v_float_val > -1e16 THEN
            RETURN public.py_str_from_text(v_float_val::bigint::text || '.0');
        ELSE
            RETURN public.py_str_from_text(v_float_val::text);
        END IF;
    END IF;

    -- NoneType
    IF v_type_id = ID_NONE_TYPE THEN
        RETURN public.py_str_from_text('None');
    END IF;

    -- list: [repr(elem), ...]
    IF v_type_id = ID_LIST_TYPE THEN
        SELECT ob_item INTO v_items FROM public.py_list_object WHERE ob_base = obj_id;
        v_parts := ARRAY[]::text[];
        FOR i IN 1..COALESCE(array_length(v_items, 1), 0) LOOP
            v_elem_str := public.py_object_repr(v_items[i]);
            SELECT str_value INTO v_elem_text FROM public.py_unicode_object WHERE ob_base = v_elem_str;
            v_parts := array_append(v_parts, COALESCE(v_elem_text, '???'));
        END LOOP;
        RETURN public.py_str_from_text('[' || array_to_string(v_parts, ', ') || ']');
    END IF;

    -- tuple: (repr(elem), ...)
    IF v_type_id = ID_TUPLE_TYPE THEN
        SELECT ob_item INTO v_items FROM public.py_tuple_object WHERE ob_base = obj_id;
        v_parts := ARRAY[]::text[];
        FOR i IN 1..COALESCE(array_length(v_items, 1), 0) LOOP
            v_elem_str := public.py_object_repr(v_items[i]);
            SELECT str_value INTO v_elem_text FROM public.py_unicode_object WHERE ob_base = v_elem_str;
            v_parts := array_append(v_parts, COALESCE(v_elem_text, '???'));
        END LOOP;
        IF array_length(v_parts, 1) = 1 THEN
            RETURN public.py_str_from_text('(' || v_parts[1] || ',)');
        ELSE
            RETURN public.py_str_from_text('(' || array_to_string(v_parts, ', ') || ')');
        END IF;
    END IF;

    -- dict: {repr(key): repr(value), ...}
    IF v_type_id = ID_DICT_TYPE THEN
        v_parts := ARRAY[]::text[];
        FOR v_key, v_value IN
            SELECT me_key, me_value FROM public.py_dict_entry WHERE dict_id = obj_id ORDER BY id
        LOOP
            v_elem_str := public.py_object_repr(v_key);
            SELECT str_value INTO v_key_repr FROM public.py_unicode_object WHERE ob_base = v_elem_str;
            v_elem_str := public.py_object_repr(v_value);
            SELECT str_value INTO v_val_repr FROM public.py_unicode_object WHERE ob_base = v_elem_str;
            v_parts := array_append(v_parts, COALESCE(v_key_repr, '???') || ': ' || COALESCE(v_val_repr, '???'));
        END LOOP;
        RETURN public.py_str_from_text('{' || array_to_string(v_parts, ', ') || '}');
    END IF;

    -- Fallback: <type_name object>
    DECLARE
        v_tp_name TEXT;
    BEGIN
        SELECT tp_name INTO v_tp_name FROM public.py_type_object WHERE ob_base = v_type_id;
        RETURN public.py_str_from_text('<' || COALESCE(v_tp_name, 'object') || ' object>');
    END;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_object_repr: Like py_object_str but adds quotes around strings
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_object_repr(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    v_type_id UUID;
    v_str_val TEXT;
BEGIN
    IF obj_id IS NULL THEN
        RETURN public.py_str_from_text('None');
    END IF;

    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = obj_id;

    -- str: add quotes
    IF v_type_id = ID_STR_TYPE THEN
        SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = obj_id;
        RETURN public.py_str_from_text('''' || COALESCE(v_str_val, '') || '''');
    END IF;

    -- Everything else: same as str()
    RETURN public.py_object_str(obj_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_builtin_print: print(*args, sep=' ', end='\n')
-- METH_VARARGS|METH_KEYWORDS (0x0001|0x0002 = 3)
-- Outputs via RAISE NOTICE. Returns None.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_builtin_print(
    func_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_NONE_OBJ UUID := '00000000-0000-4000-b000-000000000001';
    v_parts TEXT[];
    v_str_id UUID;
    v_str_val TEXT;
    i INTEGER;
    v_output TEXT;
BEGIN
    v_parts := ARRAY[]::text[];

    IF args IS NOT NULL THEN
        FOR i IN 1..COALESCE(array_length(args, 1), 0) LOOP
            v_str_id := public.py_object_str(args[i]);
            SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_str_id;
            v_parts := array_append(v_parts, COALESCE(v_str_val, ''));
        END LOOP;
    END IF;

    v_output := array_to_string(v_parts, ' ');
    RAISE NOTICE '%', v_output;

    RETURN ID_NONE_OBJ;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register print in __builtins__ module
-- ============================================================================
DO $$
DECLARE
    ID_PRINT_FUNCTION UUID := '00000000-0000-4000-b000-000000000005';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

    builtins_dict_id UUID;
    str_name_id UUID;
    str_doc_id UUID;
BEGIN
    SELECT md_dict INTO builtins_dict_id
    FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    -- Create name and doc strings
    str_name_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_name_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_name_id, 'print');

    str_doc_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_doc_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_doc_id, 'Prints the values to sys.stdout.');

    -- Create print function object
    INSERT INTO public.py_object (id, ob_type) VALUES (ID_PRINT_FUNCTION, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_PRINT_FUNCTION, str_name_id, 3, str_doc_id, NULL, ID_BUILTINS_MODULE, 'py_builtin_print'::regproc);

    -- Register in builtins dict
    PERFORM public.py_dict_set_item(builtins_dict_id, str_name_id, ID_PRINT_FUNCTION);
END $$;
