-- ============================================================================
-- Migration: Unary Invert (~) + UNARY_INVERT opcode (15)
-- 20260114240362_unary_invert.sql
--
-- ~x for int only (float → TypeError, matching CPython).
-- Pattern follows nb_negative_slot (235501).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_invert(obj_id uuid)
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
    -- Python: ~n = -(n+1)
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, -(val + 1));
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_invert(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    type_id uuid;
    num_methods_id uuid;
    nb_inv regproc;
    res uuid;
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    type_name text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_object WHERE id = obj_id) THEN
        RAISE EXCEPTION 'py_object_invert: object % does not exist', obj_id;
    END IF;
    SELECT ob_type INTO type_id FROM public.py_object WHERE id = obj_id;
    IF type_id IS NULL THEN
        PERFORM public.py_err_set_type_error('bad operand type for unary ~: ''NoneType''');
        RETURN NULL;
    END IF;
    SELECT tp_as_number INTO num_methods_id FROM public.py_type_object WHERE ob_base = type_id;
    IF num_methods_id IS NULL THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        PERFORM public.py_err_set_type_error('bad operand type for unary ~: ''' || COALESCE(type_name, 'unknown') || '''');
        RETURN NULL;
    END IF;
    SELECT nb_invert INTO nb_inv FROM public.py_number_methods WHERE id = num_methods_id;
    IF nb_inv IS NULL THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        PERFORM public.py_err_set_type_error('bad operand type for unary ~: ''' || COALESCE(type_name, 'unknown') || '''');
        RETURN NULL;
    END IF;
    EXECUTE format('SELECT %I($1)', nb_inv::text) USING obj_id INTO res;
    IF res = id_not_implemented THEN
        SELECT tp_name INTO type_name FROM public.py_type_object WHERE ob_base = type_id;
        PERFORM public.py_err_set_type_error('bad operand type for unary ~: ''' || COALESCE(type_name, 'unknown') || '''');
        RETURN NULL;
    END IF;
    RETURN res;
END;
$$ LANGUAGE plpgsql;

-- Register nb_invert on int
DO $$
DECLARE
    id_int uuid := '00000000-0000-4000-a000-000000000004';
    num_id uuid;
BEGIN
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = id_int;
    IF num_id IS NOT NULL THEN
        UPDATE public.py_number_methods SET nb_invert = 'py_long_nb_invert'::regproc WHERE id = num_id;
    END IF;
END $$;

-- ============================================================================
-- Opcode UNARY_INVERT (15): pop TOS, push ~TOS
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_UNARY_INVERT(frame_id UUID)
RETURNS void AS $$
DECLARE
    tos_id UUID;
    result_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    tos_id := public.py_stack_pop(frame_id);
    result_id := public.py_object_invert(tos_id);
    IF result_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, result_id);
    END IF;
END;
$$ LANGUAGE plpgsql;
