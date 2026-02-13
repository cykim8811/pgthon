-- ============================================================================
-- Migration: Opcode CALL_FUNCTION_EX (142) — CPython 3.11
--
-- f(*args) / f(*args, **kwargs). Stack: [NULL, callable, args_tuple, (kwargs_dict)?]
-- flags = oparg & 1: if set, TOS is kwargs dict.
-- Pop kwargs (if flags), pop args tuple, pop callable, pop NULL marker.
-- Call py_object_call(callable, args_array, kwargs_dict).
-- Depends: tp_call_slot (py_object_call), py_iterate_to_array, ceval_core.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_CALL_FUNCTION_EX(frame_id UUID, flags INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_NULL_OBJ   UUID := '00000000-0000-4000-b000-000000000030';
    kwargs_id UUID := NULL;
    args_obj_id UUID;
    func_obj_id UUID;
    args UUID[];
    args_type UUID;
    result_id UUID;
    current_stack UUID[];
    stack_len INT;
BEGIN
    -- If flags & 1, pop kwargs dict from TOS
    IF (flags & 1) = 1 THEN
        kwargs_id := public.py_stack_pop(frame_id);
    END IF;

    -- Pop args (tuple or iterable)
    args_obj_id := public.py_stack_pop(frame_id);

    -- Pop callable
    func_obj_id := public.py_stack_pop(frame_id);

    -- Pop NULL marker (same pattern as CALL opcode)
    SELECT f_valuestack INTO current_stack FROM public.py_frame_object WHERE ob_base = frame_id;
    stack_len := COALESCE(array_length(current_stack, 1), 0);
    IF stack_len >= 1 AND current_stack[stack_len] = ID_NULL_OBJ THEN
        UPDATE public.py_frame_object
        SET f_valuestack = current_stack[1:stack_len - 1]
        WHERE ob_base = frame_id;
    END IF;

    -- Convert args to UUID array
    SELECT ob_type INTO args_type FROM public.py_object WHERE id = args_obj_id;
    IF args_type = ID_TUPLE_TYPE THEN
        SELECT ob_item INTO args FROM public.py_tuple_object WHERE ob_base = args_obj_id;
        IF args IS NULL THEN args := ARRAY[]::uuid[]; END IF;
    ELSE
        args := public.py_iterate_to_array(args_obj_id);
        IF args IS NULL THEN
            RETURN; -- error already set
        END IF;
    END IF;

    -- Call the function
    result_id := public.py_object_call(func_obj_id, args, kwargs_id);

    IF result_id IS NULL THEN
        RETURN; -- error already set
    END IF;

    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
