-- ============================================================================
-- Migration: Container Extension Opcodes (CPython 3.11)
-- LIST_EXTEND(162), SET_UPDATE(163), DICT_UPDATE(164), DICT_MERGE(165)
--
-- LIST_EXTEND(i): Pop TOS (iterable), extend list at PEEK(i) with its items.
-- SET_UPDATE(i): Pop TOS (iterable), update set at PEEK(i) with its items.
-- DICT_UPDATE(i): Pop TOS (dict), merge into dict at PEEK(i); duplicates overwrite.
-- DICT_MERGE(i): Pop TOS (dict), merge into dict at PEEK(i); duplicates → TypeError.
-- Depends: ceval_core, py_iterate_to_array, py_dict_set_item, py_dict_get_item.
-- ============================================================================

-- LIST_EXTEND(oparg): Pop TOS (iterable), peek at list at depth oparg, extend.
CREATE OR REPLACE FUNCTION public.py_opcode_LIST_EXTEND(frame_id UUID, oparg INTEGER)
RETURNS VOID AS $$
DECLARE
    iterable_id UUID;
    stack UUID[];
    len INT;
    list_id UUID;
    items UUID[];
BEGIN
    -- Pop the iterable
    iterable_id := public.py_stack_pop(frame_id);

    -- Peek at the list
    SELECT f_valuestack INTO stack FROM public.py_frame_object WHERE ob_base = frame_id;
    len := COALESCE(array_length(stack, 1), 0);

    IF len < oparg THEN
        RAISE EXCEPTION 'LIST_EXTEND: stack too shallow (size=%, oparg=%)', len, oparg;
    END IF;

    list_id := stack[len - oparg + 1];

    -- Iterate the iterable to get items
    items := public.py_iterate_to_array(iterable_id);
    IF items IS NULL THEN
        RETURN; -- error already set
    END IF;

    -- Extend list in place
    UPDATE public.py_list_object SET ob_item = ob_item || items WHERE ob_base = list_id;
END;
$$ LANGUAGE plpgsql;

-- SET_UPDATE(oparg): Pop TOS (iterable), peek at set at depth oparg, add all items.
CREATE OR REPLACE FUNCTION public.py_opcode_SET_UPDATE(frame_id UUID, oparg INTEGER)
RETURNS VOID AS $$
DECLARE
    iterable_id UUID;
    stack UUID[];
    len INT;
    set_id UUID;
    items UUID[];
BEGIN
    -- Pop the iterable
    iterable_id := public.py_stack_pop(frame_id);

    -- Peek at the set
    SELECT f_valuestack INTO stack FROM public.py_frame_object WHERE ob_base = frame_id;
    len := COALESCE(array_length(stack, 1), 0);

    IF len < oparg THEN
        RAISE EXCEPTION 'SET_UPDATE: stack too shallow (size=%, oparg=%)', len, oparg;
    END IF;

    set_id := stack[len - oparg + 1];

    -- Iterate the iterable to get items
    items := public.py_iterate_to_array(iterable_id);
    IF items IS NULL THEN
        RETURN; -- error already set
    END IF;

    -- Update set in place
    UPDATE public.py_set_object SET ob_item = ob_item || items WHERE ob_base = set_id;
END;
$$ LANGUAGE plpgsql;

-- DICT_UPDATE(oparg): Pop TOS (source dict), merge into dict at PEEK(oparg).
-- Duplicates silently overwritten (last wins).
CREATE OR REPLACE FUNCTION public.py_opcode_DICT_UPDATE(frame_id UUID, oparg INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    source_id UUID;
    source_type UUID;
    stack UUID[];
    len INT;
    target_id UUID;
    v_key UUID;
    v_value UUID;
    v_tp_name TEXT;
    rec RECORD;
BEGIN
    -- Pop source dict
    source_id := public.py_stack_pop(frame_id);

    -- Validate source is a dict
    SELECT ob_type INTO source_type FROM public.py_object WHERE id = source_id;
    IF source_type IS DISTINCT FROM ID_DICT_TYPE THEN
        SELECT tp_name INTO v_tp_name FROM public.py_type_object WHERE ob_base = source_type;
        PERFORM public.py_err_set_type_error(
            format('''%s'' object is not a mapping', COALESCE(v_tp_name, '<unknown>')));
        RETURN;
    END IF;

    -- Peek at target dict
    SELECT f_valuestack INTO stack FROM public.py_frame_object WHERE ob_base = frame_id;
    len := COALESCE(array_length(stack, 1), 0);

    IF len < oparg THEN
        RAISE EXCEPTION 'DICT_UPDATE: stack too shallow (size=%, oparg=%)', len, oparg;
    END IF;

    target_id := stack[len - oparg + 1];

    -- Copy all entries from source to target (overwrite duplicates)
    FOR rec IN SELECT me_key, me_value FROM public.py_dict_entry WHERE dict_id = source_id LOOP
        PERFORM public.py_dict_set_item(target_id, rec.me_key, rec.me_value);
        IF public.py_err_occurred() THEN
            RETURN;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- DICT_MERGE(oparg): Pop TOS (source dict), merge into dict at PEEK(oparg).
-- Duplicate keys → TypeError (used for f(**a, **b) where duplicates are errors).
CREATE OR REPLACE FUNCTION public.py_opcode_DICT_MERGE(frame_id UUID, oparg INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    source_id UUID;
    source_type UUID;
    stack UUID[];
    len INT;
    target_id UUID;
    existing UUID;
    v_tp_name TEXT;
    v_key_str TEXT;
    rec RECORD;
BEGIN
    -- Pop source dict
    source_id := public.py_stack_pop(frame_id);

    -- Validate source is a dict
    SELECT ob_type INTO source_type FROM public.py_object WHERE id = source_id;
    IF source_type IS DISTINCT FROM ID_DICT_TYPE THEN
        SELECT tp_name INTO v_tp_name FROM public.py_type_object WHERE ob_base = source_type;
        PERFORM public.py_err_set_type_error(
            format('''%s'' object is not a mapping', COALESCE(v_tp_name, '<unknown>')));
        RETURN;
    END IF;

    -- Peek at target dict
    SELECT f_valuestack INTO stack FROM public.py_frame_object WHERE ob_base = frame_id;
    len := COALESCE(array_length(stack, 1), 0);

    IF len < oparg THEN
        RAISE EXCEPTION 'DICT_MERGE: stack too shallow (size=%, oparg=%)', len, oparg;
    END IF;

    target_id := stack[len - oparg + 1];

    -- Copy entries, checking for duplicates
    FOR rec IN SELECT me_key, me_value FROM public.py_dict_entry WHERE dict_id = source_id LOOP
        -- Check if key already exists in target
        existing := public.py_dict_get_item(target_id, rec.me_key);
        IF public.py_err_occurred() THEN
            RETURN; -- hash error
        END IF;

        IF existing IS NOT NULL THEN
            -- Duplicate key → TypeError
            SELECT str_value INTO v_key_str FROM public.py_unicode_object WHERE ob_base = rec.me_key;
            PERFORM public.py_err_set_type_error(
                format('got multiple values for keyword argument ''%s''', COALESCE(v_key_str, '?')));
            RETURN;
        END IF;

        PERFORM public.py_dict_set_item(target_id, rec.me_key, rec.me_value);
        IF public.py_err_occurred() THEN
            RETURN;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
