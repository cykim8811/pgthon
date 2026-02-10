-- ============================================================================
-- Migration: Opcode BUILD_MAP (105) — CPython 3.11
-- 20260114240341
--
-- Pops 2*count items: for each pair, value then key (TOS = value, then key).
-- Builds a new dict and pushes it. oparg = count (number of key-value pairs).
-- Depends: ceval_core (py_stack_pop, py_stack_push), py_dict_object, py_dict_set_item.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_BUILD_MAP(frame_id UUID, count INTEGER)
RETURNS void AS $$
DECLARE
    dict_id UUID;
    key_id UUID;
    value_id UUID;
    i INTEGER;
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF count < 0 THEN
        RAISE EXCEPTION 'BUILD_MAP: count must be non-negative, got %', count;
    END IF;
    dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_id);
    FOR i IN 1..count LOOP
        value_id := public.py_stack_pop(frame_id);
        key_id := public.py_stack_pop(frame_id);
        IF key_id IS NULL OR value_id IS NULL THEN
            RAISE EXCEPTION 'BUILD_MAP: stack underflow';
        END IF;
        PERFORM public.py_dict_set_item(dict_id, key_id, value_id);
    END LOOP;
    PERFORM public.py_stack_push(frame_id, dict_id);
END;
$$ LANGUAGE plpgsql;
