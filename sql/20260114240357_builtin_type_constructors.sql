-- ============================================================================
-- Migration: Builtin Type Constructors (tp_call for int/str/float/bool/list/tuple/dict)
-- 20260114240357
--
-- Registers tp_call on builtin types so int(), str(), float(), bool(),
-- list(), tuple(), dict() work when called as functions.
--
-- Each follows the tp_call convention: (obj_id UUID, args UUID[], kwargs_id UUID) RETURNS UUID
--
-- Depends: 234000 (tp_call_slot), 236000 (builtin_print/py_object_str),
--          240300 (py_object_istrue), 227100 (tp_iter_slot)
-- ============================================================================

-- ============================================================================
-- py_int_tp_call: int() constructor
-- 0-arg → 0, 1-arg int → copy, 1-arg str → parse, 1-arg float → truncate, 1-arg bool → 0/1
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_int_tp_call(
    type_obj UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_INT_TYPE   UUID := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE   UUID := '00000000-0000-4000-a000-000000000003';
    ID_FLOAT_TYPE UUID := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE  UUID := '00000000-0000-4000-a000-000000000013';
    ID_TRUE_OBJ   UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ  UUID := '00000000-0000-4000-b000-000000000011';

    v_nargs INTEGER;
    v_arg UUID;
    v_arg_type UUID;
    v_int_val NUMERIC;
    v_str_val TEXT;
    v_float_val DOUBLE PRECISION;
    v_result_id UUID;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);

    IF v_nargs = 0 THEN
        v_int_val := 0;
    ELSIF v_nargs = 1 THEN
        v_arg := args[1];
        SELECT ob_type INTO v_arg_type FROM public.py_object WHERE id = v_arg;

        IF v_arg_type = ID_BOOL_TYPE THEN
            IF v_arg = ID_TRUE_OBJ THEN v_int_val := 1;
            ELSE v_int_val := 0;
            END IF;
        ELSIF v_arg_type = ID_INT_TYPE THEN
            SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = v_arg;
        ELSIF v_arg_type = ID_FLOAT_TYPE THEN
            SELECT ob_fval INTO v_float_val FROM public.py_float_object WHERE ob_base = v_arg;
            v_int_val := trunc(v_float_val);
        ELSIF v_arg_type = ID_STR_TYPE THEN
            SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_arg;
            BEGIN
                v_int_val := v_str_val::NUMERIC;
            EXCEPTION WHEN OTHERS THEN
                PERFORM public.py_err_set_value_error(
                    format('invalid literal for int() with base 10: ''%s''', v_str_val));
                RETURN NULL;
            END;
        ELSE
            PERFORM public.py_err_set_type_error('int() argument must be a string, a bytes-like object or a real number');
            RETURN NULL;
        END IF;
    ELSE
        PERFORM public.py_err_set_type_error('int() takes at most 1 argument');
        RETURN NULL;
    END IF;

    v_result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_result_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (v_result_id, v_int_val);
    RETURN v_result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_str_tp_call: str() constructor
