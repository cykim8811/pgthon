-- ============================================================================
-- Migration: Opcode BUILD_LIST (103) — 240305 (opcode block)
-- ============================================================================
-- Pop count items; build list; push. Depends: ceval_core (stack), bootstrap (list type).

CREATE OR REPLACE FUNCTION public.py_opcode_BUILD_LIST(frame_id UUID, count INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    items UUID[] := '{}';
    new_id UUID;
    i INTEGER;
    elem_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF count < 0 THEN
        RAISE EXCEPTION 'BUILD_LIST: count must be non-negative, got %', count;
    END IF;
    FOR i IN 1..count LOOP
        elem_id := public.py_stack_pop(frame_id);
        items := array_prepend(elem_id, items);
    END LOOP;
    new_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (new_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item) VALUES (new_id, items);
    PERFORM public.py_stack_push(frame_id, new_id);
END;
$$ LANGUAGE plpgsql;
