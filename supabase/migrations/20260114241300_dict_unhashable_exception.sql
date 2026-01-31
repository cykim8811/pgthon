-- ============================================================================
-- dict unhashable: Python-level TypeError via py_err_set_type_error (5단계)
-- 20260114241300_dict_unhashable_exception.sql
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md §2.7
-- py_object_hash: unhashable 시 RAISE EXCEPTION 대신 py_err_set_type_error + RETURN NULL.
-- py_dict_get_item / py_dict_set_item: hash 반환 NULL이고 py_err_occurred()면 진행하지 않고 반환.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- py_object_hash: unhashable type → py_err_set_type_error, RETURN NULL
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_object_hash(obj_id UUID)
RETURNS BIGINT AS $$
DECLARE
    obj_type_id UUID;
    hash_func regproc;
    hash_value BIGINT;
    type_name TEXT;
BEGIN
    -- Validate object exists
    IF NOT EXISTS (SELECT 1 FROM public.py_object WHERE id = obj_id) THEN
        RAISE EXCEPTION 'py_object_hash: Object with id % does not exist', obj_id;
    END IF;

    -- Get object type
    SELECT ob_type INTO obj_type_id
    FROM public.py_object
    WHERE id = obj_id;

    IF obj_type_id IS NULL THEN
        RAISE EXCEPTION 'py_object_hash: Object with id % does not have a type', obj_id;
    END IF;

    -- Get tp_hash slot from type object
    SELECT tp_hash INTO hash_func
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;

    -- Unhashable: set Python TypeError and return NULL (CPython 고증)
    IF hash_func IS NULL THEN
        SELECT tp_name INTO type_name
        FROM public.py_type_object
        WHERE ob_base = obj_type_id;
        PERFORM public.py_err_set_type_error('unhashable type: ''' || COALESCE(type_name, 'unknown') || '''');
        RETURN NULL;
    END IF;

    -- Call the tp_hash function
    EXECUTE format('SELECT %I($1)', hash_func::text) USING obj_id INTO hash_value;

    RETURN hash_value;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- py_dict_get_item: hash NULL + py_err_occurred() → RETURN NULL (예외 유지)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_dict_get_item(dict_id UUID, key_id UUID)
RETURNS UUID AS $$
DECLARE
    h BIGINT;
    val_id UUID;
BEGIN
    h := public.py_object_hash(key_id);
    IF h IS NULL AND public.py_err_occurred() THEN
        RETURN NULL;
    END IF;
    SELECT e.me_value INTO val_id
    FROM public.py_dict_entry e
    WHERE e.dict_id = py_dict_get_item.dict_id
      AND e.me_hash = h
      AND public.py_object_richcompare_eq(e.me_key, key_id)
    LIMIT 1;
    RETURN val_id;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- py_dict_set_item: hash NULL + py_err_occurred() → RETURN (예외 유지)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_dict_set_item(dict_id UUID, key_id UUID, value_id UUID)
RETURNS VOID AS $$
DECLARE
    h BIGINT;
    entry_id UUID;
BEGIN
    h := public.py_object_hash(key_id);
    IF h IS NULL AND public.py_err_occurred() THEN
        RETURN;
    END IF;
    SELECT e.id INTO entry_id
    FROM public.py_dict_entry e
    WHERE e.dict_id = py_dict_set_item.dict_id
      AND e.me_hash = h
      AND public.py_object_richcompare_eq(e.me_key, key_id)
    LIMIT 1;

    IF entry_id IS NOT NULL THEN
        UPDATE public.py_dict_entry SET me_value = value_id WHERE id = entry_id;
    ELSE
        INSERT INTO public.py_dict_entry (dict_id, me_key, me_value, me_hash)
        VALUES (py_dict_set_item.dict_id, key_id, value_id, h);
    END IF;
END;
$$ LANGUAGE plpgsql;