-- 0-arg → "", 1-arg → py_object_str(arg)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_str_tp_call(
    type_obj UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    v_nargs INTEGER;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);

    IF v_nargs = 0 THEN
        RETURN public.py_str_from_text('');
    ELSIF v_nargs = 1 THEN
        RETURN public.py_object_str(args[1]);
    ELSE
        PERFORM public.py_err_set_type_error('str() takes at most 1 argument');
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_float_tp_call: float() constructor
-- 0-arg → 0.0, 1-arg int → cast, 1-arg str → parse, 1-arg float → copy
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_float_tp_call(
    type_obj UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_INT_TYPE   UUID := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE   UUID := '00000000-0000-4000-a000-000000000003';
    ID_FLOAT_TYPE UUID := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE  UUID := '00000000-0000-4000-a000-000000000013';
    ID_TRUE_OBJ   UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ  UUID := '00000000-0000-4000-b000-000000000011';

    v_nargs INTEGER;
    v_arg UUID;
    v_arg_type UUID;
    v_float_val DOUBLE PRECISION;
    v_str_val TEXT;
    v_result_id UUID;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);

    IF v_nargs = 0 THEN
        v_float_val := 0.0;
    ELSIF v_nargs = 1 THEN
        v_arg := args[1];
        SELECT ob_type INTO v_arg_type FROM public.py_object WHERE id = v_arg;

        IF v_arg_type = ID_BOOL_TYPE THEN
            IF v_arg = ID_TRUE_OBJ THEN v_float_val := 1.0;
            ELSE v_float_val := 0.0;
            END IF;
        ELSIF v_arg_type = ID_INT_TYPE THEN
            SELECT long_value::DOUBLE PRECISION INTO v_float_val FROM public.py_long_object WHERE ob_base = v_arg;
        ELSIF v_arg_type = ID_FLOAT_TYPE THEN
            SELECT ob_fval INTO v_float_val FROM public.py_float_object WHERE ob_base = v_arg;
        ELSIF v_arg_type = ID_STR_TYPE THEN
            SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = v_arg;
            BEGIN
                v_float_val := v_str_val::DOUBLE PRECISION;
            EXCEPTION WHEN OTHERS THEN
                PERFORM public.py_err_set_value_error(
                    format('could not convert string to float: ''%s''', v_str_val));
                RETURN NULL;
            END;
        ELSE
            PERFORM public.py_err_set_type_error('float() argument must be a string or a real number');
            RETURN NULL;
        END IF;
    ELSE
        PERFORM public.py_err_set_type_error('float() takes at most 1 argument');
        RETURN NULL;
    END IF;

    v_result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_result_id, ID_FLOAT_TYPE);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (v_result_id, v_float_val);
    RETURN v_result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_bool_tp_call: bool() constructor
-- 0-arg → False, 1-arg → py_object_istrue(arg) → True/False singleton
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_bool_tp_call(
    type_obj UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_TRUE_OBJ  UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000011';
    v_nargs INTEGER;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);

    IF v_nargs = 0 THEN
        RETURN ID_FALSE_OBJ;
    ELSIF v_nargs = 1 THEN
        IF public.py_object_istrue(args[1]) THEN
            RETURN ID_TRUE_OBJ;
        ELSE
            RETURN ID_FALSE_OBJ;
        END IF;
    ELSE
        PERFORM public.py_err_set_type_error('bool() takes at most 1 argument');
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Helper: iterate an object and collect items into a UUID array
-- Used by list() and tuple() constructors
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_iterate_to_array(iterable_id UUID)
RETURNS UUID[] AS $$
DECLARE
    ID_STOP_ITERATION_TYPE UUID := '00000000-0000-4000-a000-00000000002a';

    v_type_id UUID;
    v_tp_iter regproc;
    v_tp_iternext regproc;
    v_iter_id UUID;
    v_iter_type_id UUID;
    v_item UUID;
    v_items UUID[] := ARRAY[]::uuid[];
    v_tp_name TEXT;
    v_exc_type UUID;
