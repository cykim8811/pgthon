-- ============================================================================
-- Migration: Binary Arithmetic Ops (true_divide, floor_divide, remainder, power)
-- 20260114240360_binary_arithmetic_ops.sql
--
-- Implements /, //, %, ** for int and float types.
-- Follows the same 3-layer pattern as binary_add (238000):
--   1. Type-specific: py_long_nb_X / py_float_nb_X → result or NotImplemented
--   2. Dispatch: py_object_X_via_nb → try left slot, fallback right slot
--   3. Public: py_object_X → dispatch + TypeError on failure
--
-- CPython: PyNumber_TrueDivide, PyNumber_FloorDivide, PyNumber_Remainder, PyNumber_Power
-- ============================================================================

-- ============================================================================
-- TRUE DIVIDE (/)
-- Python semantics: int/int → float, float/float → float
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_true_divide(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv numeric;
    rv numeric;
    id_float_type uuid := '00000000-0000-4000-a000-000000000009';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = left_id) THEN
        RETURN id_not_implemented;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = right_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT long_value INTO lv FROM public.py_long_object WHERE ob_base = left_id;
    SELECT long_value INTO rv FROM public.py_long_object WHERE ob_base = right_id;
    IF rv = 0 THEN
        PERFORM public.py_err_set_zero_division_error('division by zero');
        RETURN NULL;
    END IF;
    -- Python: int / int always returns float
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_float_type);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (result_id, (lv::double precision / rv::double precision));
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_float_nb_true_divide(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv double precision;
    rv double precision;
    rv_long numeric;
    id_float_type uuid := '00000000-0000-4000-a000-000000000009';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = left_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT ob_fval INTO lv FROM public.py_float_object WHERE ob_base = left_id;
    IF EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = right_id) THEN
        SELECT ob_fval INTO rv FROM public.py_float_object WHERE ob_base = right_id;
    ELSIF EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = right_id) THEN
        SELECT long_value INTO rv_long FROM public.py_long_object WHERE ob_base = right_id;
        rv := rv_long::double precision;
    ELSE
        RETURN id_not_implemented;
    END IF;
    IF rv = 0 THEN
        PERFORM public.py_err_set_zero_division_error('float division by zero');
        RETURN NULL;
    END IF;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_float_type);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (result_id, lv / rv);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_true_divide_via_nb(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    left_type_id uuid;
    right_type_id uuid;
    num_id uuid;
    slot regproc;
    res uuid;
    call_nspname text;
    call_proname text;
BEGIN
    SELECT ob_type INTO left_type_id FROM public.py_object WHERE id = left_id;
    IF left_type_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = left_type_id;
    IF num_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT nb_true_divide INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NOT NULL AND call_proname IS NOT NULL THEN
        EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING left_id, right_id INTO res;
        IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    END IF;
    -- If error was set (e.g. ZeroDivisionError), propagate
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    IF right_type_id IS NULL OR right_type_id = left_type_id THEN RETURN id_not_implemented; END IF;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = right_type_id;
    IF num_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT nb_true_divide INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NULL OR call_proname IS NULL THEN RETURN id_not_implemented; END IF;
    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_true_divide(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    left_type_id uuid;
    right_type_id uuid;
    left_tp_name text;
    right_tp_name text;
BEGIN
    res := public.py_object_true_divide_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    PERFORM public.py_err_set_type_error('unsupported operand type(s) for /: ''' || COALESCE(left_tp_name, 'None') || ''' and ''' || COALESCE(right_tp_name, 'None') || '''');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FLOOR DIVIDE (//)
-- Python semantics: int//int → int, float//float → float
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_floor_divide(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv numeric;
    rv numeric;
    id_int_type uuid := '00000000-0000-4000-a000-000000000004';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = left_id) THEN
        RETURN id_not_implemented;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = right_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT long_value INTO lv FROM public.py_long_object WHERE ob_base = left_id;
    SELECT long_value INTO rv FROM public.py_long_object WHERE ob_base = right_id;
    IF rv = 0 THEN
        PERFORM public.py_err_set_zero_division_error('integer division or modulo by zero');
        RETURN NULL;
    END IF;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, floor(lv / rv));
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_float_nb_floor_divide(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv double precision;
    rv double precision;
    rv_long numeric;
    id_float_type uuid := '00000000-0000-4000-a000-000000000009';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = left_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT ob_fval INTO lv FROM public.py_float_object WHERE ob_base = left_id;
    IF EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = right_id) THEN
        SELECT ob_fval INTO rv FROM public.py_float_object WHERE ob_base = right_id;
    ELSIF EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = right_id) THEN
        SELECT long_value INTO rv_long FROM public.py_long_object WHERE ob_base = right_id;
        rv := rv_long::double precision;
    ELSE
        RETURN id_not_implemented;
    END IF;
    IF rv = 0 THEN
        PERFORM public.py_err_set_zero_division_error('float floor division by zero');
        RETURN NULL;
    END IF;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_float_type);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (result_id, floor(lv / rv));
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_floor_divide_via_nb(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    left_type_id uuid;
    right_type_id uuid;
    num_id uuid;
    slot regproc;
    res uuid;
    call_nspname text;
    call_proname text;
BEGIN
    SELECT ob_type INTO left_type_id FROM public.py_object WHERE id = left_id;
    IF left_type_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = left_type_id;
    IF num_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT nb_floor_divide INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NOT NULL AND call_proname IS NOT NULL THEN
        EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING left_id, right_id INTO res;
        IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    IF right_type_id IS NULL OR right_type_id = left_type_id THEN RETURN id_not_implemented; END IF;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = right_type_id;
    IF num_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT nb_floor_divide INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NULL OR call_proname IS NULL THEN RETURN id_not_implemented; END IF;
    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_floor_divide(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    left_type_id uuid;
    right_type_id uuid;
    left_tp_name text;
    right_tp_name text;
BEGIN
    res := public.py_object_floor_divide_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    PERFORM public.py_err_set_type_error('unsupported operand type(s) for //: ''' || COALESCE(left_tp_name, 'None') || ''' and ''' || COALESCE(right_tp_name, 'None') || '''');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- REMAINDER (%)
-- Python semantics: result has sign of divisor (PostgreSQL % matches this for numeric)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_remainder(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv numeric;
    rv numeric;
    result_val numeric;
    id_int_type uuid := '00000000-0000-4000-a000-000000000004';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = left_id) THEN
        RETURN id_not_implemented;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = right_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT long_value INTO lv FROM public.py_long_object WHERE ob_base = left_id;
    SELECT long_value INTO rv FROM public.py_long_object WHERE ob_base = right_id;
    IF rv = 0 THEN
        PERFORM public.py_err_set_zero_division_error('integer division or modulo by zero');
        RETURN NULL;
    END IF;
    -- Python modulo: result = lv - floor(lv/rv)*rv (result has sign of divisor)
    result_val := lv - floor(lv / rv) * rv;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, result_val);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_float_nb_remainder(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv double precision;
    rv double precision;
    rv_long numeric;
    result_val double precision;
    id_float_type uuid := '00000000-0000-4000-a000-000000000009';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = left_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT ob_fval INTO lv FROM public.py_float_object WHERE ob_base = left_id;
    IF EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = right_id) THEN
        SELECT ob_fval INTO rv FROM public.py_float_object WHERE ob_base = right_id;
    ELSIF EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = right_id) THEN
        SELECT long_value INTO rv_long FROM public.py_long_object WHERE ob_base = right_id;
        rv := rv_long::double precision;
    ELSE
        RETURN id_not_implemented;
    END IF;
    IF rv = 0 THEN
        PERFORM public.py_err_set_zero_division_error('float modulo');
        RETURN NULL;
    END IF;
    -- Python modulo: result = lv - floor(lv/rv)*rv
    result_val := lv - floor(lv / rv) * rv;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_float_type);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (result_id, result_val);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_remainder_via_nb(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    left_type_id uuid;
    right_type_id uuid;
    num_id uuid;
    slot regproc;
    res uuid;
    call_nspname text;
    call_proname text;
BEGIN
    SELECT ob_type INTO left_type_id FROM public.py_object WHERE id = left_id;
    IF left_type_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = left_type_id;
    IF num_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT nb_remainder INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NOT NULL AND call_proname IS NOT NULL THEN
        EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING left_id, right_id INTO res;
        IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    IF right_type_id IS NULL OR right_type_id = left_type_id THEN RETURN id_not_implemented; END IF;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = right_type_id;
    IF num_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT nb_remainder INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NULL OR call_proname IS NULL THEN RETURN id_not_implemented; END IF;
    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_remainder(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    left_type_id uuid;
    right_type_id uuid;
    left_tp_name text;
    right_tp_name text;
BEGIN
    res := public.py_object_remainder_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    PERFORM public.py_err_set_type_error('unsupported operand type(s) for %: ''' || COALESCE(left_tp_name, 'None') || ''' and ''' || COALESCE(right_tp_name, 'None') || '''');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- POWER (**)
-- Python semantics: int**int → int (negative exp → float), float**float → float
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_power(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv numeric;
    rv numeric;
    id_int_type uuid := '00000000-0000-4000-a000-000000000004';
    id_float_type uuid := '00000000-0000-4000-a000-000000000009';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = left_id) THEN
        RETURN id_not_implemented;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = right_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT long_value INTO lv FROM public.py_long_object WHERE ob_base = left_id;
    SELECT long_value INTO rv FROM public.py_long_object WHERE ob_base = right_id;
    IF rv < 0 THEN
        -- Negative exponent: int ** negative → float (Python semantics)
        result_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_float_type);
        INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (result_id, power(lv::double precision, rv::double precision));
        RETURN result_id;
    END IF;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, power(lv, rv));
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_float_nb_power(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv double precision;
    rv double precision;
    rv_long numeric;
    id_float_type uuid := '00000000-0000-4000-a000-000000000009';
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = left_id) THEN
        RETURN id_not_implemented;
    END IF;
    SELECT ob_fval INTO lv FROM public.py_float_object WHERE ob_base = left_id;
    IF EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = right_id) THEN
        SELECT ob_fval INTO rv FROM public.py_float_object WHERE ob_base = right_id;
    ELSIF EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = right_id) THEN
        SELECT long_value INTO rv_long FROM public.py_long_object WHERE ob_base = right_id;
        rv := rv_long::double precision;
    ELSE
        RETURN id_not_implemented;
    END IF;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_float_type);
    INSERT INTO public.py_float_object (ob_base, ob_fval) VALUES (result_id, power(lv, rv));
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_power_via_nb(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    left_type_id uuid;
    right_type_id uuid;
    num_id uuid;
    slot regproc;
    res uuid;
    call_nspname text;
    call_proname text;
BEGIN
    SELECT ob_type INTO left_type_id FROM public.py_object WHERE id = left_id;
    IF left_type_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = left_type_id;
    IF num_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT nb_power INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NOT NULL AND call_proname IS NOT NULL THEN
        EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING left_id, right_id INTO res;
        IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    IF right_type_id IS NULL OR right_type_id = left_type_id THEN RETURN id_not_implemented; END IF;
    SELECT tp_as_number INTO num_id FROM public.py_type_object WHERE ob_base = right_type_id;
    IF num_id IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT nb_power INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NULL OR call_proname IS NULL THEN RETURN id_not_implemented; END IF;
    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_power(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    left_type_id uuid;
    right_type_id uuid;
    left_tp_name text;
    right_tp_name text;
BEGIN
    res := public.py_object_power_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    PERFORM public.py_err_set_type_error('unsupported operand type(s) for **: ''' || COALESCE(left_tp_name, 'None') || ''' and ''' || COALESCE(right_tp_name, 'None') || '''');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Slot Registration: register type-specific functions on int and float
-- ============================================================================
DO $$
DECLARE
    id_int uuid := '00000000-0000-4000-a000-000000000004';
    id_float uuid := '00000000-0000-4000-a000-000000000009';
BEGIN
    UPDATE public.py_number_methods
    SET nb_true_divide = 'py_long_nb_true_divide'::regproc,
        nb_floor_divide = 'py_long_nb_floor_divide'::regproc,
        nb_remainder = 'py_long_nb_remainder'::regproc,
        nb_power = 'py_long_nb_power'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_int);

    UPDATE public.py_number_methods
    SET nb_true_divide = 'py_float_nb_true_divide'::regproc,
        nb_floor_divide = 'py_float_nb_floor_divide'::regproc,
        nb_remainder = 'py_float_nb_remainder'::regproc,
        nb_power = 'py_float_nb_power'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_float);
END $$;
