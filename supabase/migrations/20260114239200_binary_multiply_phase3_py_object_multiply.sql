-- ============================================================================
-- Migration: BINARY_MULTIPLY Phase 3 — py_object_multiply (PyNumber_Multiply 대응)
-- Created: 2026-01-14 23:92:00
--
-- Purpose:
--   CPython PyNumber_Multiply(v,w): (1) nb_multiply (2) left의 sq_repeat(left, right_as_int)
--   (3) right의 sq_repeat(right, left_as_int) (4) TypeError.
--
-- Design: docs/BINARY_MULTIPLY_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- ============================================================================
-- H: py_object_multiply(left_id, right_id)
--    (1) py_object_multiply_via_nb (2) left sq_repeat(left, right_as_int)
--    (3) right sq_repeat(right, left_as_int) (4) TypeError
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_multiply(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    n_val numeric;
    n_int integer;
    left_type_id uuid;
    right_type_id uuid;
    left_tp_name text;
    right_tp_name text;
BEGIN
    res := public.py_object_multiply_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN
        RETURN res;
    END IF;

    -- Try left's sq_repeat(left, right) when right is int
    SELECT long_value INTO n_val FROM public.py_long_object WHERE ob_base = right_id;
    IF n_val IS NOT NULL THEN
        n_int := n_val::integer;
        res := public.py_sequence_repeat(left_id, n_int);
        IF res IS NOT NULL THEN
            RETURN res;
        END IF;
    END IF;

    -- Try right's sq_repeat(right, left) when left is int
    SELECT long_value INTO n_val FROM public.py_long_object WHERE ob_base = left_id;
    IF n_val IS NOT NULL THEN
        n_int := n_val::integer;
        res := public.py_sequence_repeat(right_id, n_int);
        IF res IS NOT NULL THEN
            RETURN res;
        END IF;
    END IF;

    SELECT ob_type INTO left_type_id FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for *: ''%'' and ''%''',
        COALESCE(left_tp_name, 'None'), COALESCE(right_tp_name, 'None');
END;
$$ LANGUAGE plpgsql;
