-- ============================================================================
-- Migration: Common Builtins (isinstance, hasattr, getattr, setattr, id)
-- + Register type objects in builtins dict
-- 20260114240358
--
-- Depends: 235000 (py_object_getattr/setattr), 240300 (py_object_istrue),
--          225000 (builtin_functions pattern)
-- ============================================================================

-- ============================================================================
-- py_builtin_isinstance(obj, classinfo) → True/False
-- Checks if obj's type matches classinfo (or any type in a tuple of types)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_builtin_isinstance(
    func_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_TRUE_OBJ   UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ  UUID := '00000000-0000-4000-b000-000000000011';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_TYPE_TYPE   UUID := '00000000-0000-4000-a000-000000000002';

    v_nargs INTEGER;
    v_obj UUID;
    v_classinfo UUID;
    v_obj_type UUID;
    v_classinfo_type UUID;
    v_tuple_items UUID[];
    i INTEGER;
    v_result BOOLEAN;

    -- For walking type hierarchy
    v_check_type UUID;
    v_bases_tuple UUID;
    v_base_items UUID[];
    j INTEGER;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);
    IF v_nargs != 2 THEN
        PERFORM public.py_err_set_type_error('isinstance expected 2 arguments, got ' || v_nargs);
        RETURN NULL;
    END IF;

    v_obj := args[1];
    v_classinfo := args[2];

    SELECT ob_type INTO v_obj_type FROM public.py_object WHERE id = v_obj;
    SELECT ob_type INTO v_classinfo_type FROM public.py_object WHERE id = v_classinfo;

    -- If classinfo is a tuple, check each element
    IF v_classinfo_type = ID_TUPLE_TYPE THEN
        SELECT ob_item INTO v_tuple_items FROM public.py_tuple_object WHERE ob_base = v_classinfo;
        FOR i IN 1..COALESCE(array_length(v_tuple_items, 1), 0) LOOP
            -- Recursive call for each element
            v_result := public.py_isinstance_check(v_obj_type, v_tuple_items[i]);
            IF v_result THEN
                RETURN ID_TRUE_OBJ;
            END IF;
        END LOOP;
        RETURN ID_FALSE_OBJ;
    END IF;

    -- classinfo must be a type
    IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = v_classinfo) THEN
        PERFORM public.py_err_set_type_error('isinstance() arg 2 must be a type or tuple of types');
        RETURN NULL;
    END IF;

    IF public.py_isinstance_check(v_obj_type, v_classinfo) THEN
        RETURN ID_TRUE_OBJ;
    ELSE
        RETURN ID_FALSE_OBJ;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Helper: check if obj_type is classinfo or a subclass of it
