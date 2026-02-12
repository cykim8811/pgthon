-- ============================================================================
-- Migration: Subscript Slots + Opcode BINARY_SUBSCR (25) — CPython 3.11
-- 20260114240342
--
-- Defines type-specific mp_subscript/mp_ass_subscript handlers, dispatch
-- functions (py_object_getitem/setitem/delitem), registers slots, then
-- defines the BINARY_SUBSCR opcode.
--
-- Stack: ..., obj, key → ..., result. obj[key].
-- Depends: ceval_core, type_method_slots (226000), tp_hash_slot (235000).
-- ============================================================================

-- ============================================================================
-- Type-specific mp_subscript handlers
-- Signature: (obj_id UUID, key_id UUID) RETURNS UUID
-- ============================================================================

-- tuple.__getitem__
CREATE OR REPLACE FUNCTION public.py_tuple_mp_subscript(obj_id UUID, key_id UUID)
RETURNS UUID AS $$
DECLARE
    items UUID[];
    seq_len INTEGER;
    idx INTEGER;
    key_val NUMERIC;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = key_id) THEN
        PERFORM public.py_err_set_type_error('tuple indices must be integers or slices, not type');
        RETURN NULL;
    END IF;
    SELECT long_value INTO key_val FROM public.py_long_object WHERE ob_base = key_id;
    idx := key_val::INTEGER;
    SELECT ob_item INTO items FROM public.py_tuple_object WHERE ob_base = obj_id;
    IF items IS NULL THEN items := array[]::uuid[]; END IF;
    seq_len := COALESCE(array_length(items, 1), 0);
    IF idx < 0 THEN idx := idx + seq_len; END IF;
    IF idx < 0 OR idx >= seq_len THEN
        PERFORM public.py_err_set_index_error('tuple index out of range');
        RETURN NULL;
    END IF;
    RETURN items[idx + 1];
END;
$$ LANGUAGE plpgsql;

-- list.__getitem__
CREATE OR REPLACE FUNCTION public.py_list_mp_subscript(obj_id UUID, key_id UUID)
RETURNS UUID AS $$
DECLARE
    items UUID[];
    seq_len INTEGER;
    idx INTEGER;
    key_val NUMERIC;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = key_id) THEN
        PERFORM public.py_err_set_type_error('list indices must be integers or slices, not type');
        RETURN NULL;
    END IF;
    SELECT long_value INTO key_val FROM public.py_long_object WHERE ob_base = key_id;
    idx := key_val::INTEGER;
    SELECT ob_item INTO items FROM public.py_list_object WHERE ob_base = obj_id;
    IF items IS NULL THEN items := array[]::uuid[]; END IF;
    seq_len := COALESCE(array_length(items, 1), 0);
    IF idx < 0 THEN idx := idx + seq_len; END IF;
    IF idx < 0 OR idx >= seq_len THEN
        PERFORM public.py_err_set_index_error('list index out of range');
        RETURN NULL;
    END IF;
    RETURN items[idx + 1];
END;
$$ LANGUAGE plpgsql;

-- dict.__getitem__
CREATE OR REPLACE FUNCTION public.py_dict_mp_subscript(obj_id UUID, key_id UUID)
RETURNS UUID AS $$
DECLARE
    result_id UUID;
BEGIN
    result_id := public.py_dict_get_item(obj_id, key_id);
    IF result_id IS NULL AND public.py_err_occurred() THEN
        RETURN NULL;
    END IF;
    IF result_id IS NULL THEN
        PERFORM public.py_err_set_key_error('key not found');
        RETURN NULL;
    END IF;
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Type-specific mp_ass_subscript handlers
-- Signature: (obj_id UUID, key_id UUID, value_id UUID) RETURNS UUID
-- Convention: value_id = NULL means delete; otherwise set.
-- Returns NULL on success (no meaningful return), sets error on failure.
-- ============================================================================

