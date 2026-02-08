-- ============================================================================
-- Migration: Opcode CONTAINS_OP (118) — CPython 3.11
-- 20260114240340
--
-- Stack: ..., container, item → ..., bool. oparg 0 = "in", oparg 1 = "not in".
-- Pops item (right), container (left). Push True if (item in container) for
-- oparg 0, or (item not in container) for oparg 1. Supports tuple, list (identity in ob_item).
-- Depends: ceval_core (py_stack_pop, py_stack_push), py_tuple_object, py_list_object.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_CONTAINS_OP(frame_id UUID, oparg INTEGER)
RETURNS void AS $$
DECLARE
    item_id UUID;
    container_id UUID;
    items UUID[];
    found BOOLEAN;
    result_id UUID;
    ID_TRUE_OBJ  UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000011';
    type_name text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    item_id := public.py_stack_pop(frame_id);
    container_id := public.py_stack_pop(frame_id);
    found := FALSE;
    IF EXISTS (SELECT 1 FROM public.py_tuple_object WHERE ob_base = container_id) THEN
        SELECT ob_item INTO items FROM public.py_tuple_object WHERE ob_base = container_id;
        IF items IS NOT NULL AND item_id = ANY(items) THEN
            found := TRUE;
        END IF;
    ELSIF EXISTS (SELECT 1 FROM public.py_list_object WHERE ob_base = container_id) THEN
        SELECT ob_item INTO items FROM public.py_list_object WHERE ob_base = container_id;
        IF items IS NOT NULL AND item_id = ANY(items) THEN
            found := TRUE;
        END IF;
    ELSE
        SELECT tp_name INTO type_name FROM public.py_type_object t
        JOIN public.py_object o ON o.ob_type = t.ob_base WHERE o.id = container_id;
        PERFORM public.py_err_set_type_error('argument of type ''' || COALESCE(type_name, 'unknown') || ''' has no ''in'' support');
        RETURN;
    END IF;
    IF oparg = 0 THEN
        result_id := CASE WHEN found THEN ID_TRUE_OBJ ELSE ID_FALSE_OBJ END;
    ELSIF oparg = 1 THEN
        result_id := CASE WHEN found THEN ID_FALSE_OBJ ELSE ID_TRUE_OBJ END;
    ELSE
        RAISE EXCEPTION 'CONTAINS_OP: invalid oparg %', oparg;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
