-- ============================================================================
-- Migration: nb_absolute Slot (CPython PyNumber_Absolute)
-- Created: 2026-01-14 23:55:00
--
-- Purpose:
--   Implements CPython's nb_absolute via tp_as_number->nb_absolute so builtin abs()
--   uses PyNumber_Absolute semantics. CPython: PyTypeObject has tp_as_number
--   (PyNumberMethods*), and nb_absolute lives there—not on PyTypeObject directly.
--
-- CPython:
--   builtin_abs(obj) -> PyNumber_Absolute(obj)
--   PyNumber_Absolute uses Py_TYPE(obj)->tp_as_number->nb_absolute;
--   unaryfunc (PyObject*) -> PyObject*; returns new object or Py_NotImplemented.
--
-- This migration:
--   1. Creates py_number_methods (PyNumberMethods), adds tp_as_number to py_type_object
--   2. Defines py_long_nb_absolute, py_float_nb_absolute (type-specific, table existence only)
--   3. Defines py_object_absolute (dispatch via tp_as_number->nb_absolute only)
--   4. Registers nb_absolute for int and float via tp_as_number
--   5. Replaces py_builtin_abs to call py_object_absolute only
--
-- Design: docs/CHANGE_1_NB_ABSOLUTE_PLAN.md
-- ============================================================================

-- Singleton ID (must match bootstrap 20260114223000)
-- NotImplemented: 00000000-0000-4000-b000-000000000012

-- ============================================================================
-- Schema: PyNumberMethods (CPython tp_as_number)
-- ============================================================================

-- py_number_methods (Implements CPython's PyNumberMethods)
-- In CPython, PyTypeObject has PyNumberMethods *tp_as_number; nb_absolute lives here.
create table public.py_number_methods (
  id uuid primary key default gen_random_uuid(),
  -- nb_absolute: unaryfunc (PyObject*) -> PyObject*
  nb_absolute regproc
);

alter table public.py_type_object
  add column tp_as_number uuid references public.py_number_methods(id);

alter table public.py_number_methods enable row level security;
create policy "Authenticated users can view py_number_methods"
  on public.py_number_methods for select using (auth.role() = 'authenticated');

-- ============================================================================
-- Type-specific nb_absolute (table existence only; no tp_name)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_absolute(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    abs_val numeric;
    id_int_type uuid := '00000000-0000-4000-a000-000000000004';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = obj_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT long_value INTO abs_val FROM public.py_long_object WHERE ob_base = obj_id;
    abs_val := ABS(abs_val);
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, abs_val);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_float_nb_absolute(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    abs_val double precision;
    id_float_type uuid := '00000000-0000-4000-a000-000000000009';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = obj_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT ob_fval INTO abs_val FROM public.py_float_object WHERE ob_base = obj_id;
    abs_val := ABS(abs_val);
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_float_type);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (result_id, abs_val);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Dispatch: py_object_absolute (CPython PyNumber_Absolute)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_absolute(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    type_id uuid;
    num_methods_id uuid;
    nb_abs regproc;
    res uuid;
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    type_name text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_object WHERE id = obj_id) THEN
        RAISE EXCEPTION 'py_object_absolute: object % does not exist', obj_id;
    END IF;

    SELECT ob_type INTO type_id FROM public.py_object WHERE id = obj_id;
    IF type_id IS NULL THEN
        RAISE EXCEPTION 'TypeError: abs() argument must be a number, not NoneType';
    END IF;

    -- Py_TYPE(obj)->tp_as_number
    SELECT tp_as_number INTO num_methods_id
    FROM public.py_type_object
    WHERE ob_base = type_id;

    IF num_methods_id IS NULL THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        RAISE EXCEPTION 'TypeError: bad operand type for abs(): ''%''', COALESCE(type_name, 'unknown');
    END IF;

    -- tp_as_number->nb_absolute
    SELECT nb_absolute INTO nb_abs
    FROM public.py_number_methods
    WHERE id = num_methods_id;

    IF nb_abs IS NULL THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        RAISE EXCEPTION 'TypeError: bad operand type for abs(): ''%''', COALESCE(type_name, 'unknown');
    END IF;

    EXECUTE format('SELECT %I($1)', nb_abs::text) USING obj_id INTO res;

    IF res = id_not_implemented THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        RAISE EXCEPTION 'TypeError: bad operand type for abs(): ''%''', COALESCE(type_name, 'unknown');
    END IF;

    RETURN res;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register nb_absolute for int and float via tp_as_number
-- ============================================================================

DO $$
DECLARE
    id_int   uuid := '00000000-0000-4000-a000-000000000004';
    id_float uuid := '00000000-0000-4000-a000-000000000009';
    id_num_int   uuid := gen_random_uuid();
    id_num_float uuid := gen_random_uuid();
BEGIN
    INSERT INTO public.py_number_methods (id, nb_absolute)
    VALUES (id_num_int, 'py_long_nb_absolute'::regproc);

    INSERT INTO public.py_number_methods (id, nb_absolute)
    VALUES (id_num_float, 'py_float_nb_absolute'::regproc);

    UPDATE public.py_type_object SET tp_as_number = id_num_int  WHERE ob_base = id_int;
    UPDATE public.py_type_object SET tp_as_number = id_num_float WHERE ob_base = id_float;
END $$;

-- ============================================================================
-- builtin abs: use PyNumber_Absolute path only (no tp_name branching)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_builtin_abs(obj_id uuid)
RETURNS uuid AS $$
BEGIN
    RETURN public.py_object_absolute(obj_id);
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$ LANGUAGE plpgsql;
