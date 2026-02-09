-- ============================================================================
-- Comprehension Opcodes (CPython 3.11)
-- BUILD_SET(104), LIST_APPEND(145), SET_ADD(146), MAP_ADD(147)
-- ============================================================================

-- BUILD_SET(count): Pop count items from stack, create a set object, push it.
-- Same pattern as BUILD_LIST but creates py_set_object.
CREATE OR REPLACE FUNCTION public.py_opcode_BUILD_SET(frame_id UUID, count INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_SET_TYPE UUID := '00000000-0000-4000-a000-000000000018';
    items UUID[] := '{}';
    new_id UUID;
    i INTEGER;
    elem_id UUID;
BEGIN
    IF count < 0 THEN
        RAISE EXCEPTION 'BUILD_SET: count must be non-negative, got %', count;
    END IF;

    FOR i IN 1..count LOOP
        elem_id := public.py_stack_pop(frame_id);
        items := array_prepend(elem_id, items);
    END LOOP;

    new_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (new_id, ID_SET_TYPE);
    INSERT INTO public.py_set_object (ob_base, ob_item) VALUES (new_id, items);
    PERFORM public.py_stack_push(frame_id, new_id);
END;
$$ LANGUAGE plpgsql;

-- LIST_APPEND(i): Pop TOS (value), peek at list at depth oparg, append value to list.
-- Used by list comprehensions. CPython: list.append(PEEK(i), POP())
CREATE OR REPLACE FUNCTION public.py_opcode_LIST_APPEND(frame_id UUID, oparg INTEGER)
RETURNS VOID AS $$
DECLARE
    value_id uuid;
    stack uuid[];
    len int;
    list_id uuid;
BEGIN
    -- Pop the value first
    value_id := public.py_stack_pop(frame_id);

    -- Read the stack after pop to peek at the list
    SELECT f_valuestack INTO stack FROM public.py_frame_object WHERE ob_base = frame_id;
    len := array_length(stack, 1);

    IF len IS NULL OR len < oparg THEN
        RAISE EXCEPTION 'LIST_APPEND: stack too shallow (size=%, oparg=%)', COALESCE(len, 0), oparg;
    END IF;

    list_id := stack[len - oparg + 1];

    -- Append value to the list's ob_item array
    UPDATE public.py_list_object SET ob_item = array_append(ob_item, value_id) WHERE ob_base = list_id;
END;
$$ LANGUAGE plpgsql;

-- SET_ADD(i): Pop TOS (value), peek at set at depth oparg, add value to set.
-- Used by set comprehensions. Same pattern as LIST_APPEND but for sets.
CREATE OR REPLACE FUNCTION public.py_opcode_SET_ADD(frame_id UUID, oparg INTEGER)
RETURNS VOID AS $$
DECLARE
    value_id uuid;
    stack uuid[];
    len int;
    set_id uuid;
BEGIN
    -- Pop the value first
    value_id := public.py_stack_pop(frame_id);

    -- Read the stack after pop to peek at the set
    SELECT f_valuestack INTO stack FROM public.py_frame_object WHERE ob_base = frame_id;
    len := array_length(stack, 1);

    IF len IS NULL OR len < oparg THEN
        RAISE EXCEPTION 'SET_ADD: stack too shallow (size=%, oparg=%)', COALESCE(len, 0), oparg;
    END IF;

    set_id := stack[len - oparg + 1];

    -- Add value to the set's ob_item array
    UPDATE public.py_set_object SET ob_item = array_append(ob_item, value_id) WHERE ob_base = set_id;
END;
$$ LANGUAGE plpgsql;

-- MAP_ADD(i): Pop value (TOS), pop key (TOS-1), peek at dict at depth oparg, set dict[key]=value.
-- Used by dict comprehensions. CPython: value=POP(); key=POP(); map=PEEK(oparg); map[key]=value
CREATE OR REPLACE FUNCTION public.py_opcode_MAP_ADD(frame_id UUID, oparg INTEGER)
RETURNS VOID AS $$
DECLARE
    value_id uuid;
    key_id uuid;
    stack uuid[];
    len int;
    map_id uuid;
BEGIN
    -- Pop value (TOS), then key (TOS-1)
    value_id := public.py_stack_pop(frame_id);
    key_id := public.py_stack_pop(frame_id);

    -- Read the stack after both pops to peek at the dict
    SELECT f_valuestack INTO stack FROM public.py_frame_object WHERE ob_base = frame_id;
    len := array_length(stack, 1);

    IF len IS NULL OR len < oparg THEN
        RAISE EXCEPTION 'MAP_ADD: stack too shallow (size=%, oparg=%)', COALESCE(len, 0), oparg;
    END IF;

    map_id := stack[len - oparg + 1];

    -- Set dict[key] = value using the existing dict helper
    PERFORM public.py_dict_set_item(map_id, key_id, value_id);
END;
$$ LANGUAGE plpgsql;
