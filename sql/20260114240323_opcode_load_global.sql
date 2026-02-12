-- ============================================================================
-- Migration: Opcode LOAD_GLOBAL (116) — 240323 (opcode block)
-- CPython 3.11: Load from globals then builtins (no locals).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_GLOBAL(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    name_str TEXT;
    obj_id UUID;
    f_globals_id UUID;
    f_builtins_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'LOAD_GLOBAL: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_GLOBAL: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_GLOBAL: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_GLOBAL: Index % out of range for co_names tuple', name_index;
    END IF;
    SELECT str_value INTO name_str FROM public.py_unicode_object WHERE ob_base = name_str_id;

    SELECT f_globals, f_builtins INTO f_globals_id, f_builtins_id
    FROM public.py_frame_object WHERE ob_base = frame_id;
    IF f_globals_id IS NULL OR f_builtins_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_GLOBAL: Frame with id % does not have globals and builtins', frame_id;
    END IF;

    -- 3.11: LOAD_GLOBAL looks in globals then builtins only (no locals).
    obj_id := public.py_dict_get_item(f_globals_id, name_str_id);
    IF obj_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;
    obj_id := public.py_dict_get_item(f_builtins_id, name_str_id);
    IF obj_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;

    PERFORM public.py_err_set_name_error('name ''' || COALESCE(name_str, 'unknown') || ''' is not defined');
    RETURN;
END;
$$ LANGUAGE plpgsql;
