-- ============================================================================
-- Migration: nb_positive Slot (CPython PyNumber_Positive)
-- 20260114235502
--
-- UNARY_POSITIVE(10): pop TOS, push +TOS via nb_positive. CPython: +x often returns same object.
-- int/float: return same object (no-op for numbers).
-- Depends: 235501, 220000 (py_number_methods.nb_positive).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_positive(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = obj_id) THEN
        RETURN id_not_implemented;
    END IF;
    RETURN obj_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_float_nb_positive(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = obj_id) THEN
        RETURN id_not_implemented;
    END IF;
    RETURN obj_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_positive(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    type_id uuid;
    num_methods_id uuid;
    nb_pos regproc;
    res uuid;
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    type_name text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_object WHERE id = obj_id) THEN
        RAISE EXCEPTION 'py_object_positive: object % does not exist', obj_id;
    END IF;
    SELECT ob_type INTO type_id FROM public.py_object WHERE id = obj_id;
    IF type_id IS NULL THEN
        PERFORM public.py_err_set_type_error('bad operand type for unary +: ''NoneType''');
        RETURN NULL;
    END IF;
    SELECT tp_as_number INTO num_methods_id FROM public.py_type_object WHERE ob_base = type_id;
    IF num_methods_id IS NULL THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        PERFORM public.py_err_set_type_error('bad operand type for unary +: ''' || COALESCE(type_name, 'unknown') || '''');
        RETURN NULL;
    END IF;
    SELECT nb_positive INTO nb_pos FROM public.py_number_methods WHERE id = num_methods_id;
    IF nb_pos IS NULL THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        PERFORM public.py_err_set_type_error('bad operand type for unary +: ''' || COALESCE(type_name, 'unknown') || '''');
        RETURN NULL;
    END IF;
    EXECUTE format('SELECT %I($1)', nb_pos::text) USING obj_id INTO res;
    IF res = id_not_implemented THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        PERFORM public.py_err_set_type_error('bad operand type for unary +: ''' || COALESCE(type_name, 'unknown') || '''');
        RETURN NULL;
    END IF;
    RETURN res;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    id_int   uuid := '00000000-0000-4000-a000-000000000004';
    id_float uuid := '00000000-0000-4000-a000-000000000009';
    num_id uuid;
BEGIN
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = id_int;
    IF num_id IS NOT NULL THEN
        UPDATE public.py_number_methods SET nb_positive = 'py_long_nb_positive'::regproc WHERE id = num_id;
    END IF;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = id_float;
    IF num_id IS NOT NULL THEN
        UPDATE public.py_number_methods SET nb_positive = 'py_float_nb_positive'::regproc WHERE id = num_id;
    END IF;
END $$;
