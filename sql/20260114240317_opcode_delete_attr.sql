-- ============================================================================
-- Migration: Opcode DELETE_ATTR (96 in CPython 3.11) — 240317 (opcode block)
-- Design: docs/DELETE_ATTR_DESIGN.md §3.3. Stack: TOS = owner, pop then delattr(owner, name).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_DELETE_ATTR(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    obj_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'DELETE_ATTR: Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'DELETE_ATTR: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'DELETE_ATTR: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'DELETE_ATTR: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'DELETE_ATTR: Index % out of range for co_names tuple', name_index;
    END IF;

    obj_id := public.py_stack_pop(frame_id);
    PERFORM public.py_object_delattr(obj_id, name_str_id);
END;
$$ LANGUAGE plpgsql;
