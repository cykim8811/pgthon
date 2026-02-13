-- ============================================================================
-- Migration: Opcode LOAD_FAST (124) — CPython 3.11
-- 20260114240321_opcode_load_fast.sql
--
-- Pushes the local variable at index var_num (into co_varnames) from the
-- frame's fast local slots (f_fastlocals). Raises UnboundLocalError (NameError)
-- if the slot does not exist or is NULL (variable referenced before assignment).
-- Depends: ceval_core (py_stack_push), function_object_schema (frame, code, tuple).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_FAST(frame_id UUID, var_num INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_varnames_id UUID;
    fast_arr uuid[];
    arr_len INTEGER;
    val_id UUID;
    name_str_id UUID;
    var_name TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'LOAD_FAST: Frame with id % does not exist', frame_id;
    END IF;
    IF var_num < 0 THEN
        RAISE EXCEPTION 'LOAD_FAST: var_num must be non-negative, got %', var_num;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_FAST: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_varnames INTO co_varnames_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_varnames_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_FAST: Code object with id % does not have co_varnames', code_obj_id;
    END IF;

    SELECT f_fastlocals INTO fast_arr FROM public.py_frame_object WHERE ob_base = frame_id;
    arr_len := coalesce(array_length(fast_arr, 1), 0);
    IF var_num + 1 > arr_len THEN
        SELECT ob_item[var_num + 1] INTO name_str_id
        FROM public.py_tuple_object WHERE ob_base = co_varnames_id;
        SELECT str_value INTO var_name FROM public.py_unicode_object WHERE ob_base = name_str_id;
        PERFORM public.py_err_set_name_error('local variable ''' || COALESCE(var_name, '?') || ''' referenced before assignment');
        RETURN;
    END IF;

    val_id := fast_arr[var_num + 1];
    IF val_id IS NULL THEN
        SELECT ob_item[var_num + 1] INTO name_str_id
        FROM public.py_tuple_object WHERE ob_base = co_varnames_id;
        SELECT str_value INTO var_name FROM public.py_unicode_object WHERE ob_base = name_str_id;
        PERFORM public.py_err_set_name_error('local variable ''' || COALESCE(var_name, '?') || ''' referenced before assignment');
        RETURN;
    END IF;

    PERFORM public.py_stack_push(frame_id, val_id);
END;
$$ LANGUAGE plpgsql;
