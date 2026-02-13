-- ============================================================================
-- Migration: Opcode BUILD_CONST_KEY_MAP (156) — CPython 3.11
--
-- {k1: v1, k2: v2} with constant keys.
-- TOS = tuple of keys. Pop count values from stack. Create dict mapping keys[i] → values[i].
-- Depends: ceval_core, py_dict_set_item, py_tuple_object.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_BUILD_CONST_KEY_MAP(frame_id UUID, count INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_DICT_TYPE  UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    keys_tuple_id UUID;
    keys_type UUID;
    keys UUID[];
    values UUID[] := ARRAY[]::uuid[];
    dict_id UUID;
    i INT;
BEGIN
    -- Pop keys tuple from TOS
    keys_tuple_id := public.py_stack_pop(frame_id);

    -- Validate it's a tuple
    SELECT ob_type INTO keys_type FROM public.py_object WHERE id = keys_tuple_id;
    IF keys_type IS DISTINCT FROM ID_TUPLE_TYPE THEN
        PERFORM public.py_err_set_type_error('BUILD_CONST_KEY_MAP: keys must be a tuple');
        RETURN;
    END IF;

    SELECT ob_item INTO keys FROM public.py_tuple_object WHERE ob_base = keys_tuple_id;
    IF keys IS NULL THEN keys := ARRAY[]::uuid[]; END IF;

    -- Pop count values (use prepend to preserve order: first value popped = last in array)
    FOR i IN 1..count LOOP
        values := array_prepend(public.py_stack_pop(frame_id), values);
    END LOOP;

    -- Create dict
    dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_id);

    -- Set items: keys[i] → values[i]
    FOR i IN 1..count LOOP
        PERFORM public.py_dict_set_item(dict_id, keys[i], values[i]);
        IF public.py_err_occurred() THEN
            RETURN;
        END IF;
    END LOOP;

    PERFORM public.py_stack_push(frame_id, dict_id);
END;
$$ LANGUAGE plpgsql;
