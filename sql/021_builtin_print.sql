-- ============================================================================
-- Migration: print() Builtin + py_object_str() / py_object_repr() Dispatchers
-- Created: 2026-01-14 22:51:00
--
-- Purpose:
--   Implements type-specific tp_str/tp_repr handler functions, then
--   py_object_str() and py_object_repr() which dispatch through the
--   tp_str/tp_repr slots on py_type_object (matching CPython's PyObject_Str
--   and PyObject_Repr). Also implements print() builtin.
--
-- Depends: 225000 (builtin_functions), 223000 (bootstrap), 224300 (exception_setters)
-- ============================================================================

-- ============================================================================
-- Type-specific tp_str handlers
-- Signature: (obj_id UUID) RETURNS UUID (a py_unicode_object)
-- ============================================================================

-- str.__str__: return self
CREATE OR REPLACE FUNCTION public.py_unicode_tp_str(obj_id UUID)
RETURNS UUID AS $$
BEGIN
    RETURN obj_id;
END;
$$ LANGUAGE plpgsql;

-- bool.__repr__ / bool.__str__: 'True' or 'False'
CREATE OR REPLACE FUNCTION public.py_bool_tp_repr(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    v_bool_val BOOLEAN;
BEGIN
    SELECT bool_value INTO v_bool_val FROM public.py_bool_object WHERE ob_base = obj_id;
    IF v_bool_val THEN
        RETURN public.py_str_from_text('True');
    ELSE
        RETURN public.py_str_from_text('False');
    END IF;
END;
$$ LANGUAGE plpgsql;

-- int.__repr__ / int.__str__: decimal text
CREATE OR REPLACE FUNCTION public.py_long_tp_repr(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    v_int_val NUMERIC;
BEGIN
    SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = obj_id;
    RETURN public.py_str_from_text(v_int_val::text);
END;
$$ LANGUAGE plpgsql;

-- float.__repr__ / float.__str__: CPython %g-like formatting
CREATE OR REPLACE FUNCTION public.py_float_tp_repr(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    v_float_val DOUBLE PRECISION;
BEGIN
    SELECT ob_fval INTO v_float_val FROM public.py_float_object WHERE ob_base = obj_id;
    IF v_float_val = floor(v_float_val) AND v_float_val < 1e16 AND v_float_val > -1e16 THEN
        RETURN public.py_str_from_text(v_float_val::bigint::text || '.0');
    ELSE
        RETURN public.py_str_from_text(v_float_val::text);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- NoneType.__repr__ / NoneType.__str__: 'None'
CREATE OR REPLACE FUNCTION public.py_none_tp_repr(obj_id UUID)
RETURNS UUID AS $$
BEGIN
    RETURN public.py_str_from_text('None');
END;
$$ LANGUAGE plpgsql;

-- str.__repr__: add quotes
CREATE OR REPLACE FUNCTION public.py_unicode_tp_repr(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    v_str_val TEXT;
BEGIN
    SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = obj_id;
    RETURN public.py_str_from_text('''' || COALESCE(v_str_val, '') || '''');
END;
$$ LANGUAGE plpgsql;

-- list.__repr__ / list.__str__: [repr(elem), ...]
CREATE OR REPLACE FUNCTION public.py_list_tp_repr(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    v_items UUID[];
    v_parts TEXT[];
    v_elem_str UUID;
    v_elem_text TEXT;
    i INTEGER;
BEGIN
    SELECT ob_item INTO v_items FROM public.py_list_object WHERE ob_base = obj_id;
    v_parts := ARRAY[]::text[];
    FOR i IN 1..COALESCE(array_length(v_items, 1), 0) LOOP
        v_elem_str := public.py_object_repr(v_items[i]);
        SELECT str_value INTO v_elem_text FROM public.py_unicode_object WHERE ob_base = v_elem_str;
        v_parts := array_append(v_parts, COALESCE(v_elem_text, '???'));
    END LOOP;
    RETURN public.py_str_from_text('[' || array_to_string(v_parts, ', ') || ']');
END;
$$ LANGUAGE plpgsql;

-- tuple.__repr__ / tuple.__str__: (repr(elem), ...)
CREATE OR REPLACE FUNCTION public.py_tuple_tp_repr(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    v_items UUID[];
    v_parts TEXT[];
    v_elem_str UUID;
    v_elem_text TEXT;
    i INTEGER;
BEGIN
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
END;
$$ LANGUAGE plpgsql;

-- dict.__repr__ / dict.__str__: {repr(key): repr(value), ...}
CREATE OR REPLACE FUNCTION public.py_dict_tp_repr(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    v_parts TEXT[];
    v_key UUID;
    v_value UUID;
    v_elem_str UUID;
    v_key_repr TEXT;
    v_val_repr TEXT;
BEGIN
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
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_object_repr: Dispatch through tp_repr slot (CPython PyObject_Repr)
-- CPython: tp_repr → if NULL, return '<type object>'
-- Defined BEFORE py_object_str because str falls back to repr.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_object_repr(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    v_type_id UUID;
    v_tp_repr regproc;
    v_result UUID;
    v_tp_name TEXT;
BEGIN
    IF obj_id IS NULL THEN
        RETURN public.py_str_from_text('None');
    END IF;

    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = obj_id;

    -- Look up tp_repr on the type
    SELECT tp_repr INTO v_tp_repr FROM public.py_type_object WHERE ob_base = v_type_id;

    IF v_tp_repr IS NOT NULL THEN
        EXECUTE format('SELECT %I($1)', v_tp_repr) USING obj_id INTO v_result;
        RETURN v_result;
    END IF;

    -- Fallback: <type_name object> (CPython uses <type at 0xaddr>; we omit address)
    SELECT tp_name INTO v_tp_name FROM public.py_type_object WHERE ob_base = v_type_id;
    RETURN public.py_str_from_text('<' || COALESCE(v_tp_name, 'object') || ' object>');
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_object_str: Dispatch through tp_str slot (CPython PyObject_Str)
-- CPython: tp_str → if NULL, fallback to PyObject_Repr()
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_object_str(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    v_type_id UUID;
    v_tp_str regproc;
    v_result UUID;
BEGIN
    IF obj_id IS NULL THEN
        RETURN public.py_str_from_text('None');
    END IF;

    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = obj_id;

    -- Look up tp_str on the type
    SELECT tp_str INTO v_tp_str FROM public.py_type_object WHERE ob_base = v_type_id;

    IF v_tp_str IS NOT NULL THEN
        EXECUTE format('SELECT %I($1)', v_tp_str) USING obj_id INTO v_result;
        RETURN v_result;
    END IF;

    -- Fallback: CPython calls PyObject_Repr(v) when tp_str is NULL
    RETURN public.py_object_repr(obj_id);
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
-- Register tp_str / tp_repr slots for builtin types
-- ============================================================================
DO $$
DECLARE
    ID_STR_TYPE   UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE   UUID := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE  UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE  UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_NONE_TYPE  UUID := '00000000-0000-4000-a000-000000000008';
    ID_FLOAT_TYPE UUID := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE  UUID := '00000000-0000-4000-a000-000000000013';
BEGIN
    -- str: only type that defines tp_str (returns self). tp_repr adds quotes.
    -- CPython: PyUnicode_Type.tp_str = PyObject_Str, tp_repr = unicode_repr
    UPDATE public.py_type_object
    SET tp_str = 'py_unicode_tp_str'::regproc, tp_repr = 'py_unicode_tp_repr'::regproc
    WHERE ob_base = ID_STR_TYPE;

    -- All other builtins: tp_str = NULL (fallback to repr), tp_repr only.
    -- This matches CPython where int/float/bool/None/list/tuple/dict all have tp_str = NULL.
    UPDATE public.py_type_object SET tp_repr = 'py_long_tp_repr'::regproc
    WHERE ob_base = ID_INT_TYPE;

    UPDATE public.py_type_object SET tp_repr = 'py_float_tp_repr'::regproc
    WHERE ob_base = ID_FLOAT_TYPE;

    UPDATE public.py_type_object SET tp_repr = 'py_bool_tp_repr'::regproc
    WHERE ob_base = ID_BOOL_TYPE;

    UPDATE public.py_type_object SET tp_repr = 'py_none_tp_repr'::regproc
    WHERE ob_base = ID_NONE_TYPE;

    UPDATE public.py_type_object SET tp_repr = 'py_list_tp_repr'::regproc
    WHERE ob_base = ID_LIST_TYPE;

    UPDATE public.py_type_object SET tp_repr = 'py_tuple_tp_repr'::regproc
    WHERE ob_base = ID_TUPLE_TYPE;

    UPDATE public.py_type_object SET tp_repr = 'py_dict_tp_repr'::regproc
    WHERE ob_base = ID_DICT_TYPE;
END $$;

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
