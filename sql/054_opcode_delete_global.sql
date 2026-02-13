-- ============================================================================
-- Migration: Opcode DELETE_GLOBAL (98) — CPython 3.11
-- 20260114240328
--
-- Deletes the name from the global namespace (f_globals). namei = co_names[name_index].
-- Does not pop the stack. If the name is not in globals, sets NameError.
-- Depends: function_object_schema (frame, code), tp_hash_slot (py_dict_del_item, py_err_set_name_error).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_DELETE_GLOBAL(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    name_str TEXT;
    f_globals_id UUID;
    deleted BOOLEAN;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'DELETE_GLOBAL: Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'DELETE_GLOBAL: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'DELETE_GLOBAL: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'DELETE_GLOBAL: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'DELETE_GLOBAL: Index % out of range for co_names tuple', name_index;
    END IF;
    SELECT str_value INTO name_str FROM public.py_unicode_object WHERE ob_base = name_str_id;

    SELECT f_globals INTO f_globals_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF f_globals_id IS NULL THEN
        RAISE EXCEPTION 'DELETE_GLOBAL: Frame with id % does not have f_globals', frame_id;
    END IF;

    deleted := public.py_dict_del_item(f_globals_id, name_str_id);
    IF NOT deleted THEN
        PERFORM public.py_err_set_name_error('name ''' || COALESCE(name_str, 'unknown') || ''' is not defined');
    END IF;
END;
$$ LANGUAGE plpgsql;
