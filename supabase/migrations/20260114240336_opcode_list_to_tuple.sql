-- ============================================================================
-- Migration: Opcode LIST_TO_TUPLE (82) — CPython 3.11
-- 20260114240336
--
-- Pops TOS (must be list); pushes tuple with same elements (tuple(list)).
-- Depends: ceval_core (py_stack_pop, py_stack_push), py_list_object, py_tuple_object.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_LIST_TO_TUPLE(frame_id UUID)
RETURNS void AS $$
DECLARE
    list_id UUID;
    items UUID[];
    tuple_id UUID;
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    type_name text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    list_id := public.py_stack_pop(frame_id);
    IF NOT EXISTS (SELECT 1 FROM public.py_list_object WHERE ob_base = list_id) THEN
        SELECT tp_name INTO type_name FROM public.py_type_object t
        JOIN public.py_object o ON o.ob_type = t.ob_base WHERE o.id = list_id;
        PERFORM public.py_err_set_type_error('list_to_tuple expected list, got ''' || COALESCE(type_name, 'unknown') || '''');
        RETURN;
    END IF;
    SELECT ob_item INTO items FROM public.py_list_object WHERE ob_base = list_id;
    IF items IS NULL THEN
        items := array[]::uuid[];
    END IF;
    tuple_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (tuple_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (tuple_id, items);
    PERFORM public.py_stack_push(frame_id, tuple_id);
END;
$$ LANGUAGE plpgsql;
