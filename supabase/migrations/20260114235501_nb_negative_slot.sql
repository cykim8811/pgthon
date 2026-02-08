-- ============================================================================
-- Migration: nb_negative Slot (CPython PyNumber_Negative)
-- 20260114235501
--
-- UNARY_NEGATIVE(11): pop TOS, push -TOS via tp_as_number->nb_negative.
-- int/float: py_long_nb_negative, py_float_nb_negative; dispatch: py_object_negative.
-- Depends: 235500 (tp_as_number, nb_absolute), 220000 (py_number_methods.nb_negative).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_negative(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    val numeric;
    id_int_type uuid := '00000000-0000-4000-a000-000000000004';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = obj_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT long_value INTO val FROM public.py_long_object WHERE ob_base = obj_id;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, -val);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_float_nb_negative(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    val double precision;
    id_float_type uuid := '00000000-0000-4000-a000-000000000009';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = obj_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT ob_fval INTO val FROM public.py_float_object WHERE ob_base = obj_id;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_float_type);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (result_id, -val);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_negative(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    type_id uuid;
    num_methods_id uuid;
    nb_neg regproc;
    res uuid;
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    type_name text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_object WHERE id = obj_id) THEN
        RAISE EXCEPTION 'py_object_negative: object % does not exist', obj_id;
    END IF;
    SELECT ob_type INTO type_id FROM public.py_object WHERE id = obj_id;
    IF type_id IS NULL THEN
        PERFORM public.py_err_set_type_error('bad operand type for unary -: ''NoneType''');
        RETURN NULL;
    END IF;
    SELECT tp_as_number INTO num_methods_id FROM public.py_type_object WHERE ob_base = type_id;
    IF num_methods_id IS NULL THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        PERFORM public.py_err_set_type_error('bad operand type for unary -: ''' || COALESCE(type_name, 'unknown') || '''');
        RETURN NULL;
    END IF;
    SELECT nb_negative INTO nb_neg FROM public.py_number_methods WHERE id = num_methods_id;
    IF nb_neg IS NULL THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        PERFORM public.py_err_set_type_error('bad operand type for unary -: ''' || COALESCE(type_name, 'unknown') || '''');
        RETURN NULL;
    END IF;
    EXECUTE format('SELECT %I($1)', nb_neg::text) USING obj_id INTO res;
    IF res = id_not_implemented THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        PERFORM public.py_err_set_type_error('bad operand type for unary -: ''' || COALESCE(type_name, 'unknown') || '''');
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
        UPDATE public.py_number_methods SET nb_negative = 'py_long_nb_negative'::regproc WHERE id = num_id;
    END IF;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = id_float;
    IF num_id IS NOT NULL THEN
        UPDATE public.py_number_methods SET nb_negative = 'py_float_nb_negative'::regproc WHERE id = num_id;
    END IF;
END $$;