-- list.__setitem__ / list.__delitem__
CREATE OR REPLACE FUNCTION public.py_list_mp_ass_subscript(obj_id UUID, key_id UUID, value_id UUID)
RETURNS UUID AS $$
DECLARE
    items UUID[];
    seq_len INTEGER;
    idx INTEGER;
    key_val NUMERIC;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = key_id) THEN
        PERFORM public.py_err_set_type_error('list indices must be integers or slices, not type');
        RETURN NULL;
    END IF;
    SELECT long_value INTO key_val FROM public.py_long_object WHERE ob_base = key_id;
    idx := key_val::INTEGER;
    SELECT ob_item INTO items FROM public.py_list_object WHERE ob_base = obj_id;
    IF items IS NULL THEN items := array[]::uuid[]; END IF;
    seq_len := COALESCE(array_length(items, 1), 0);
    IF idx < 0 THEN idx := idx + seq_len; END IF;
    IF idx < 0 OR idx >= seq_len THEN
        PERFORM public.py_err_set_index_error('list assignment index out of range');
        RETURN NULL;
    END IF;
    IF value_id IS NULL THEN
        -- delete
        items := items[1:idx] || COALESCE(items[(idx+2):seq_len], array[]::uuid[]);
    ELSE
        -- set
        items[idx + 1] := value_id;
    END IF;
    UPDATE public.py_list_object SET ob_item = items WHERE ob_base = obj_id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- dict.__setitem__ / dict.__delitem__
CREATE OR REPLACE FUNCTION public.py_dict_mp_ass_subscript(obj_id UUID, key_id UUID, value_id UUID)
RETURNS UUID AS $$
DECLARE
    deleted BOOLEAN;
BEGIN
    IF value_id IS NULL THEN
        -- delete
        deleted := public.py_dict_del_item(obj_id, key_id);
        IF NOT deleted THEN
            PERFORM public.py_err_set_key_error('key not found');
        END IF;
    ELSE
        -- set
        PERFORM public.py_dict_set_item(obj_id, key_id, value_id);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Dispatch functions: py_object_getitem / py_object_setitem / py_object_delitem
-- CPython: PyObject_GetItem, PyObject_SetItem, PyObject_DelItem
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_getitem(obj_id UUID, key_id UUID)
RETURNS UUID AS $$
DECLARE
    v_type_id UUID;
    v_map_id UUID;
    v_mp_sub regproc;
    v_result UUID;
    v_tp_name TEXT;
