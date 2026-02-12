-- ============================================================================
-- Migration: Opcode STORE_GLOBAL (97) — 240318 (opcode block)
-- CPython 3.11: Stores TOS into the global namespace (f_globals). namei = co_names[name_index].
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_STORE_GLOBAL(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    f_globals_id UUID;
    value_obj_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'STORE_GLOBAL: Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'STORE_GLOBAL: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'STORE_GLOBAL: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'STORE_GLOBAL: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'STORE_GLOBAL: Index % out of range for co_names tuple', name_index;
    END IF;
    SELECT f_globals INTO f_globals_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF f_globals_id IS NULL THEN
        RAISE EXCEPTION 'STORE_GLOBAL: Frame with id % does not have f_globals', frame_id;
    END IF;

    value_obj_id := public.py_stack_pop(frame_id);
    PERFORM public.py_dict_set_item(f_globals_id, name_str_id, value_obj_id);
END;
$$ LANGUAGE plpgsql;
