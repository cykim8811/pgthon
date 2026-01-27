-- ============================================================================
-- Migration: tp_richcompare Slot (CPython Rich Comparison Protocol)
-- Created: 2026-01-14 23:60:00
--
-- Purpose:
--   Implements CPython's tp_richcompare slot for key equality in dict lookup.
--   Design: docs/DICT_LOOKUP_DESIGN.md §7. Dict key equality uses
--   py_object_richcompare_eq (which dispatches via tp_richcompare) instead of
--   the type‑branching py_object_equals_key.
--
-- CPython:
--   richcmpfunc tp_richcompare;  // (PyObject *, PyObject *, int) -> PyObject*
--   Opcodes: Py_LT=0, Py_LE=1, Py_EQ=2, Py_NE=3, Py_GT=4, Py_GE=5 (object.h)
--   Returns Py_True, Py_False, or Py_NotImplemented.
--
-- This migration:
--   1. Defines type-specific richcompare for str (Py_EQ) and int (Py_EQ)
--   2. Defines py_object_richcompare (dispatch) and py_object_richcompare_eq
--   3. Registers tp_richcompare for str and int
--   4. Switches py_dict_get_item / py_dict_set_item to py_object_richcompare_eq
--   (tp_richcompare column is defined in 20260114220000_python_object_schema.sql)
--
-- Singleton IDs must match bootstrap (20260114223000_python_bootstrap.sql).
-- tp_richcompare column is defined in py_type_object (20260114220000_python_object_schema.sql).
-- ============================================================================

-- Opcode constants (CPython Include/object.h)
-- Py_LT=0, Py_LE=1, Py_EQ=2, Py_NE=3, Py_GT=4, Py_GE=5

COMMENT ON COLUMN public.py_type_object.tp_richcompare IS
'tp_richcompare slot: (self_id uuid, other_id uuid, op integer) returns uuid. op: 0=LT,1=LE,2=EQ,3=NE,4=GT,5=GE (CPython int). Return True/False/NotImplemented object id.';

-- ============================================================================
-- Type-specific richcompare (Py_EQ only for str/int; others -> NotImplemented)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_unicode_richcompare(
    self_id uuid, other_id uuid, op integer)
RETURNS uuid AS $$
DECLARE
    sid uuid := '00000000-0000-4000-b000-000000000012'; -- NotImplemented
    tid uuid := '00000000-0000-4000-b000-000000000010'; -- True
    fid uuid := '00000000-0000-4000-b000-000000000011'; -- False
    sval text;
    oval text;
BEGIN
    IF op <> 2 THEN  -- Py_EQ
        RETURN sid;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = other_id) THEN
        RETURN sid;
    END IF;
    SELECT str_value INTO sval FROM public.py_unicode_object WHERE ob_base = self_id;
    SELECT str_value INTO oval FROM public.py_unicode_object WHERE ob_base = other_id;
    IF sval IS NOT DISTINCT FROM oval THEN
        RETURN tid;
    END IF;
    RETURN fid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_long_richcompare(
    self_id uuid, other_id uuid, op integer)
RETURNS uuid AS $$
DECLARE
    sid uuid := '00000000-0000-4000-b000-000000000012';
    tid uuid := '00000000-0000-4000-b000-000000000010';
    fid uuid := '00000000-0000-4000-b000-000000000011';
    sval numeric;
    oval numeric;
BEGIN
    IF op <> 2 THEN
        RETURN sid;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = other_id) THEN
        RETURN sid;
    END IF;
    SELECT long_value INTO sval FROM public.py_long_object WHERE ob_base = self_id;
    SELECT long_value INTO oval FROM public.py_long_object WHERE ob_base = other_id;
    IF sval IS NOT DISTINCT FROM oval THEN
        RETURN tid;
    END IF;
    RETURN fid;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Dispatch and dict-key equality helper
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_richcompare(
    self_id uuid, other_id uuid, op integer)
RETURNS uuid AS $$
DECLARE
    type_id uuid;
    rcf regproc;
    res uuid;
    not_impl uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    SELECT ob_type INTO type_id FROM public.py_object WHERE id = self_id;
    IF type_id IS NULL THEN
        RETURN not_impl;
    END IF;
    SELECT tp_richcompare INTO rcf
    FROM public.py_type_object WHERE ob_base = type_id;
    IF rcf IS NULL THEN
        RETURN not_impl;
    END IF;
    EXECUTE format('SELECT %I($1::uuid, $2::uuid, $3::integer)', rcf::text)
    USING self_id, other_id, op INTO res;
    RETURN res;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_richcompare_eq(a_id uuid, b_id uuid)
RETURNS boolean AS $$
DECLARE
    tid uuid := '00000000-0000-4000-b000-000000000010';
    fid uuid := '00000000-0000-4000-b000-000000000011';
    nid uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    res2 uuid;
BEGIN
    IF a_id IS NULL OR b_id IS NULL THEN
        RETURN FALSE;
    END IF;
    IF a_id = b_id THEN
        RETURN TRUE;
    END IF;
    res := public.py_object_richcompare(a_id, b_id, 2);
    IF res = tid THEN
        RETURN TRUE;
    END IF;
    IF res = fid THEN
        RETURN FALSE;
    END IF;
    IF res = nid THEN
        res2 := public.py_object_richcompare(b_id, a_id, 2);
        RETURN (res2 = tid);
    END IF;
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register tp_richcompare for str and int
-- ============================================================================

DO $$
DECLARE
    id_str uuid := '00000000-0000-4000-a000-000000000003';
    id_int uuid := '00000000-0000-4000-a000-000000000004';
BEGIN
    UPDATE public.py_type_object
    SET tp_richcompare = 'py_unicode_richcompare'::regproc
    WHERE ob_base = id_str;
    UPDATE public.py_type_object
    SET tp_richcompare = 'py_long_richcompare'::regproc
    WHERE ob_base = id_int;
END $$;

-- ============================================================================
-- Dict API: use py_object_richcompare_eq for key equality (§7.5)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_dict_get_item(dict_id uuid, key_id uuid)
RETURNS uuid AS $$
DECLARE
    h bigint;
    val_id uuid;
BEGIN
    h := public.py_object_hash(key_id);
    SELECT e.me_value INTO val_id
    FROM public.py_dict_entry e
    WHERE e.dict_id = py_dict_get_item.dict_id
      AND e.me_hash = h
      AND public.py_object_richcompare_eq(e.me_key, key_id)
    LIMIT 1;
    RETURN val_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_dict_set_item(
    dict_id uuid, key_id uuid, value_id uuid)
RETURNS void AS $$
DECLARE
    h bigint;
    entry_id uuid;
BEGIN
    h := public.py_object_hash(key_id);
    SELECT e.id INTO entry_id
    FROM public.py_dict_entry e
    WHERE e.dict_id = py_dict_set_item.dict_id
      AND e.me_hash = h
      AND public.py_object_richcompare_eq(e.me_key, key_id)
    LIMIT 1;

    IF entry_id IS NOT NULL THEN
        UPDATE public.py_dict_entry SET me_value = value_id WHERE id = entry_id;
    ELSE
        INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
        VALUES (py_dict_set_item.dict_id, key_id, value_id, h);
    END IF;
END;
$$ LANGUAGE plpgsql;