BEGIN
    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = obj_id;

    -- Check tp_as_mapping → mp_subscript
    SELECT tp_as_mapping INTO v_map_id FROM public.py_type_object WHERE ob_base = v_type_id;
    IF v_map_id IS NOT NULL THEN
        SELECT mp_subscript INTO v_mp_sub FROM public.py_mapping_methods WHERE id = v_map_id;
        IF v_mp_sub IS NOT NULL THEN
            EXECUTE format('SELECT %I($1, $2)', v_mp_sub) USING obj_id, key_id INTO v_result;
            RETURN v_result;
        END IF;
    END IF;

    SELECT tp_name INTO v_tp_name FROM public.py_type_object WHERE ob_base = v_type_id;
    PERFORM public.py_err_set_type_error('''' || COALESCE(v_tp_name, 'unknown') || ''' object is not subscriptable');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_setitem(obj_id UUID, key_id UUID, value_id UUID)
RETURNS void AS $$
DECLARE
    v_type_id UUID;
    v_map_id UUID;
    v_mp_ass regproc;
    v_tp_name TEXT;
    v_dummy UUID;
BEGIN
    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = obj_id;

    -- Check tp_as_mapping → mp_ass_subscript
    SELECT tp_as_mapping INTO v_map_id FROM public.py_type_object WHERE ob_base = v_type_id;
    IF v_map_id IS NOT NULL THEN
        SELECT mp_ass_subscript INTO v_mp_ass FROM public.py_mapping_methods WHERE id = v_map_id;
        IF v_mp_ass IS NOT NULL THEN
            EXECUTE format('SELECT %I($1, $2, $3)', v_mp_ass) USING obj_id, key_id, value_id INTO v_dummy;
            RETURN;
        END IF;
    END IF;

    SELECT tp_name INTO v_tp_name FROM public.py_type_object WHERE ob_base = v_type_id;
    PERFORM public.py_err_set_type_error('''' || COALESCE(v_tp_name, 'unknown') || ''' object does not support item assignment');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_delitem(obj_id UUID, key_id UUID)
RETURNS void AS $$
DECLARE
    v_type_id UUID;
    v_map_id UUID;
    v_mp_ass regproc;
    v_tp_name TEXT;
    v_dummy UUID;
BEGIN
    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = obj_id;

    -- Check tp_as_mapping → mp_ass_subscript (NULL value = delete)
    SELECT tp_as_mapping INTO v_map_id FROM public.py_type_object WHERE ob_base = v_type_id;
    IF v_map_id IS NOT NULL THEN
        SELECT mp_ass_subscript INTO v_mp_ass FROM public.py_mapping_methods WHERE id = v_map_id;
        IF v_mp_ass IS NOT NULL THEN
            EXECUTE format('SELECT %I($1, $2, $3)', v_mp_ass) USING obj_id, key_id, NULL::UUID INTO v_dummy;
            RETURN;
        END IF;
    END IF;

    SELECT tp_name INTO v_tp_name FROM public.py_type_object WHERE ob_base = v_type_id;
    PERFORM public.py_err_set_type_error('''' || COALESCE(v_tp_name, 'unknown') || ''' object does not support item deletion');
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register mp_subscript / mp_ass_subscript slots for tuple, list, dict
-- ============================================================================
DO $$
DECLARE
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_LIST_TYPE  UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE  UUID := '00000000-0000-4000-a000-000000000006';

    v_tuple_map_id UUID;
    v_list_map_id UUID;
BEGIN
    -- tuple: needs a new py_mapping_methods row (mp_subscript only, no mp_ass_subscript)
    v_tuple_map_id := gen_random_uuid();
    INSERT INTO public.py_mapping_methods (id, mp_subscript)
    VALUES (v_tuple_map_id, 'py_tuple_mp_subscript'::regproc);
    UPDATE public.py_type_object SET tp_as_mapping = v_tuple_map_id WHERE ob_base = ID_TUPLE_TYPE;

    -- list: needs a new py_mapping_methods row
    v_list_map_id := gen_random_uuid();
    INSERT INTO public.py_mapping_methods (id, mp_subscript, mp_ass_subscript)
    VALUES (v_list_map_id, 'py_list_mp_subscript'::regproc, 'py_list_mp_ass_subscript'::regproc);
    UPDATE public.py_type_object SET tp_as_mapping = v_list_map_id WHERE ob_base = ID_LIST_TYPE;

    -- dict: already has a py_mapping_methods row (from type_method_slots.sql), update it
    UPDATE public.py_mapping_methods
    SET mp_subscript = 'py_dict_mp_subscript'::regproc,
        mp_ass_subscript = 'py_dict_mp_ass_subscript'::regproc
    WHERE id = (SELECT tp_as_mapping FROM public.py_type_object WHERE ob_base = ID_DICT_TYPE);
END $$;

-- ============================================================================
-- Opcode BINARY_SUBSCR: obj[key] via py_object_getitem dispatch
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_BINARY_SUBSCR(frame_id UUID)
RETURNS void AS $$
DECLARE
    key_id UUID;
    obj_id UUID;
    result_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    key_id := public.py_stack_pop(frame_id);
    obj_id := public.py_stack_pop(frame_id);
    result_id := public.py_object_getitem(obj_id, key_id);
    IF result_id IS NULL AND public.py_err_occurred() THEN
        RETURN;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
