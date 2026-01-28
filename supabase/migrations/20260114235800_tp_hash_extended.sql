-- ============================================================================
-- Migration: tp_hash Extended (bytes, float, bool, None, tuple)
-- Created: 2026-01-14 23:58:00
--
-- Purpose:
--   Registers tp_hash for bytes, float, bool, NoneType, tuple so hashable
--   scope matches CPython. No tp_name branching; type identified by concrete
--   table existence only. Design: docs/CHANGE_2_TP_HASH_EXTENDED_PLAN.md
--
-- CPython:
--   bytes, float, bool, None, tuple are hashable. tuple is hashable iff
--   all elements are hashable; hash combines element hashes (tuplehash).
-- ============================================================================

-- ============================================================================
-- Type-specific hash (table existence only; no tp_name)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_bytes_hash(obj_id uuid)
RETURNS bigint AS $$
DECLARE
    bval bytea;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_bytes_object WHERE ob_base = obj_id) THEN
        RAISE EXCEPTION 'TypeError: py_bytes_hash called on non-bytes object';
    END IF;
    SELECT bytes_value INTO bval FROM public.py_bytes_object WHERE ob_base = obj_id;
    IF bval IS NULL OR length(bval) = 0 THEN
        RETURN 0;
    END IF;
    -- Deterministic hash of byte string. CPython has bytes_hash; we use encode+hashtext.
    RETURN hashtext(encode(bval, 'hex'))::bigint;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_float_hash(obj_id uuid)
RETURNS bigint AS $$
DECLARE
    fval double precision;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = obj_id) THEN
        RAISE EXCEPTION 'TypeError: py_float_hash called on non-float object';
    END IF;
    SELECT ob_fval INTO fval FROM public.py_float_object WHERE ob_base = obj_id;
    -- CPython uses _Py_HashDouble. We use deterministic text representation hash.
    RETURN hashtext(fval::text)::bigint;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_bool_hash(obj_id uuid)
RETURNS bigint AS $$
DECLARE
    bval boolean;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_bool_object WHERE ob_base = obj_id) THEN
        RAISE EXCEPTION 'TypeError: py_bool_hash called on non-bool object';
    END IF;
    SELECT bool_value INTO bval FROM public.py_bool_object WHERE ob_base = obj_id;
    -- CPython: hash(True)==1, hash(False)==0
    RETURN CASE WHEN bval THEN 1 ELSE 0 END;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_none_hash(obj_id uuid)
RETURNS bigint AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_none_object WHERE ob_base = obj_id) THEN
        RAISE EXCEPTION 'TypeError: py_none_hash called on non-None object';
    END IF;
    -- None is a singleton; return fixed constant. CPython uses id-based value.
    RETURN 0;
END;
$$ LANGUAGE plpgsql;

-- py_tuple_hash: hashable iff all elements hashable; combine element hashes (CPython tuplehash style)
CREATE OR REPLACE FUNCTION public.py_tuple_hash(obj_id uuid)
RETURNS bigint AS $$
DECLARE
    items uuid[];
    n int;
    i int;
    h bigint;
    total numeric := 0;
    mult constant numeric := 1000003;
    lim64 constant numeric := 18446744073709551616;
    mid   constant numeric := 9223372036854775808;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_tuple_object WHERE ob_base = obj_id) THEN
        RAISE EXCEPTION 'TypeError: py_tuple_hash called on non-tuple object';
    END IF;
    SELECT ob_item INTO items FROM public.py_tuple_object WHERE ob_base = obj_id;
    n := coalesce(array_length(items, 1), 0);
    IF n = 0 THEN
        RETURN 0;
    END IF;
    FOR i IN 1..n LOOP
        h := public.py_object_hash(items[i]);
        total := (total * mult + h);
    END LOOP;
    total := mod(total + n, lim64);
    IF total >= mid THEN
        total := total - lim64;
    END IF;
    RETURN total::bigint;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register tp_hash for bytes, float, bool, NoneType, tuple
-- ============================================================================

DO $$
DECLARE
    id_bytes  uuid := '00000000-0000-4000-a000-000000000012';
    id_float  uuid := '00000000-0000-4000-a000-000000000009';
    id_bool   uuid := '00000000-0000-4000-a000-000000000013';
    id_none   uuid := '00000000-0000-4000-a000-000000000008';
    id_tuple  uuid := '00000000-0000-4000-a000-000000000007';
BEGIN
    UPDATE public.py_type_object SET tp_hash = 'py_bytes_hash'::regproc  WHERE ob_base = id_bytes;
    UPDATE public.py_type_object SET tp_hash = 'py_float_hash'::regproc  WHERE ob_base = id_float;
    UPDATE public.py_type_object SET tp_hash = 'py_bool_hash'::regproc   WHERE ob_base = id_bool;
    UPDATE public.py_type_object SET tp_hash = 'py_none_hash'::regproc   WHERE ob_base = id_none;
    UPDATE public.py_type_object SET tp_hash = 'py_tuple_hash'::regproc  WHERE ob_base = id_tuple;
END $$;
