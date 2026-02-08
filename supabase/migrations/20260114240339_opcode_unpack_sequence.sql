-- ============================================================================
-- Migration: Opcode UNPACK_SEQUENCE (92) — CPython 3.11
-- 20260114240339
--
-- Pops TOS (sequence: tuple or list); pushes count elements so that first
-- element is at stack[-count] and last at TOS. oparg = count.
-- If len(sequence) != count, ValueError.
-- Depends: ceval_core (py_stack_pop, py_stack_push), py_tuple_object, py_list_object.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_UNPACK_SEQUENCE(frame_id UUID, count INTEGER)
RETURNS void AS $$
DECLARE
    seq_id UUID;
    items UUID[];
    seq_len INTEGER;
    i INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF count < 0 THEN
        RAISE EXCEPTION 'UNPACK_SEQUENCE: count must be non-negative, got %', count;
    END IF;
    seq_id := public.py_stack_pop(frame_id);
    IF EXISTS (SELECT 1 FROM public.py_tuple_object WHERE ob_base = seq_id) THEN
        SELECT ob_item INTO items FROM public.py_tuple_object WHERE ob_base = seq_id;
    ELSIF EXISTS (SELECT 1 FROM public.py_list_object WHERE ob_base = seq_id) THEN
        SELECT ob_item INTO items FROM public.py_list_object WHERE ob_base = seq_id;
    ELSE
        PERFORM public.py_err_set_type_error('cannot unpack non-iterable object');
        RETURN;
    END IF;
    IF items IS NULL THEN
        items := array[]::uuid[];
    END IF;
    seq_len := array_length(items, 1);
    IF seq_len IS NULL THEN seq_len := 0; END IF;
    IF seq_len != count THEN
        PERFORM public.py_err_set_value_error('cannot unpack sequence of ' || seq_len || ' items into ' || count || ' values');
        RETURN;
    END IF;
    FOR i IN REVERSE seq_len..1 LOOP
        PERFORM public.py_stack_push(frame_id, items[i]);
    END LOOP;
END;
$$ LANGUAGE plpgsql;
