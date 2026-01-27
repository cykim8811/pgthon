-- ============================================================================
-- Migration: tp_richcompare Full Op Set (Py_LT .. Py_GE) for str and int
-- Created: 2026-01-14 23:70:00
--
-- Purpose:
--   Extends py_unicode_richcompare and py_long_richcompare to implement all
--   six rich comparison ops (Py_LT=0, Py_LE=1, Py_EQ=2, Py_NE=3, Py_GT=4, Py_GE=5)
--   per CPython semantics. No new slots or schema; only replaces the two
--   type-specific functions already registered in 236000.
--
-- CPython:
--   - str: lexicographic comparison for all six ops; other type -> NotImplemented
--   - int: numeric comparison for all six ops; other type -> NotImplemented
--
-- ============================================================================

-- Singleton IDs (must match bootstrap)
-- True: 00000000-0000-4000-b000-000000000010
-- False: 00000000-0000-4000-b000-000000000011
-- NotImplemented: 00000000-0000-4000-b000-000000000012

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
