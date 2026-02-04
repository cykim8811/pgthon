-- ============================================================================
-- Migration: tp_richcompare Slot (CPython Rich Comparison Protocol)
-- 20260114234900 — runs before 235000_tp_hash_slot (tp_hash_slot uses py_object_richcompare_eq).
--
-- Purpose:
--   Implements CPython's tp_richcompare slot for key equality in dict lookup.
--   Design: docs/DICT_LOOKUP_DESIGN.md §7. Dict key equality uses
--   py_object_richcompare_eq (which dispatches via tp_richcompare) for dict key equality.
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
    sid uuid := '00000000-0000-4000-b000-000000000012';
    tid uuid := '00000000-0000-4000-b000-000000000010';
    fid uuid := '00000000-0000-4000-b000-000000000011';
    sval text;
    oval text;
    cmp boolean;
BEGIN
    IF op NOT IN (0, 1, 2, 3, 4, 5) THEN
        RETURN sid;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = other_id) THEN
        RETURN sid;
    END IF;
    SELECT str_value INTO sval FROM public.py_unicode_object WHERE ob_base = self_id;
    SELECT str_value INTO oval FROM public.py_unicode_object WHERE ob_base = other_id;

    CASE op
        WHEN 0 THEN cmp := (sval < oval);   -- Py_LT
        WHEN 1 THEN cmp := (sval <= oval);  -- Py_LE
        WHEN 2 THEN RETURN CASE WHEN sval IS NOT DISTINCT FROM oval THEN tid ELSE fid END;  -- Py_EQ
        WHEN 3 THEN cmp := (sval IS DISTINCT FROM oval);  -- Py_NE
        WHEN 4 THEN cmp := (sval > oval);   -- Py_GT
        WHEN 5 THEN cmp := (sval >= oval);  -- Py_GE
        ELSE RETURN sid;
    END CASE;

    IF op IN (0, 1, 3, 4, 5) THEN
        RETURN CASE WHEN cmp THEN tid ELSE fid END;
    END IF;
    RETURN sid;
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
    cmp boolean;
BEGIN
    IF op NOT IN (0, 1, 2, 3, 4, 5) THEN
        RETURN sid;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = other_id) THEN
        RETURN sid;
    END IF;
    SELECT long_value INTO sval FROM public.py_long_object WHERE ob_base = self_id;
    SELECT long_value INTO oval FROM public.py_long_object WHERE ob_base = other_id;

    CASE op
        WHEN 0 THEN cmp := (sval < oval);   -- Py_LT
        WHEN 1 THEN cmp := (sval <= oval);  -- Py_LE
        WHEN 2 THEN RETURN CASE WHEN sval IS NOT DISTINCT FROM oval THEN tid ELSE fid END;  -- Py_EQ
        WHEN 3 THEN cmp := (sval IS DISTINCT FROM oval);  -- Py_NE
        WHEN 4 THEN cmp := (sval > oval);   -- Py_GT
        WHEN 5 THEN cmp := (sval >= oval);  -- Py_GE
        ELSE RETURN sid;
    END CASE;

    IF op IN (0, 1, 3, 4, 5) THEN
        RETURN CASE WHEN cmp THEN tid ELSE fid END;
    END IF;
    RETURN sid;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_float_richcompare(self_id, other_id, op) — float vs float, float vs int (CPython coercion)
--    self는 float(디스패치에서 float일 때만 호출). other가 float면 ob_fval 비교; other가 int면 long_value를 double로 변환 후 비교.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_float_richcompare(
    self_id uuid, other_id uuid, op integer)
RETURNS uuid AS $$
DECLARE
    sid uuid := '00000000-0000-4000-b000-000000000012';
    tid uuid := '00000000-0000-4000-b000-000000000010';
    fid uuid := '00000000-0000-4000-b000-000000000011';
    sval double precision;
    oval double precision;
    oval_long numeric;
    cmp boolean;
BEGIN
    IF op NOT IN (0, 1, 2, 3, 4, 5) THEN
        RETURN sid;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = self_id) THEN
        RETURN sid;
    END IF;
    SELECT ob_fval INTO sval FROM public.py_float_object WHERE ob_base = self_id;
    IF EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = other_id) THEN
        SELECT ob_fval INTO oval FROM public.py_float_object WHERE ob_base = other_id;
    ELSIF EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = other_id) THEN
        SELECT long_value INTO oval_long FROM public.py_long_object WHERE ob_base = other_id;
        oval := oval_long::double precision;
    ELSE
        RETURN sid;
    END IF;

    CASE op
        WHEN 0 THEN cmp := (sval < oval);   -- Py_LT
        WHEN 1 THEN cmp := (sval <= oval);  -- Py_LE
        WHEN 2 THEN RETURN CASE WHEN sval IS NOT DISTINCT FROM oval THEN tid ELSE fid END;  -- Py_EQ
        WHEN 3 THEN cmp := (sval IS DISTINCT FROM oval);  -- Py_NE
        WHEN 4 THEN cmp := (sval > oval);   -- Py_GT
        WHEN 5 THEN cmp := (sval >= oval);  -- Py_GE
        ELSE RETURN sid;
    END CASE;

    IF op IN (0, 1, 3, 4, 5) THEN
        RETURN CASE WHEN cmp THEN tid ELSE fid END;
    END IF;
    RETURN sid;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_bytes_richcompare(self_id, other_id, op) — bytes vs bytes only (lexicographic)