BEGIN
    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = iterable_id;

    -- Check if already an iterator (has tp_iternext)
    SELECT tp_iternext INTO v_tp_iternext FROM public.py_type_object WHERE ob_base = v_type_id;
    IF v_tp_iternext IS NOT NULL THEN
        v_iter_id := iterable_id;
        v_iter_type_id := v_type_id;
    ELSE
        -- Get tp_iter
        SELECT tp_iter INTO v_tp_iter FROM public.py_type_object WHERE ob_base = v_type_id;
        IF v_tp_iter IS NULL THEN
            SELECT tp_name INTO v_tp_name FROM public.py_type_object WHERE ob_base = v_type_id;
            PERFORM public.py_err_set_type_error(
                format('''%s'' object is not iterable', COALESCE(v_tp_name, '<unknown>')));
            RETURN NULL;
        END IF;

        EXECUTE format('SELECT public.%I($1)', v_tp_iter::text) INTO v_iter_id USING iterable_id;

        SELECT ob_type INTO v_iter_type_id FROM public.py_object WHERE id = v_iter_id;
        SELECT tp_iternext INTO v_tp_iternext FROM public.py_type_object WHERE ob_base = v_iter_type_id;
    END IF;

    -- Iterate until StopIteration
    LOOP
        EXECUTE format('SELECT public.%I($1)', v_tp_iternext::text) INTO v_item USING v_iter_id;

        IF v_item IS NOT NULL THEN
            v_items := array_append(v_items, v_item);
        ELSE
            -- Check for StopIteration
            SELECT exc_type_id INTO v_exc_type
            FROM public.py_thread_state
            WHERE id = current_setting('pgthon.thread_state_id')::uuid;

            IF v_exc_type = ID_STOP_ITERATION_TYPE THEN
                PERFORM public.py_err_clear();
                EXIT; -- done iterating
            ELSE
                -- Some other error, propagate
                RETURN NULL;
            END IF;
        END IF;
    END LOOP;

    RETURN v_items;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_list_tp_call: list() constructor
-- 0-arg → [], 1-arg iterable → iterate and collect
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_list_tp_call(
    type_obj UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    v_nargs INTEGER;
    v_items UUID[];
    v_result_id UUID;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);

    IF v_nargs = 0 THEN
        v_items := ARRAY[]::uuid[];
    ELSIF v_nargs = 1 THEN
        v_items := public.py_iterate_to_array(args[1]);
        IF v_items IS NULL AND public.py_err_occurred() THEN
            RETURN NULL;
        END IF;
        IF v_items IS NULL THEN
            v_items := ARRAY[]::uuid[];
        END IF;
    ELSE
        PERFORM public.py_err_set_type_error('list expected at most 1 argument');
        RETURN NULL;
    END IF;

    v_result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_result_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item) VALUES (v_result_id, v_items);
    RETURN v_result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_tuple_tp_call: tuple() constructor
-- 0-arg → (), 1-arg iterable → iterate and collect
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_tuple_tp_call(
    type_obj UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    v_nargs INTEGER;
    v_items UUID[];
    v_result_id UUID;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);

    IF v_nargs = 0 THEN
        v_items := ARRAY[]::uuid[];
    ELSIF v_nargs = 1 THEN
        v_items := public.py_iterate_to_array(args[1]);
        IF v_items IS NULL AND public.py_err_occurred() THEN
            RETURN NULL;
        END IF;
        IF v_items IS NULL THEN
            v_items := ARRAY[]::uuid[];
        END IF;
    ELSE
        PERFORM public.py_err_set_type_error('tuple expected at most 1 argument');
        RETURN NULL;
    END IF;

    v_result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_result_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (v_result_id, v_items);
    RETURN v_result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_dict_tp_call: dict() constructor
-- 0-arg → {}
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_dict_tp_call(
    type_obj UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    v_nargs INTEGER;
    v_result_id UUID;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);

    IF v_nargs > 0 THEN
        PERFORM public.py_err_set_type_error('dict() takes at most 0 positional arguments');
        RETURN NULL;
    END IF;

    v_result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_result_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (v_result_id);
    RETURN v_result_id;
END;
$$ LANGUAGE plpgsql;

-- NOTE: These constructor functions are NOT registered as tp_call on the
-- individual types. Instead, py_type_tp_call (registered on the 'type'
-- metaclass) dispatches to them based on type_obj identity. This is correct
-- because tp_call on a type controls what happens when INSTANCES of that type
-- are called (e.g., int.tp_call=NULL means 42() raises TypeError, which is
-- correct). The type metaclass's tp_call handles constructor dispatch.
