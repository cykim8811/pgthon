-- ============================================================================
-- Migration: Opcode STORE_NAME (90) — 240306 (opcode block)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_STORE_NAME(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    f_locals_id UUID;
    value_obj_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'STORE_NAME: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Index % out of range for co_names tuple', name_index;
    END IF;
    SELECT f_locals INTO f_locals_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF f_locals_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Frame with id % does not have f_locals', frame_id;
    END IF;

    value_obj_id := public.py_stack_pop(frame_id);
    PERFORM public.py_dict_set_item(f_locals_id, name_str_id, value_obj_id);
END;
$$ LANGUAGE plpgsql;
