-- ============================================================================
-- Migration: Opcode COPY (120) — CPython 3.11
-- 20260114240329
--
-- Copies the value at stack[-depth] to the top of the stack (duplicate at depth).
-- CPython 3.11: COPY(depth) pushes a reference to the value at stack[-depth].
-- depth >= 1; stack must have at least depth elements.
-- Depends: ceval_core (py_stack_push), function_object_schema (frame).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_COPY(frame_id UUID, depth INTEGER)
RETURNS VOID AS $$
DECLARE
    current_stack uuid[];
    stack_top INTEGER;
    val_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'COPY: Frame with id % does not exist', frame_id;
    END IF;
    IF depth IS NULL OR depth < 1 THEN
        RAISE EXCEPTION 'COPY: depth must be >= 1, got %', depth;
    END IF;

    SELECT f_valuestack INTO current_stack
    FROM public.py_frame_object
    WHERE ob_base = frame_id;

    stack_top := coalesce(array_length(current_stack, 1), 0);
    IF stack_top < depth THEN
        RAISE EXCEPTION 'COPY: stack has % items, need at least % (depth)', stack_top, depth;
    END IF;

    val_id := current_stack[stack_top - depth + 1];
    PERFORM public.py_stack_push(frame_id, val_id);
END;
$$ LANGUAGE plpgsql;
