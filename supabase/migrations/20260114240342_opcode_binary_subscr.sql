-- ============================================================================
-- Migration: Opcode BINARY_SUBSCR (25) — CPython 3.11
-- 20260114240342
--
-- Stack: ..., obj, key → ..., result. obj[key].
-- Supports: tuple/list (key = int index, 0-based; negative = from end), dict (key lookup).
-- Depends: ceval_core (py_stack_pop, py_stack_push), py_tuple_object, py_list_object,
--          py_dict_get_item, py_long_object.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_BINARY_SUBSCR(frame_id UUID)
RETURNS void AS $$
DECLARE
    key_id UUID;
    obj_id UUID;
    items UUID[];
    seq_len INTEGER;
    idx INTEGER;
    key_val NUMERIC;
    result_id UUID;
    type_name text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    key_id := public.py_stack_pop(frame_id);
    obj_id := public.py_stack_pop(frame_id);
    result_id := NULL;
    IF EXISTS (SELECT 1 FROM public.py_tuple_object WHERE ob_base = obj_id) THEN
        IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = key_id) THEN
            PERFORM public.py_err_set_type_error('tuple indices must be integers or slices, not type');
            RETURN;
        END IF;
        SELECT long_value INTO key_val FROM public.py_long_object WHERE ob_base = key_id;
        idx := key_val::INTEGER;
        SELECT ob_item INTO items FROM public.py_tuple_object WHERE ob_base = obj_id;
        IF items IS NULL THEN items := array[]::uuid[]; END IF;
        seq_len := array_length(items, 1);
        IF seq_len IS NULL THEN seq_len := 0; END IF;
        IF idx < 0 THEN idx := idx + seq_len; END IF;
        IF idx < 0 OR idx >= seq_len THEN
            PERFORM public.py_err_set_index_error('tuple index out of range');
            RETURN;
        END IF;
        result_id := items[idx + 1];
    ELSIF EXISTS (SELECT 1 FROM public.py_list_object WHERE ob_base = obj_id) THEN
        IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = key_id) THEN
            PERFORM public.py_err_set_type_error('list indices must be integers or slices, not type');
            RETURN;
        END IF;
        SELECT long_value INTO key_val FROM public.py_long_object WHERE ob_base = key_id;
        idx := key_val::INTEGER;
        SELECT ob_item INTO items FROM public.py_list_object WHERE ob_base = obj_id;
        IF items IS NULL THEN items := array[]::uuid[]; END IF;
        seq_len := array_length(items, 1);
        IF seq_len IS NULL THEN seq_len := 0; END IF;
        IF idx < 0 THEN idx := idx + seq_len; END IF;
        IF idx < 0 OR idx >= seq_len THEN
            PERFORM public.py_err_set_index_error('list index out of range');
            RETURN;
        END IF;
        result_id := items[idx + 1];
    ELSIF EXISTS (SELECT 1 FROM public.py_dict_object WHERE ob_base = obj_id) THEN
        result_id := public.py_dict_get_item(obj_id, key_id);
        IF result_id IS NULL AND public.py_err_occurred() THEN
            RETURN;
        END IF;
        IF result_id IS NULL THEN
            PERFORM public.py_err_set_key_error('key not found');
            RETURN;
        END IF;
    ELSE
        SELECT tp_name INTO type_name FROM public.py_type_object t
        JOIN public.py_object o ON o.ob_type = t.ob_base WHERE o.id = obj_id;
        PERFORM public.py_err_set_type_error('''' || COALESCE(type_name, 'unknown') || ''' object is not subscriptable');
        RETURN;
    END IF;
    IF result_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, result_id);
    END IF;
END;
$$ LANGUAGE plpgsql;