--    self는 bytes(디스패치에서 bytes일 때만 호출). other가 bytes가 아니면 NotImplemented.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_bytes_richcompare(
    self_id uuid, other_id uuid, op integer)
RETURNS uuid AS $$
DECLARE
    sid uuid := '00000000-0000-4000-b000-000000000012';
    tid uuid := '00000000-0000-4000-b000-000000000010';
    fid uuid := '00000000-0000-4000-b000-000000000011';
    sval bytea;
    oval bytea;
    cmp boolean;
BEGIN
    IF op NOT IN (0, 1, 2, 3, 4, 5) THEN
        RETURN sid;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_bytes_object WHERE ob_base = self_id) THEN
        RETURN sid;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_bytes_object WHERE ob_base = other_id) THEN
        RETURN sid;
    END IF;
    SELECT bytes_value INTO sval FROM public.py_bytes_object WHERE ob_base = self_id;
    SELECT bytes_value INTO oval FROM public.py_bytes_object WHERE ob_base = other_id;

    CASE op
        WHEN 0 THEN cmp := (sval < oval);   -- Py_LT
        WHEN 1 THEN cmp := (sval <= oval);   -- Py_LE
        WHEN 2 THEN RETURN CASE WHEN sval IS NOT DISTINCT FROM oval THEN tid ELSE fid END;  -- Py_EQ
        WHEN 3 THEN cmp := (sval IS DISTINCT FROM oval);  -- Py_NE
        WHEN 4 THEN cmp := (sval > oval);   -- Py_GT
        WHEN 5 THEN cmp := (sval >= oval);  -- Py_GE
        ELSE RETURN sid;
    END CASE;

    IF op IN (0, 1, 3, 4, 5) THEN
        RETURN CASE WHEN cmp THEN tid ELSE fid END;
    END IF;
    RETURN sid;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Dispatch and dict-key equality helper
-- ============================================================================

-- py_object_richcompare: dispatch via tp_richcompare; on NotImplemented, try other's tp_richcompare with reflected op (CPython PyObject_RichCompare).
CREATE OR REPLACE FUNCTION public.py_object_richcompare(
    self_id uuid, other_id uuid, op integer)
RETURNS uuid AS $$
DECLARE
    type_id uuid;
    other_type_id uuid;
    rcf regproc;
    res uuid;
    not_impl uuid := '00000000-0000-4000-b000-000000000012';
    reflected_op integer;
BEGIN
    -- 1) left(self_id) tp_richcompare(self_id, other_id, op)
    SELECT ob_type INTO type_id FROM public.py_object WHERE id = self_id;
    IF type_id IS NULL THEN
        RETURN not_impl;
    END IF;
    SELECT tp_richcompare INTO rcf
    FROM public.py_type_object WHERE ob_base = type_id;
    IF rcf IS NULL THEN
        NULL;
    ELSE
        EXECUTE format('SELECT %I($1::uuid, $2::uuid, $3::integer)', rcf::text)
        USING self_id, other_id, op INTO res;
        IF res IS DISTINCT FROM not_impl THEN
            RETURN res;
        END IF;
    END IF;

    -- 2) NotImplemented → other's tp_richcompare(other_id, self_id, reflected_op)
    SELECT ob_type INTO other_type_id FROM public.py_object WHERE id = other_id;
    IF other_type_id IS NULL THEN
        RETURN not_impl;
    END IF;
    SELECT tp_richcompare INTO rcf
    FROM public.py_type_object WHERE ob_base = other_type_id;
    IF rcf IS NULL THEN
        RETURN not_impl;
    END IF;

    IF op IN (0, 1, 4, 5) THEN
        reflected_op := CASE op WHEN 0 THEN 4 WHEN 1 THEN 5 WHEN 4 THEN 0 WHEN 5 THEN 1 ELSE op END;
        EXECUTE format('SELECT %I($1::uuid, $2::uuid, $3::integer)', rcf::text)
        USING other_id, self_id, reflected_op INTO res;
    ELSE
        EXECUTE format('SELECT %I($1::uuid, $2::uuid, $3::integer)', rcf::text)
        USING other_id, self_id, op INTO res;
    END IF;

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
-- Register tp_richcompare for str, int, float
-- ============================================================================

DO $$
DECLARE
    id_str uuid := '00000000-0000-4000-a000-000000000003';
    id_int uuid := '00000000-0000-4000-a000-000000000004';
    id_float uuid := '00000000-0000-4000-a000-000000000009';
    id_bytes uuid := '00000000-0000-4000-a000-000000000012';
BEGIN
    UPDATE public.py_type_object
    SET tp_richcompare = 'py_unicode_richcompare'::regproc
    WHERE ob_base = id_str;
    UPDATE public.py_type_object
    SET tp_richcompare = 'py_long_richcompare'::regproc
    WHERE ob_base = id_int;
    UPDATE public.py_type_object
    SET tp_richcompare = 'py_float_richcompare'::regproc
    WHERE ob_base = id_float;
    UPDATE public.py_type_object
    SET tp_richcompare = 'py_bytes_richcompare'::regproc
    WHERE ob_base = id_bytes;
END $$;

-- py_dict_get_item and py_dict_set_item (using py_object_richcompare_eq for key equality) are defined in 20260114235000_tp_hash_slot.sql.
