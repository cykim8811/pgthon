-- ============================================================================
-- Migration: Opcode BUILD_SLICE (133) — CPython 3.11
-- 20260114240345
--
-- Stack: oparg 2 → ..., start, stop → ..., slice(start, stop, None).
--        oparg 3 → ..., start, stop, step → ..., slice(start, stop, step).
-- TOS is top of stack (last pushed). Pop in reverse order: stop, start [; step].
-- Depends: ceval_core, py_slice_object, bootstrap slice type and None.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_BUILD_SLICE(frame_id UUID, oparg INTEGER)
RETURNS void AS $$
DECLARE
    start_id UUID;
    stop_id UUID;
    step_id UUID;
    slice_id UUID;
    ID_SLICE_TYPE uuid := '00000000-0000-4000-a000-000000000016';
    ID_NONE_OBJ uuid := '00000000-0000-4000-b000-000000000001';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF oparg = 2 THEN
        stop_id := public.py_stack_pop(frame_id);
        start_id := public.py_stack_pop(frame_id);
        step_id := ID_NONE_OBJ;
    ELSIF oparg = 3 THEN
        step_id := public.py_stack_pop(frame_id);
        stop_id := public.py_stack_pop(frame_id);
        start_id := public.py_stack_pop(frame_id);
    ELSE
        RAISE EXCEPTION 'BUILD_SLICE oparg must be 2 or 3, got %', oparg;
    END IF;
    slice_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (slice_id, ID_SLICE_TYPE);
    INSERT INTO public.py_slice_object (ob_base, ob_start, ob_stop, ob_step)
    VALUES (slice_id, start_id, stop_id, step_id);
    PERFORM public.py_stack_push(frame_id, slice_id);
END;
$$ LANGUAGE plpgsql;
