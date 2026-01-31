-- ============================================================================
-- builtin len: Python-level TypeError via py_err_set_type_error (5단계)
-- 20260114241400_builtin_len_exception.sql
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md §2.7
-- - py_object_size: unsupported type 시 RAISE EXCEPTION 대신 py_err_set_type_error + RETURN NULL.
-- - py_builtin_len: py_object_size가 NULL 반환·예외 설정 시 INSERT 하지 않고 RETURN NULL.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- py_object_size: NoneType / no len() → py_err_set_type_error, RETURN NULL
-- sq_length/mp_length 호출 후 NULL + py_err_occurred() → RETURN NULL
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_object_size(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    obj_type_id UUID;
    sequence_methods_id UUID;
    mapping_methods_id UUID;
    sq_length_func regproc;
    mp_length_func regproc;
    length_value NUMERIC;
    type_name TEXT;
BEGIN
    SELECT ob_type INTO obj_type_id
    FROM public.py_object
    WHERE id = obj_id;

    IF obj_type_id IS NULL THEN
        PERFORM public.py_err_set_type_error('object of type ''NoneType'' has no len()');
        RETURN NULL;
    END IF;

    SELECT tp_as_sequence INTO sequence_methods_id
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;

    IF sequence_methods_id IS NOT NULL THEN
        SELECT sq_length INTO sq_length_func
        FROM public.py_sequence_methods
        WHERE id = sequence_methods_id;

        IF sq_length_func IS NOT NULL THEN
            EXECUTE format('SELECT %I($1)', sq_length_func) USING obj_id INTO length_value;
            IF length_value IS NULL AND public.py_err_occurred() THEN RETURN NULL; END IF;
            RETURN length_value;
        END IF;
    END IF;

    SELECT tp_as_mapping INTO mapping_methods_id
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;

    IF mapping_methods_id IS NOT NULL THEN
        SELECT mp_length INTO mp_length_func
        FROM public.py_mapping_methods
        WHERE id = mapping_methods_id;

        IF mp_length_func IS NOT NULL THEN
            EXECUTE format('SELECT %I($1)', mp_length_func) USING obj_id INTO length_value;
            IF length_value IS NULL AND public.py_err_occurred() THEN RETURN NULL; END IF;
            RETURN length_value;
        END IF;
    END IF;

    SELECT tp_name INTO type_name
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;

    IF type_name IS NULL THEN
        type_name := 'unknown';
    END IF;

    PERFORM public.py_err_set_type_error('object of type ''' || type_name || ''' has no len()');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- py_builtin_len: PyObject_Size 실패 시(NULL + py_err_occurred) INSERT 없이 RETURN NULL
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_builtin_len(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    length_value NUMERIC;
    result_id UUID;
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
BEGIN
    length_value := public.py_object_size(obj_id);

    IF length_value IS NULL AND public.py_err_occurred() THEN
        RETURN NULL;
    END IF;

    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type)
    VALUES (result_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value)
    VALUES (result_id, length_value);

    RETURN result_id;
END;
$$ LANGUAGE plpgsql;
