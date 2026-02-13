-- ============================================================================
-- Migration: Opcode UNPACK_EX (94) — CPython 3.11
--
-- a, *b, c = iterable
-- oparg encoding: count_before = oparg & 0xFF, count_after = (oparg >> 8) & 0xFF
-- Pop iterable, iterate to array, validate length >= count_before + count_after.
-- Push items in reverse order: last count_after items, then middle list, then first count_before items.
-- (First element ends up deepest, matching CPython's STORE_FAST order.)
-- Depends: ceval_core, py_iterate_to_array, py_list_object.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_UNPACK_EX(frame_id UUID, oparg INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    count_before INT;
    count_after INT;
    iterable_id UUID;
    items UUID[];
    total INT;
    middle_start INT;
    middle_end INT;
    middle_items UUID[];
    list_id UUID;
    i INT;
BEGIN
    count_before := oparg & 255;
    count_after := (oparg >> 8) & 255;

    -- Pop iterable
    iterable_id := public.py_stack_pop(frame_id);

    -- Iterate to array
    items := public.py_iterate_to_array(iterable_id);
    IF items IS NULL THEN
        RETURN; -- error already set
    END IF;

    total := COALESCE(array_length(items, 1), 0);

    -- Validate minimum length
    IF total < count_before + count_after THEN
        PERFORM public.py_err_set_value_error(
            format('not enough values to unpack (expected at least %s, got %s)',
                   count_before + count_after, total));
        RETURN;
    END IF;

    -- Build middle list (items between count_before and total - count_after)
    middle_start := count_before + 1;
    middle_end := total - count_after;
    IF middle_start <= middle_end THEN
        middle_items := items[middle_start:middle_end];
    ELSE
        middle_items := ARRAY[]::uuid[];
    END IF;

    list_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (list_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item) VALUES (list_id, middle_items);

    -- Push in reverse order so first element is deepest on stack:
    -- Push count_after items (from end), then middle list, then count_before items (from start)
    -- All in reverse so that the first assigned variable gets the deepest stack position.

    -- Push last count_after items in reverse
    FOR i IN REVERSE total..total - count_after + 1 LOOP
        PERFORM public.py_stack_push(frame_id, items[i]);
    END LOOP;

    -- Push the middle list
    PERFORM public.py_stack_push(frame_id, list_id);

    -- Push first count_before items in reverse
    FOR i IN REVERSE count_before..1 LOOP
        PERFORM public.py_stack_push(frame_id, items[i]);
    END LOOP;
END;
$$ LANGUAGE plpgsql;
