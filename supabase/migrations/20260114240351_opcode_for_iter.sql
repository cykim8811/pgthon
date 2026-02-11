-- ============================================================================
-- Migration: Opcode FOR_ITER (93) — CPython 3.11
-- 20260114240351
--
-- FOR_ITER(delta): Peek TOS (iterator), call tp_iternext.
--   - If value returned: push value, return NULL (continue to next instruction)
--   - If StopIteration: clear exception, pop iterator, return jump target
--   - Other exception: propagate (return NULL, let eval_frame handle it)
--
-- Returns: NULL to continue normally, or INTEGER jump target (byte offset)
--
-- CPython 3.11: delta is in units of instructions (2 bytes each).
-- Jump target = start_i + 2 + delta * 2 (computed by eval_frame, but
-- this function returns the target directly for clarity).
--
-- CPython: ceval.c TARGET(FOR_ITER)
-- Depends: 227100 (tp_iter_slot), 224200 (exception_helpers), ceval_core
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_FOR_ITER(frame_id UUID, start_i INTEGER, arg INTEGER)
RETURNS INTEGER AS $$
DECLARE
    ID_STOP_ITERATION_TYPE UUID := '00000000-0000-4000-a000-00000000002a';
    v_iter UUID;
    v_type_id UUID;
    v_tp_iternext regproc;
    v_value UUID;
    v_exc_type UUID;
    v_stack UUID[];
BEGIN
    -- Peek TOS (iterator) — do not pop yet
    SELECT f_valuestack INTO v_stack FROM public.py_frame_object WHERE ob_base = frame_id;
    v_iter := v_stack[array_length(v_stack, 1)];

    -- Get tp_iternext from iterator's type
    SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = v_iter;
    SELECT tp_iternext INTO v_tp_iternext FROM public.py_type_object WHERE ob_base = v_type_id;

    IF v_tp_iternext IS NULL THEN
        PERFORM public.py_err_set_type_error('FOR_ITER: iterator has no tp_iternext');
        RETURN NULL;
    END IF;

    -- Call tp_iternext(iter)
    EXECUTE format('SELECT public.%I($1)', v_tp_iternext::text) INTO v_value USING v_iter;

    IF v_value IS NOT NULL THEN
        -- Got a value: push it onto stack (iterator stays below)
        PERFORM public.py_stack_push(frame_id, v_value);
        RETURN NULL; -- continue to next instruction
    END IF;

    -- v_value is NULL — check if it's StopIteration
    SELECT exc_type_id INTO v_exc_type
    FROM public.py_thread_state
    WHERE id = current_setting('elytra.thread_state_id')::uuid;

    IF v_exc_type = ID_STOP_ITERATION_TYPE THEN
        -- StopIteration: clear exception, pop iterator, jump past loop
        PERFORM public.py_err_clear();
        PERFORM public.py_stack_pop(frame_id); -- pop the iterator
        RETURN start_i + 2 + arg * 2; -- jump target
    END IF;

    -- Other exception: propagate (leave exception set, return NULL)
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
