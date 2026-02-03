-- ============================================================================
-- Migration: Opcode CALL_FUNCTION (141) — 240302 (opcode block)
-- ============================================================================
-- Pop arg_count args, then func; call py_object_call; push result.
-- Depends: ceval_opcodes_basic (py_call_cfunction via py_object_call), tp_call_slot, ceval_core.

CREATE OR REPLACE FUNCTION public.py_opcode_CALL_FUNCTION(frame_id UUID, arg_count INTEGER)
RETURNS VOID AS $$
DECLARE
    func_obj_id UUID;
    args UUID[];
    i INTEGER;
    result_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF arg_count < 0 THEN
        RAISE EXCEPTION 'CALL_FUNCTION: arg_count must be non-negative, got %', arg_count;
    END IF;

    args := array[]::UUID[];
    FOR i IN 1..arg_count LOOP
        args := array_prepend(public.py_stack_pop(frame_id), args);
    END LOOP;
    func_obj_id := public.py_stack_pop(frame_id);

    result_id := public.py_object_call(func_obj_id, args, NULL);

    IF result_id IS NULL THEN
        RETURN;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