-- Walks tp_bases chain (depth-first)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_isinstance_check(
    obj_type UUID, classinfo UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_check_type UUID;
    v_bases_tuple UUID;
    v_base_items UUID[];
    i INTEGER;
BEGIN
    -- Direct match
    IF obj_type = classinfo THEN
        RETURN TRUE;
    END IF;

    -- Walk bases of obj_type
    SELECT tp_bases INTO v_bases_tuple FROM public.py_type_object WHERE ob_base = obj_type;
    IF v_bases_tuple IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT ob_item INTO v_base_items FROM public.py_tuple_object WHERE ob_base = v_bases_tuple;
    IF v_base_items IS NULL THEN
        RETURN FALSE;
    END IF;

    FOR i IN 1..COALESCE(array_length(v_base_items, 1), 0) LOOP
        IF public.py_isinstance_check(v_base_items[i], classinfo) THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_builtin_hasattr(obj, name) → True/False
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_builtin_hasattr(
    func_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_TRUE_OBJ  UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000011';
    ID_STR_TYPE  UUID := '00000000-0000-4000-a000-000000000003';

    v_nargs INTEGER;
    v_obj UUID;
    v_name UUID;
    v_name_type UUID;
    v_attr UUID;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);
    IF v_nargs != 2 THEN
        PERFORM public.py_err_set_type_error('hasattr expected 2 arguments, got ' || v_nargs);
        RETURN NULL;
    END IF;

    v_obj := args[1];
    v_name := args[2];

    -- name must be a string
    SELECT ob_type INTO v_name_type FROM public.py_object WHERE id = v_name;
    IF v_name_type != ID_STR_TYPE THEN
        PERFORM public.py_err_set_type_error('attribute name must be string');
        RETURN NULL;
    END IF;

    v_attr := public.py_object_getattr(v_obj, v_name);
    IF v_attr IS NOT NULL THEN
        RETURN ID_TRUE_OBJ;
    END IF;

    -- Clear any AttributeError that was set
    IF public.py_err_occurred() THEN
        PERFORM public.py_err_clear();
    END IF;
    RETURN ID_FALSE_OBJ;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_builtin_getattr(obj, name[, default]) → attribute value or default
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_builtin_getattr(
    func_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

    v_nargs INTEGER;
    v_obj UUID;
    v_name UUID;
    v_default UUID;
    v_name_type UUID;
    v_attr UUID;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);
    IF v_nargs < 2 OR v_nargs > 3 THEN
        PERFORM public.py_err_set_type_error('getattr expected 2 or 3 arguments, got ' || v_nargs);
        RETURN NULL;
    END IF;

    v_obj := args[1];
    v_name := args[2];
    IF v_nargs = 3 THEN
        v_default := args[3];
    END IF;

    -- name must be a string
    SELECT ob_type INTO v_name_type FROM public.py_object WHERE id = v_name;
    IF v_name_type != ID_STR_TYPE THEN
        PERFORM public.py_err_set_type_error('attribute name must be string');
        RETURN NULL;
    END IF;

    v_attr := public.py_object_getattr(v_obj, v_name);
    IF v_attr IS NOT NULL THEN
        RETURN v_attr;
    END IF;

    -- Attribute not found
    IF v_default IS NOT NULL THEN
        -- Clear error and return default
        IF public.py_err_occurred() THEN
            PERFORM public.py_err_clear();
        END IF;
        RETURN v_default;
    END IF;

    -- No default — let the AttributeError propagate
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_builtin_setattr(obj, name, value) → None
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_builtin_setattr(
    func_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_NONE_OBJ UUID := '00000000-0000-4000-b000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

    v_nargs INTEGER;
    v_name_type UUID;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);
    IF v_nargs != 3 THEN
        PERFORM public.py_err_set_type_error('setattr expected 3 arguments, got ' || v_nargs);
        RETURN NULL;
    END IF;

    -- name must be a string
    SELECT ob_type INTO v_name_type FROM public.py_object WHERE id = args[2];
    IF v_name_type != ID_STR_TYPE THEN
        PERFORM public.py_err_set_type_error('attribute name must be string');
        RETURN NULL;
    END IF;

    PERFORM public.py_object_setattr(args[1], args[2], args[3]);
    IF public.py_err_occurred() THEN
        RETURN NULL;
    END IF;

    RETURN ID_NONE_OBJ;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_builtin_id(obj) → int (hash of UUID as integer)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_builtin_id(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    v_hash BIGINT;
    v_result_id UUID;
BEGIN
    -- Use a stable numeric representation of the UUID
    -- Extract the first 8 bytes of the UUID as a bigint
    v_hash := ('x' || replace(obj_id::text, '-', ''))::bit(64)::bigint;

    v_result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_result_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_result_id, v_hash);
    RETURN v_result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register all new builtins in __builtins__ module dict
-- ============================================================================
DO $$
DECLARE
    -- Fixed UUIDs for new builtins
    ID_ISINSTANCE_FUNCTION UUID := '00000000-0000-4000-b000-000000000008';
    ID_HASATTR_FUNCTION    UUID := '00000000-0000-4000-b000-000000000009';
    ID_GETATTR_FUNCTION    UUID := '00000000-0000-4000-b000-00000000000a';
    ID_SETATTR_FUNCTION    UUID := '00000000-0000-4000-b000-00000000000b';
    ID_ID_FUNCTION         UUID := '00000000-0000-4000-b000-00000000000c';

    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

    -- Type object UUIDs to register in builtins
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYPE_TYPE   UUID := '00000000-0000-4000-a000-000000000002';
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_FLOAT_TYPE  UUID := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE   UUID := '00000000-0000-4000-a000-000000000013';
    ID_LIST_TYPE   UUID := '00000000-0000-4000-a000-000000000005';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';

    builtins_dict_id UUID;

    -- String name objects (for dict keys)
    str_isinstance_id UUID;
    str_hasattr_id UUID;
    str_getattr_id UUID;
    str_setattr_id UUID;
    str_id_id UUID;

    -- String name objects for type registrations
    str_int_id UUID;
    str_str_id UUID;
    str_float_id UUID;
    str_bool_id UUID;
    str_list_id UUID;
    str_tuple_id UUID;
    str_dict_id UUID;
    str_type_id UUID;
    str_object_id UUID;

    -- Doc strings
    str_doc UUID;
BEGIN
    SELECT md_dict INTO builtins_dict_id
    FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    -- ================================================================
    -- Register isinstance
    -- ================================================================
    str_isinstance_id := public.py_str_from_text('isinstance');
    str_doc := public.py_str_from_text('Return whether an object is an instance of a class or of a subclass thereof.');

    INSERT INTO public.py_object (id, ob_type) VALUES (ID_ISINSTANCE_FUNCTION, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_ISINSTANCE_FUNCTION, str_isinstance_id, 1, str_doc, NULL, ID_BUILTINS_MODULE, 'py_builtin_isinstance'::regproc);
    -- METH_VARARGS = 1

    PERFORM public.py_dict_set_item(builtins_dict_id, str_isinstance_id, ID_ISINSTANCE_FUNCTION);

    -- ================================================================
    -- Register hasattr
    -- ================================================================
    str_hasattr_id := public.py_str_from_text('hasattr');
    str_doc := public.py_str_from_text('Return whether the object has an attribute with the given name.');

    INSERT INTO public.py_object (id, ob_type) VALUES (ID_HASATTR_FUNCTION, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_HASATTR_FUNCTION, str_hasattr_id, 1, str_doc, NULL, ID_BUILTINS_MODULE, 'py_builtin_hasattr'::regproc);

    PERFORM public.py_dict_set_item(builtins_dict_id, str_hasattr_id, ID_HASATTR_FUNCTION);

    -- ================================================================
    -- Register getattr
    -- ================================================================
    str_getattr_id := public.py_str_from_text('getattr');
    str_doc := public.py_str_from_text('getattr(object, name[, default]) -> value');

    INSERT INTO public.py_object (id, ob_type) VALUES (ID_GETATTR_FUNCTION, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_GETATTR_FUNCTION, str_getattr_id, 1, str_doc, NULL, ID_BUILTINS_MODULE, 'py_builtin_getattr'::regproc);

    PERFORM public.py_dict_set_item(builtins_dict_id, str_getattr_id, ID_GETATTR_FUNCTION);

    -- ================================================================
    -- Register setattr
    -- ================================================================
    str_setattr_id := public.py_str_from_text('setattr');
    str_doc := public.py_str_from_text('Sets the named attribute on the given object to the specified value.');

    INSERT INTO public.py_object (id, ob_type) VALUES (ID_SETATTR_FUNCTION, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_SETATTR_FUNCTION, str_setattr_id, 1, str_doc, NULL, ID_BUILTINS_MODULE, 'py_builtin_setattr'::regproc);

    PERFORM public.py_dict_set_item(builtins_dict_id, str_setattr_id, ID_SETATTR_FUNCTION);

    -- ================================================================
    -- Register id
    -- ================================================================
    str_id_id := public.py_str_from_text('id');
    str_doc := public.py_str_from_text('Return the identity of an object.');

    INSERT INTO public.py_object (id, ob_type) VALUES (ID_ID_FUNCTION, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_ID_FUNCTION, str_id_id, 8, str_doc, NULL, ID_BUILTINS_MODULE, 'py_builtin_id'::regproc);
    -- METH_O = 8

    PERFORM public.py_dict_set_item(builtins_dict_id, str_id_id, ID_ID_FUNCTION);

    -- ================================================================
    -- Register builtin type objects in builtins dict
    -- so int(x), str(x), etc. resolve via LOAD_NAME → builtins lookup
    -- ================================================================
    str_int_id := public.py_str_from_text('int');
    PERFORM public.py_dict_set_item(builtins_dict_id, str_int_id, ID_INT_TYPE);

    str_str_id := public.py_str_from_text('str');
    PERFORM public.py_dict_set_item(builtins_dict_id, str_str_id, ID_STR_TYPE);

    str_float_id := public.py_str_from_text('float');
    PERFORM public.py_dict_set_item(builtins_dict_id, str_float_id, ID_FLOAT_TYPE);

    str_bool_id := public.py_str_from_text('bool');
    PERFORM public.py_dict_set_item(builtins_dict_id, str_bool_id, ID_BOOL_TYPE);

    str_list_id := public.py_str_from_text('list');
    PERFORM public.py_dict_set_item(builtins_dict_id, str_list_id, ID_LIST_TYPE);

    str_tuple_id := public.py_str_from_text('tuple');
    PERFORM public.py_dict_set_item(builtins_dict_id, str_tuple_id, ID_TUPLE_TYPE);

    str_dict_id := public.py_str_from_text('dict');
    PERFORM public.py_dict_set_item(builtins_dict_id, str_dict_id, ID_DICT_TYPE);

    str_type_id := public.py_str_from_text('type');
    PERFORM public.py_dict_set_item(builtins_dict_id, str_type_id, ID_TYPE_TYPE);

    str_object_id := public.py_str_from_text('object');
    PERFORM public.py_dict_set_item(builtins_dict_id, str_object_id, ID_OBJECT_TYPE);
END $$;
