-- ============================================================================
-- Migration: Opcode GET_ITER (68) — CPython 3.11
-- 20260114240350
--
-- GET_ITER: Pop TOS, call tp_iter to get an iterator, push iterator.
-- If TOS already has tp_iternext (is an iterator), return it directly.
-- TypeError if no tp_iter and no tp_iternext.
--
-- CPython: ceval.c TARGET(GET_ITER)
-- Depends: 227100 (tp_iter_slot), 224300 (exception_setters), ceval_core
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_GET_ITER(frame_id UUID)
RETURNS VOID AS $$
DECLARE
    v_obj UUID;
    v_type_id UUID;
    v_tp_iter regproc;
    v_tp_iternext regproc;
    v_iter UUID;
    v_tp_name TEXT;
BEGIN
    -- Pop TOS
    v_obj := public.py_stack_pop(frame_id);

    -- Get the type of the object
    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = v_obj;

    -- Check if object already has tp_iternext (is already an iterator)
    SELECT tp_iternext INTO v_tp_iternext FROM public.py_type_object WHERE ob_base = v_type_id;
    IF v_tp_iternext IS NOT NULL THEN
        -- Already an iterator, push it back (CPython behavior: iter(iterator) returns self)
        PERFORM public.py_stack_push(frame_id, v_obj);
        RETURN;
    END IF;

    -- Get tp_iter from the type
    SELECT tp_iter INTO v_tp_iter FROM public.py_type_object WHERE ob_base = v_type_id;
    IF v_tp_iter IS NULL THEN
        SELECT tp_name INTO v_tp_name FROM public.py_type_object WHERE ob_base = v_type_id;
        PERFORM public.py_err_set_type_error(
            format('''%s'' object is not iterable', COALESCE(v_tp_name, '<unknown>'))
        );
        RETURN;
    END IF;

    -- Call tp_iter(obj) to create an iterator
    EXECUTE format('SELECT public.%I($1)', v_tp_iter::text) INTO v_iter USING v_obj;

    -- Push iterator onto stack
    PERFORM public.py_stack_push(frame_id, v_iter);
END;
$$ LANGUAGE plpgsql;
