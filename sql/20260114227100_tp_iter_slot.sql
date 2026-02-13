-- ============================================================================
-- Migration: tp_iter / tp_iternext Slot Functions (CPython 3.11)
-- Created: 2026-01-14 22:71:00
--
-- Purpose:
--   Implements the iteration protocol for list, tuple, dict, str types.
--   tp_iter(obj) → creates and returns an iterator object.
--   tp_iternext(iter) → returns next value or sets StopIteration.
--
-- CPython equivalents:
--   - list_iter (listobject.c) → listiter_next
--   - tuple_iter (tupleobject.c) → tupleiter_next
--   - dict_iter (dictobject.c) → dictiter_iternextkey
--   - str_iter (unicodeobject.c) → unicodeiter_next
--
-- Depends: 227000 (iterator schemas), 223000 (bootstrap), 224300 (exception_setters)
-- ============================================================================

-- ============================================================================
-- tp_iter: Create iterators from containers
-- ============================================================================

-- py_list_tp_iter: list.__iter__() → list_iterator
CREATE OR REPLACE FUNCTION public.py_list_tp_iter(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    ID_LIST_ITERATOR_TYPE UUID := '00000000-0000-4000-a000-000000000031';
    iter_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO public.py_object (id, ob_type) VALUES (iter_id, ID_LIST_ITERATOR_TYPE);
    INSERT INTO public.py_list_iterator_object (ob_base, it_seq, it_index)
    VALUES (iter_id, obj_id, 0);
    RETURN iter_id;
END;
$$ LANGUAGE plpgsql;

-- py_tuple_tp_iter: tuple.__iter__() → tuple_iterator
CREATE OR REPLACE FUNCTION public.py_tuple_tp_iter(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    ID_TUPLE_ITERATOR_TYPE UUID := '00000000-0000-4000-a000-000000000032';
    iter_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO public.py_object (id, ob_type) VALUES (iter_id, ID_TUPLE_ITERATOR_TYPE);
    INSERT INTO public.py_tuple_iterator_object (ob_base, it_seq, it_index)
    VALUES (iter_id, obj_id, 0);
    RETURN iter_id;
END;
$$ LANGUAGE plpgsql;

-- py_dict_tp_iter: dict.__iter__() → dict_keyiterator
CREATE OR REPLACE FUNCTION public.py_dict_tp_iter(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    ID_DICT_KEYITERATOR_TYPE UUID := '00000000-0000-4000-a000-000000000033';
    iter_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO public.py_object (id, ob_type) VALUES (iter_id, ID_DICT_KEYITERATOR_TYPE);
    INSERT INTO public.py_dict_keyiterator_object (ob_base, it_dict, it_pos)
    VALUES (iter_id, obj_id, 0);
    RETURN iter_id;
END;
$$ LANGUAGE plpgsql;

-- py_unicode_tp_iter: str.__iter__() → str_iterator
CREATE OR REPLACE FUNCTION public.py_unicode_tp_iter(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    ID_STR_ITERATOR_TYPE UUID := '00000000-0000-4000-a000-000000000034';
    iter_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO public.py_object (id, ob_type) VALUES (iter_id, ID_STR_ITERATOR_TYPE);
    INSERT INTO public.py_str_iterator_object (ob_base, it_seq, it_index)
    VALUES (iter_id, obj_id, 0);
    RETURN iter_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- tp_iternext: Advance iterators
-- ============================================================================

-- py_list_iterator_tp_iternext: list_iterator.__next__()
CREATE OR REPLACE FUNCTION public.py_list_iterator_tp_iternext(iter_id UUID)
RETURNS UUID AS $$
DECLARE
    v_seq UUID;
    v_index INTEGER;
    v_items UUID[];
    v_len INTEGER;
    v_value UUID;
BEGIN
    SELECT it_seq, it_index INTO v_seq, v_index
    FROM public.py_list_iterator_object WHERE ob_base = iter_id;

    SELECT ob_item INTO v_items FROM public.py_list_object WHERE ob_base = v_seq;
    v_len := COALESCE(array_length(v_items, 1), 0);

    IF v_index >= v_len THEN
        PERFORM public.py_err_set_stop_iteration();
        RETURN NULL;
    END IF;

    v_value := v_items[v_index + 1]; -- 1-based PostgreSQL array
    UPDATE public.py_list_iterator_object SET it_index = v_index + 1 WHERE ob_base = iter_id;
    RETURN v_value;
END;
$$ LANGUAGE plpgsql;

-- py_tuple_iterator_tp_iternext: tuple_iterator.__next__()
CREATE OR REPLACE FUNCTION public.py_tuple_iterator_tp_iternext(iter_id UUID)
RETURNS UUID AS $$
DECLARE
    v_seq UUID;
    v_index INTEGER;
    v_items UUID[];
    v_len INTEGER;
    v_value UUID;
BEGIN
    SELECT it_seq, it_index INTO v_seq, v_index
    FROM public.py_tuple_iterator_object WHERE ob_base = iter_id;

    SELECT ob_item INTO v_items FROM public.py_tuple_object WHERE ob_base = v_seq;
    v_len := COALESCE(array_length(v_items, 1), 0);

    IF v_index >= v_len THEN
        PERFORM public.py_err_set_stop_iteration();
        RETURN NULL;
    END IF;

    v_value := v_items[v_index + 1]; -- 1-based PostgreSQL array
    UPDATE public.py_tuple_iterator_object SET it_index = v_index + 1 WHERE ob_base = iter_id;
    RETURN v_value;
END;
$$ LANGUAGE plpgsql;

-- py_dict_keyiterator_tp_iternext: dict_keyiterator.__next__()
-- Iterates dict keys in insertion order using py_dict_entry row ordering.
CREATE OR REPLACE FUNCTION public.py_dict_keyiterator_tp_iternext(iter_id UUID)
RETURNS UUID AS $$
DECLARE
    v_dict UUID;
    v_pos INTEGER;
    v_key UUID;
BEGIN
    SELECT it_dict, it_pos INTO v_dict, v_pos
    FROM public.py_dict_keyiterator_object WHERE ob_base = iter_id;

    -- Get the key at position v_pos (0-based offset), ordered by insertion order (id)
    SELECT me_key INTO v_key
    FROM public.py_dict_entry
    WHERE dict_id = v_dict
    ORDER BY id
    LIMIT 1 OFFSET v_pos;

    IF v_key IS NULL THEN
        PERFORM public.py_err_set_stop_iteration();
        RETURN NULL;
    END IF;

    UPDATE public.py_dict_keyiterator_object SET it_pos = v_pos + 1 WHERE ob_base = iter_id;
    RETURN v_key;
END;
$$ LANGUAGE plpgsql;

-- py_str_iterator_tp_iternext: str_iterator.__next__()
-- Iterates characters of a string one at a time.
CREATE OR REPLACE FUNCTION public.py_str_iterator_tp_iternext(iter_id UUID)
RETURNS UUID AS $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    v_seq UUID;
    v_index INTEGER;
    v_str TEXT;
    v_len INTEGER;
    v_char TEXT;
    v_char_id UUID;
BEGIN
    SELECT it_seq, it_index INTO v_seq, v_index
    FROM public.py_str_iterator_object WHERE ob_base = iter_id;

    SELECT str_value INTO v_str FROM public.py_unicode_object WHERE ob_base = v_seq;
    v_len := char_length(v_str);

    IF v_index >= v_len THEN
        PERFORM public.py_err_set_stop_iteration();
        RETURN NULL;
    END IF;

    v_char := substring(v_str FROM v_index + 1 FOR 1);
    v_char_id := public.py_str_from_text(v_char);

    UPDATE public.py_str_iterator_object SET it_index = v_index + 1 WHERE ob_base = iter_id;
    RETURN v_char_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register tp_iter on container types, tp_iternext on iterator types
-- ============================================================================

-- Container types get tp_iter
UPDATE public.py_type_object SET tp_iter = 'py_list_tp_iter'::regproc
WHERE ob_base = '00000000-0000-4000-a000-000000000005'; -- list

UPDATE public.py_type_object SET tp_iter = 'py_tuple_tp_iter'::regproc
WHERE ob_base = '00000000-0000-4000-a000-000000000007'; -- tuple

UPDATE public.py_type_object SET tp_iter = 'py_dict_tp_iter'::regproc
WHERE ob_base = '00000000-0000-4000-a000-000000000006'; -- dict

UPDATE public.py_type_object SET tp_iter = 'py_unicode_tp_iter'::regproc
WHERE ob_base = '00000000-0000-4000-a000-000000000003'; -- str

-- Iterator types get tp_iternext (and tp_iter returning self is handled in GET_ITER)
UPDATE public.py_type_object SET tp_iternext = 'py_list_iterator_tp_iternext'::regproc
WHERE ob_base = '00000000-0000-4000-a000-000000000031'; -- list_iterator

UPDATE public.py_type_object SET tp_iternext = 'py_tuple_iterator_tp_iternext'::regproc
WHERE ob_base = '00000000-0000-4000-a000-000000000032'; -- tuple_iterator

UPDATE public.py_type_object SET tp_iternext = 'py_dict_keyiterator_tp_iternext'::regproc
WHERE ob_base = '00000000-0000-4000-a000-000000000033'; -- dict_keyiterator

UPDATE public.py_type_object SET tp_iternext = 'py_str_iterator_tp_iternext'::regproc
WHERE ob_base = '00000000-0000-4000-a000-000000000034'; -- str_iterator
