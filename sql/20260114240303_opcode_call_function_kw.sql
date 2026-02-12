-- ============================================================================
-- Migration: Opcode CALL_FUNCTION_KW (142) — 240303 (opcode block)
-- ============================================================================
-- Operand (nk<<4)|na. Pop nk kwvals, nk kwnames, na pos, callable; build kwargs dict; py_object_call; push result.
-- Depends: ceval_opcodes_basic (py_object_call), tp_hash_slot (py_dict_set_item), ceval_core.

CREATE OR REPLACE FUNCTION public.py_opcode_CALL_FUNCTION_KW(frame_id UUID, arg INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    na INTEGER;
    nk INTEGER;
    func_obj_id UUID;
    args UUID[];
    kwargs_dict_id UUID;
    kwvals UUID[];
    kwnames UUID[];
    result_id UUID;
    j INTEGER;
    name_ob_type UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF arg < 0 OR arg > 255 THEN
        RAISE EXCEPTION 'CALL_FUNCTION_KW: arg must be 0-255, got %', arg;
    END IF;

    na := arg & 15;
    nk := (arg >> 4) & 15;

    kwvals := array[]::UUID[];
    FOR j IN 1..nk LOOP
        kwvals := array_prepend(public.py_stack_pop(frame_id), kwvals);
    END LOOP;
    kwnames := array[]::UUID[];
    FOR j IN 1..nk LOOP
        kwnames := array_prepend(public.py_stack_pop(frame_id), kwnames);
    END LOOP;

    FOR j IN 1..array_length(kwnames, 1) LOOP
        SELECT ob_type INTO name_ob_type FROM public.py_object WHERE id = kwnames[j];
        IF name_ob_type IS DISTINCT FROM ID_STR_TYPE THEN
            RAISE EXCEPTION 'CALL_FUNCTION_KW: keyword name must be str (ob_type check), got non-str';
        END IF;
    END LOOP;

    args := array[]::UUID[];
    FOR j IN 1..na LOOP
        args := array_prepend(public.py_stack_pop(frame_id), args);
    END LOOP;
    func_obj_id := public.py_stack_pop(frame_id);

    kwargs_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (kwargs_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (kwargs_dict_id);
    FOR j IN 1..nk LOOP
        PERFORM public.py_dict_set_item(kwargs_dict_id, kwnames[j], kwvals[j]);
    END LOOP;

    result_id := public.py_object_call(func_obj_id, args, kwargs_dict_id);
    IF result_id IS NULL THEN
        RETURN;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
