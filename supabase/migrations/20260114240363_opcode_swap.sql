-- ============================================================================
-- SWAP(99) Opcode (CPython 3.11)
-- Swaps TOS with the item at position oparg from the top.
-- SWAP(2) swaps TOS and TOS-1, SWAP(3) swaps TOS and TOS-2, etc.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_SWAP(frame_id UUID, oparg INTEGER)
RETURNS VOID AS $$
DECLARE
    stack uuid[];
    len int;
    tmp uuid;
BEGIN
    SELECT f_valuestack INTO stack FROM public.py_frame_object WHERE ob_base = frame_id;
    len := array_length(stack, 1);

    IF len IS NULL OR len < oparg THEN
        RAISE EXCEPTION 'SWAP: stack too shallow (size=%, oparg=%)', COALESCE(len, 0), oparg;
    END IF;

    -- Swap stack[len] (TOS) with stack[len - oparg + 1]
    tmp := stack[len];
    stack[len] := stack[len - oparg + 1];
    stack[len - oparg + 1] := tmp;

    UPDATE public.py_frame_object SET f_valuestack = stack WHERE ob_base = frame_id;
END;
$$ LANGUAGE plpgsql;
