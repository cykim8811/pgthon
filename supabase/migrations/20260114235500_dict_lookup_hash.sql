-- ============================================================================
-- Migration: Dict Lookup Hash-Based (CPython PyDictKeyEntry.me_hash)
-- Created: 2026-01-14 23:55:00
--
-- Purpose:
--   Implements hash-based dict lookup per CPython semantics: key hash narrows
--   candidates, then key equality decides the match. No string-only or
--   identity-only workarounds.
--
-- CPython:
--   PyDict_GetItem / PyDict_SetItem use _PyObject_HashFast(key) and
--   PyObject_RichCompareBool(me_key, key, Py_EQ). Entries store me_hash.
--
-- This migration:
--   1. Backfills py_dict_entry.me_hash and enforces NOT NULL
--   2. Adds index (dict_id, me_hash) for hash-narrowed lookup
--   3. Defines py_object_equals_key (1단계: str/int value comparison; else FALSE)
--   4. Defines py_dict_get_item, py_dict_set_item
--   5. Replaces LOAD_NAME / STORE_NAME to use the dict API only
--
-- Design: docs/DICT_LOOKUP_DESIGN.md
-- ============================================================================

-- ============================================================================
-- 1. Ensure me_hash column exists, then backfill and set NOT NULL
-- ============================================================================
-- python_object_schema (20000) adds me_hash nullable. If this migration runs
-- against an DB that applied 20000 before that edit, add the column here.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'py_dict_entry' AND column_name = 'me_hash'
    ) THEN
        ALTER TABLE public.py_dict_entry ADD COLUMN me_hash bigint;
    END IF;
END $$;

UPDATE public.py_dict_entry e
SET me_hash = public.py_object_hash(e.me_key)
WHERE e.me_hash IS NULL;

ALTER TABLE public.py_dict_entry
ALTER COLUMN me_hash SET NOT NULL;

-- ============================================================================
-- 2. Index for hash-narrowed lookup
-- ============================================================================
CREATE INDEX idx_py_dict_entry_dict_id_me_hash
ON public.py_dict_entry (dict_id, me_hash);

-- ============================================================================
-- 3. Key equality (1단계): type-based value comparison, no id fallback
-- ============================================================================
-- CPython: PyObject_RichCompareBool(a, b, Py_EQ) via tp_richcompare.
-- 1단계: str → str_value, int → long_value. Other types: no comparison (FALSE).
-- 2단계 will use py_object_richcompare_eq (tp_richcompare). See DICT_LOOKUP_DESIGN §7.

