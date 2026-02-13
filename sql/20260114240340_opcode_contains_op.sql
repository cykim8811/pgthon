-- ============================================================================
-- Migration: Opcode CONTAINS_OP (118) — CPython 3.11
-- 20260114240340
--
-- Stack: ..., container, item → ..., bool. oparg 0 = "in", oparg 1 = "not in".
-- Dispatches through sq_contains slot on tp_as_sequence.
-- Depends: ceval_core (py_stack_pop, py_stack_push), tp_richcompare_slot (234900).
-- ============================================================================

-- ============================================================================
-- Type-specific sq_contains handlers
-- Signature: (obj_id UUID, item_id UUID) RETURNS boolean
-- Uses py_object_richcompare_eq for value equality (not UUID identity).
-- ============================================================================

-- tuple.__contains__
CREATE OR REPLACE FUNCTION public.py_tuple_sq_contains(obj_id UUID, item_id UUID)
RETURNS boolean AS $$
DECLARE
    items UUID[];
    i INTEGER;
BEGIN
    SELECT ob_item INTO items FROM public.py_tuple_object WHERE ob_base = obj_id;
    FOR i IN 1..COALESCE(array_length(items, 1), 0) LOOP
        IF public.py_object_richcompare_eq(items[i], item_id) THEN
            RETURN true;
        END IF;
    END LOOP;
    RETURN false;
END;
$$ LANGUAGE plpgsql;

-- list.__contains__
CREATE OR REPLACE FUNCTION public.py_list_sq_contains(obj_id UUID, item_id UUID)
RETURNS boolean AS $$
DECLARE
    items UUID[];
    i INTEGER;
BEGIN
    SELECT ob_item INTO items FROM public.py_list_object WHERE ob_base = obj_id;
    FOR i IN 1..COALESCE(array_length(items, 1), 0) LOOP
        IF public.py_object_richcompare_eq(items[i], item_id) THEN
            RETURN true;
        END IF;
    END LOOP;
    RETURN false;
END;
$$ LANGUAGE plpgsql;

-- dict.__contains__ (key membership)
CREATE OR REPLACE FUNCTION public.py_dict_sq_contains(obj_id UUID, item_id UUID)
RETURNS boolean AS $$
DECLARE
    v_result UUID;
BEGIN
    v_result := public.py_dict_get_item(obj_id, item_id);
    IF public.py_err_occurred() THEN
        -- Clear any error from dict lookup and return false
        PERFORM public.py_err_clear();
        RETURN false;
    END IF;
    RETURN (v_result IS NOT NULL);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_sequence_contains: Dispatch through sq_contains slot
-- CPython: PySequence_Contains (Objects/abstract.c)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_sequence_contains(obj_id UUID, item_id UUID)
RETURNS boolean AS $$
DECLARE
    v_type_id UUID;
    v_seq_id UUID;
    v_sq_contains regproc;
    v_result boolean;
    v_tp_name TEXT;
BEGIN
    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = obj_id;

    -- Check tp_as_sequence → sq_contains
    SELECT tp_as_sequence INTO v_seq_id FROM public.py_type_object WHERE ob_base = v_type_id;
    IF v_seq_id IS NOT NULL THEN
        SELECT sq_contains INTO v_sq_contains FROM public.py_sequence_methods WHERE id = v_seq_id;
        IF v_sq_contains IS NOT NULL THEN
            EXECUTE format('SELECT %I($1, $2)', v_sq_contains) USING obj_id, item_id INTO v_result;
            RETURN v_result;
        END IF;
    END IF;

    -- No sq_contains slot — TypeError
    SELECT tp_name INTO v_tp_name FROM public.py_type_object WHERE ob_base = v_type_id;
    PERFORM public.py_err_set_type_error('argument of type ''' || COALESCE(v_tp_name, 'unknown') || ''' has no ''in'' support');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register sq_contains slots for tuple, list, dict
-- ============================================================================
DO $$
DECLARE
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_LIST_TYPE  UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE  UUID := '00000000-0000-4000-a000-000000000006';
    v_dict_seq_id UUID;
BEGIN
    -- tuple: already has a py_sequence_methods row (from type_method_slots.sql), update it
    UPDATE public.py_sequence_methods
    SET sq_contains = 'py_tuple_sq_contains'::regproc
    WHERE id = (SELECT tp_as_sequence FROM public.py_type_object WHERE ob_base = ID_TUPLE_TYPE);

    -- list: already has a py_sequence_methods row, update it
    UPDATE public.py_sequence_methods
    SET sq_contains = 'py_list_sq_contains'::regproc
    WHERE id = (SELECT tp_as_sequence FROM public.py_type_object WHERE ob_base = ID_LIST_TYPE);

    -- dict: needs a py_sequence_methods row for sq_contains (CPython: dict uses tp_as_sequence for __contains__)
    v_dict_seq_id := gen_random_uuid();
    INSERT INTO public.py_sequence_methods (id, sq_contains)
    VALUES (v_dict_seq_id, 'py_dict_sq_contains'::regproc);
    UPDATE public.py_type_object SET tp_as_sequence = v_dict_seq_id WHERE ob_base = ID_DICT_TYPE;
END $$;

-- ============================================================================
-- Opcode CONTAINS_OP: dispatches through py_sequence_contains
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_CONTAINS_OP(frame_id UUID, oparg INTEGER)
RETURNS void AS $$
DECLARE
    item_id UUID;
    container_id UUID;
    found BOOLEAN;
    result_id UUID;
    ID_TRUE_OBJ  UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000011';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    item_id := public.py_stack_pop(frame_id);
    container_id := public.py_stack_pop(frame_id);

    found := public.py_sequence_contains(container_id, item_id);
    IF found IS NULL AND public.py_err_occurred() THEN
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
