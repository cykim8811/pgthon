-- ============================================================================
-- Migration: Binary Bitwise Ops (and, or, xor, lshift, rshift)
-- 20260114240361_binary_bitwise_ops.sql
--
-- Integer-only operations. Float → TypeError (matching CPython).
-- Same 3-layer pattern: type-specific → dispatch → public API.
-- ============================================================================

-- ============================================================================
-- BITWISE AND (&)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_and(left_id uuid, right_id uuid)
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
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, (lv::bigint & rv::bigint)::numeric);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_and_via_nb(left_id uuid, right_id uuid)
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
    SELECT nb_and INTO slot FROM public.py_number_methods WHERE id = num_id;
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
    SELECT nb_and INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NULL OR call_proname IS NULL THEN RETURN id_not_implemented; END IF;
    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_and(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    left_type_id uuid; right_type_id uuid;
    left_tp_name text; right_tp_name text;
BEGIN
    res := public.py_object_and_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    PERFORM public.py_err_set_type_error('unsupported operand type(s) for &: ''' || COALESCE(left_tp_name, 'None') || ''' and ''' || COALESCE(right_tp_name, 'None') || '''');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- BITWISE OR (|)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_or(left_id uuid, right_id uuid)
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
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, (lv::bigint | rv::bigint)::numeric);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_or_via_nb(left_id uuid, right_id uuid)
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
    SELECT nb_or INTO slot FROM public.py_number_methods WHERE id = num_id;
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
    SELECT nb_or INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NULL OR call_proname IS NULL THEN RETURN id_not_implemented; END IF;
    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_or(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    left_type_id uuid; right_type_id uuid;
    left_tp_name text; right_tp_name text;
BEGIN
    res := public.py_object_or_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    PERFORM public.py_err_set_type_error('unsupported operand type(s) for |: ''' || COALESCE(left_tp_name, 'None') || ''' and ''' || COALESCE(right_tp_name, 'None') || '''');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- BITWISE XOR (^)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_xor(left_id uuid, right_id uuid)
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
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, (lv::bigint # rv::bigint)::numeric);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_xor_via_nb(left_id uuid, right_id uuid)
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
    SELECT nb_xor INTO slot FROM public.py_number_methods WHERE id = num_id;
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
    SELECT nb_xor INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NULL OR call_proname IS NULL THEN RETURN id_not_implemented; END IF;
    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_xor(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    left_type_id uuid; right_type_id uuid;
    left_tp_name text; right_tp_name text;
BEGIN
    res := public.py_object_xor_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    PERFORM public.py_err_set_type_error('unsupported operand type(s) for ^: ''' || COALESCE(left_tp_name, 'None') || ''' and ''' || COALESCE(right_tp_name, 'None') || '''');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- LEFT SHIFT (<<)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_lshift(left_id uuid, right_id uuid)
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
    IF rv < 0 THEN
        PERFORM public.py_err_set_value_error('negative shift count');
        RETURN NULL;
    END IF;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, (lv::bigint << rv::integer)::numeric);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_lshift_via_nb(left_id uuid, right_id uuid)
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
    SELECT nb_lshift INTO slot FROM public.py_number_methods WHERE id = num_id;
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
    SELECT nb_lshift INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NULL OR call_proname IS NULL THEN RETURN id_not_implemented; END IF;
    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_lshift(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    left_type_id uuid; right_type_id uuid;
    left_tp_name text; right_tp_name text;
BEGIN
    res := public.py_object_lshift_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    PERFORM public.py_err_set_type_error('unsupported operand type(s) for <<: ''' || COALESCE(left_tp_name, 'None') || ''' and ''' || COALESCE(right_tp_name, 'None') || '''');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- RIGHT SHIFT (>>)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_long_nb_rshift(left_id uuid, right_id uuid)
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
    IF rv < 0 THEN
        PERFORM public.py_err_set_value_error('negative shift count');
        RETURN NULL;
    END IF;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_int_type);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, (lv::bigint >> rv::integer)::numeric);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_rshift_via_nb(left_id uuid, right_id uuid)
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
    SELECT nb_rshift INTO slot FROM public.py_number_methods WHERE id = num_id;
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
    SELECT nb_rshift INTO slot FROM public.py_number_methods WHERE id = num_id;
    IF slot IS NULL THEN RETURN id_not_implemented; END IF;
    SELECT n.nspname, p.proname INTO call_nspname, call_proname
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = slot::oid;
    IF call_nspname IS NULL OR call_proname IS NULL THEN RETURN id_not_implemented; END IF;
    EXECUTE format('SELECT %I.%I($1, $2)', call_nspname, call_proname) USING right_id, left_id INTO res;
    RETURN COALESCE(res, id_not_implemented);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_object_rshift(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    id_not_implemented uuid := '00000000-0000-4000-b000-000000000012';
    res uuid;
    left_type_id uuid; right_type_id uuid;
    left_tp_name text; right_tp_name text;
BEGIN
    res := public.py_object_rshift_via_nb(left_id, right_id);
    IF res IS NOT NULL AND res <> id_not_implemented THEN RETURN res; END IF;
    IF public.py_err_occurred() THEN RETURN NULL; END IF;
    SELECT ob_type INTO left_type_id  FROM public.py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
    SELECT tp_name INTO left_tp_name  FROM public.py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
    PERFORM public.py_err_set_type_error('unsupported operand type(s) for >>: ''' || COALESCE(left_tp_name, 'None') || ''' and ''' || COALESCE(right_tp_name, 'None') || '''');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Slot Registration: register on int only (no float for bitwise ops)
-- ============================================================================
DO $$
DECLARE
    id_int uuid := '00000000-0000-4000-a000-000000000004';
BEGIN
    UPDATE public.py_number_methods
    SET nb_and = 'py_long_nb_and'::regproc,
        nb_or = 'py_long_nb_or'::regproc,
        nb_xor = 'py_long_nb_xor'::regproc,
        nb_lshift = 'py_long_nb_lshift'::regproc,
        nb_rshift = 'py_long_nb_rshift'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_int);
END $$;