CREATE OR REPLACE FUNCTION public.py_object_equals_key(a_id UUID, b_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    type_a_id UUID;
    type_b_id UUID;
    tp_name_a TEXT;
    tp_name_b TEXT;
    str_a TEXT;
    str_b TEXT;
    long_a NUMERIC;
    long_b NUMERIC;
BEGIN
    IF a_id IS NULL OR b_id IS NULL THEN
        RETURN FALSE;
    END IF;
    IF a_id = b_id THEN
        RETURN TRUE;
    END IF;

    SELECT ob_type INTO type_a_id FROM public.py_object WHERE id = a_id;
    SELECT ob_type INTO type_b_id FROM public.py_object WHERE id = b_id;
    IF type_a_id IS NULL OR type_b_id IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT tp_name INTO tp_name_a FROM public.py_type_object WHERE ob_base = type_a_id;
    SELECT tp_name INTO tp_name_b FROM public.py_type_object WHERE ob_base = type_b_id;

    IF tp_name_a = 'str' AND tp_name_b = 'str' THEN
        SELECT str_value INTO str_a FROM public.py_unicode_object WHERE ob_base = a_id;
        SELECT str_value INTO str_b FROM public.py_unicode_object WHERE ob_base = b_id;
        RETURN (str_a IS NOT DISTINCT FROM str_b);
    END IF;

    IF tp_name_a = 'int' AND tp_name_b = 'int' THEN
        SELECT long_value INTO long_a FROM public.py_long_object WHERE ob_base = a_id;
        SELECT long_value INTO long_b FROM public.py_long_object WHERE ob_base = b_id;
        RETURN (long_a IS NOT DISTINCT FROM long_b);
    END IF;

    -- Other types: 1단계에서는 동등성 비교하지 않음. tp_richcompare 있을 때만 비교 (2단계).
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 4. Dict API: get_item, set_item
-- ============================================================================

-- py_dict_get_item: CPython PyDict_GetItem semantics. Hash narrows, equality confirms.
CREATE OR REPLACE FUNCTION public.py_dict_get_item(dict_id UUID, key_id UUID)
RETURNS UUID AS $$
DECLARE
    h BIGINT;
    val_id UUID;
BEGIN
    h := public.py_object_hash(key_id);
    SELECT e.me_value INTO val_id
    FROM public.py_dict_entry e
    WHERE e.dict_id = py_dict_get_item.dict_id
      AND e.me_hash = h
      AND public.py_object_equals_key(e.me_key, key_id)
    LIMIT 1;
    RETURN val_id;
END;
$$ LANGUAGE plpgsql;

-- py_dict_set_item: CPython dict-assignment semantics. Insert or update by key equality.
CREATE OR REPLACE FUNCTION public.py_dict_set_item(dict_id UUID, key_id UUID, value_id UUID)
RETURNS VOID AS $$
DECLARE
    h BIGINT;
    entry_id UUID;
BEGIN
    h := public.py_object_hash(key_id);
    SELECT e.id INTO entry_id
    FROM public.py_dict_entry e
    WHERE e.dict_id = py_dict_set_item.dict_id
      AND e.me_hash = h
      AND public.py_object_equals_key(e.me_key, key_id)
    LIMIT 1;

    IF entry_id IS NOT NULL THEN
        UPDATE public.py_dict_entry SET me_value = value_id WHERE id = entry_id;
    ELSE
        INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
        VALUES (py_dict_set_item.dict_id, key_id, value_id, h);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. LOAD_NAME / STORE_NAME use dict API only
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_STORE_NAME(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    f_locals_id UUID;
    value_obj_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'STORE_NAME: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Index % out of range for co_names tuple', name_index;
    END IF;
    SELECT f_locals INTO f_locals_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF f_locals_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Frame with id % does not have f_locals', frame_id;
    END IF;

    value_obj_id := public.py_stack_pop(frame_id);
    PERFORM public.py_dict_set_item(f_locals_id, name_str_id, value_obj_id);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_NAME(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    name_str TEXT;
    obj_id UUID;
    f_locals_id UUID;
    f_globals_id UUID;
    f_builtins_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'LOAD_NAME: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Index % out of range for co_names tuple', name_index;
    END IF;
    SELECT str_value INTO name_str FROM public.py_unicode_object WHERE ob_base = name_str_id;

    SELECT f_locals, f_globals, f_builtins INTO f_locals_id, f_globals_id, f_builtins_id
    FROM public.py_frame_object WHERE ob_base = frame_id;
    IF f_locals_id IS NULL OR f_globals_id IS NULL OR f_builtins_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Frame with id % does not have all required namespaces (locals, globals, builtins)', frame_id;
    END IF;

    -- Lookup order: locals → globals → builtins (CPython)
    obj_id := public.py_dict_get_item(f_locals_id, name_str_id);
    IF obj_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;
    obj_id := public.py_dict_get_item(f_globals_id, name_str_id);
    IF obj_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;
    obj_id := public.py_dict_get_item(f_builtins_id, name_str_id);
    IF obj_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;

    RAISE EXCEPTION 'NameError: name ''%'' is not defined', COALESCE(name_str, 'unknown');
END;
$$ LANGUAGE plpgsql;
