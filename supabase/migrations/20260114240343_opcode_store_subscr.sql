-- ============================================================================
-- Migration: Opcode STORE_SUBSCR (60) — CPython 3.11
-- 20260114240343
--
-- Stack: ..., obj, key, value → ...  (TOS = value). obj[key] = value.
-- Supports: list (int index, in-place update ob_item), dict (py_dict_set_item).
-- tuple → TypeError (does not support item assignment).
-- Depends: ceval_core, py_list_object, py_dict_set_item, py_long_object, exception setters.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_STORE_SUBSCR(frame_id UUID)
RETURNS void AS $$
DECLARE
    value_id UUID;
    key_id UUID;
    obj_id UUID;
    items UUID[];
    seq_len INTEGER;
    idx INTEGER;
    key_val NUMERIC;
    type_name text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    value_id := public.py_stack_pop(frame_id);
    key_id := public.py_stack_pop(frame_id);
    obj_id := public.py_stack_pop(frame_id);

    IF EXISTS (SELECT 1 FROM public.py_tuple_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('tuple object does not support item assignment');
        RETURN;
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
            PERFORM public.py_err_set_index_error('list assignment index out of range');
            RETURN;
        END IF;
        items[idx + 1] := value_id;
        UPDATE public.py_list_object SET ob_item = items WHERE ob_base = obj_id;
    ELSIF EXISTS (SELECT 1 FROM public.py_dict_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_dict_set_item(obj_id, key_id, value_id);
        IF public.py_err_occurred() THEN
            RETURN;
        END IF;
    ELSE
        SELECT tp_name INTO type_name FROM public.py_type_object t
        JOIN public.py_object o ON o.ob_type = t.ob_base WHERE o.id = obj_id;
        PERFORM public.py_err_set_type_error('''' || COALESCE(type_name, 'unknown') || ''' object does not support item assignment');
        RETURN;
    END IF;
END;
$$ LANGUAGE plpgsql;
