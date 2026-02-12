-- ============================================================================
-- PyObject_IsTrue — truth value for JUMP_* opcodes
-- 20260114240300_py_object_istrue.sql
--
-- CPython PyObject_IsTrue: used by POP_JUMP_IF_FALSE/TRUE etc.
-- Dispatches through nb_bool slot, falls back to py_object_size.
--
-- Design: docs/JUMP_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- ============================================================================
-- Type-specific nb_bool handlers
-- Signature: (obj_id UUID) RETURNS boolean
-- ============================================================================

-- int.__bool__: 0 → false
CREATE OR REPLACE FUNCTION public.py_long_nb_bool(obj_id UUID)
RETURNS boolean AS $$
DECLARE
    n NUMERIC;
BEGIN
    SELECT long_value INTO n FROM public.py_long_object WHERE ob_base = obj_id;
    RETURN (n IS NOT NULL AND n <> 0);
END;
$$ LANGUAGE plpgsql;

-- str.__bool__: '' → false
CREATE OR REPLACE FUNCTION public.py_unicode_nb_bool(obj_id UUID)
RETURNS boolean AS $$
DECLARE
    s TEXT;
BEGIN
    SELECT str_value INTO s FROM public.py_unicode_object WHERE ob_base = obj_id;
    RETURN (s IS NOT NULL AND s <> '');
END;
$$ LANGUAGE plpgsql;

-- float.__bool__: 0.0 → false
CREATE OR REPLACE FUNCTION public.py_float_nb_bool(obj_id UUID)
RETURNS boolean AS $$
DECLARE
    fval DOUBLE PRECISION;
BEGIN
    SELECT ob_fval INTO fval FROM public.py_float_object WHERE ob_base = obj_id;
    RETURN (fval IS NOT NULL AND fval <> 0);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- py_object_istrue: Dispatch through nb_bool slot, fallback to py_object_size
-- CPython: PyObject_IsTrue (Objects/object.c)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_object_istrue(obj_id uuid)
RETURNS boolean AS $$
DECLARE
    id_true  uuid := '00000000-0000-4000-b000-000000000010';
    id_false uuid := '00000000-0000-4000-b000-000000000011';
    id_none  uuid := '00000000-0000-4000-b000-000000000001';
    id_ni    uuid := '00000000-0000-4000-b000-000000000012';
    v_type_id uuid;
    v_num_id uuid;
    v_nb_bool regproc;
    v_result boolean;
    v_size NUMERIC;
BEGIN
    IF obj_id IS NULL THEN
        RETURN false;
    END IF;

    -- Singletons (fast path)
    IF obj_id = id_true THEN
        RETURN true;
    END IF;
    IF obj_id IN (id_false, id_none, id_ni) THEN
        RETURN false;
    END IF;

    -- Get object's type
    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = obj_id;

    -- Check nb_bool via tp_as_number → nb_bool
    SELECT tp_as_number INTO v_num_id FROM public.py_type_object WHERE ob_base = v_type_id;
    IF v_num_id IS NOT NULL THEN
        SELECT nb_bool INTO v_nb_bool FROM public.py_number_methods WHERE id = v_num_id;
        IF v_nb_bool IS NOT NULL THEN
            EXECUTE format('SELECT %I($1)', v_nb_bool) USING obj_id INTO v_result;
            RETURN v_result;
        END IF;
    END IF;

    -- Fallback to length slots: CPython checks mp_length BEFORE sq_length
    -- in PyObject_IsTrue (note: PyObject_Size checks the opposite order).
    DECLARE
        v_seq_id uuid;
        v_map_id uuid;
        v_sq_len regproc;
        v_mp_len regproc;
    BEGIN
        SELECT tp_as_sequence, tp_as_mapping INTO v_seq_id, v_map_id
        FROM public.py_type_object WHERE ob_base = v_type_id;

        -- CPython: check mp_length first (PyObject_IsTrue order)
        IF v_map_id IS NOT NULL THEN
            SELECT mp_length INTO v_mp_len FROM public.py_mapping_methods WHERE id = v_map_id;
            IF v_mp_len IS NOT NULL THEN
                EXECUTE format('SELECT %I($1)', v_mp_len) USING obj_id INTO v_size;
                RETURN (v_size IS NOT NULL AND v_size > 0);
            END IF;
        END IF;

        IF v_seq_id IS NOT NULL THEN
            SELECT sq_length INTO v_sq_len FROM public.py_sequence_methods WHERE id = v_seq_id;
            IF v_sq_len IS NOT NULL THEN
                EXECUTE format('SELECT %I($1)', v_sq_len) USING obj_id INTO v_size;
                RETURN (v_size IS NOT NULL AND v_size > 0);
            END IF;
        END IF;
    END;

    -- Default: object exists → true (CPython: no __bool__/__len__ → true)
    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Register nb_bool slots for int, float, str
-- ============================================================================
DO $$
DECLARE
    id_int   uuid := '00000000-0000-4000-a000-000000000004';
    id_float uuid := '00000000-0000-4000-a000-000000000009';
    id_str   uuid := '00000000-0000-4000-a000-000000000003';
BEGIN
    -- int: update existing py_number_methods row
    UPDATE public.py_number_methods
    SET nb_bool = 'py_long_nb_bool'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_int);

    -- float: update existing py_number_methods row
    UPDATE public.py_number_methods
    SET nb_bool = 'py_float_nb_bool'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_float);

    -- str: update existing py_number_methods row (created in binary_add.sql)
    UPDATE public.py_number_methods
    SET nb_bool = 'py_unicode_nb_bool'::regproc
    WHERE id = (SELECT tp_as_number FROM public.py_type_object WHERE ob_base = id_str);
END $$;
