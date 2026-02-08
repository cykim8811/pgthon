-- ============================================================================
-- Migration: Opcode STORE_FAST (125) — CPython 3.11
-- 20260114240322_opcode_store_fast.sql
--
-- Pops a value from the stack and stores it in the frame's fast local slot
-- at index var_num (co_varnames index). Extends f_fastlocals with NULL slots
-- if necessary so that slot var_num exists.
-- Depends: ceval_core (py_stack_pop), function_object_schema (frame).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_STORE_FAST(frame_id UUID, var_num INTEGER)
RETURNS VOID AS $$
DECLARE
    value_id UUID;
    fast_arr uuid[];
    cur_len INTEGER;
    need_len INTEGER;
    i INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'STORE_FAST: Frame with id % does not exist', frame_id;
    END IF;
    IF var_num < 0 THEN
        RAISE EXCEPTION 'STORE_FAST: var_num must be non-negative, got %', var_num;
    END IF;

    value_id := public.py_stack_pop(frame_id);

    SELECT f_fastlocals INTO fast_arr FROM public.py_frame_object WHERE ob_base = frame_id;
    cur_len := coalesce(array_length(fast_arr, 1), 0);
    need_len := var_num + 1;

    IF need_len > cur_len THEN
        IF fast_arr IS NULL THEN
            fast_arr := array_fill(NULL::uuid, ARRAY[need_len]);
        ELSE
            FOR i IN (cur_len + 1)..need_len LOOP
                fast_arr := array_append(fast_arr, NULL::uuid);
            END LOOP;
        END IF;
    END IF;

    fast_arr[var_num + 1] := value_id;
    UPDATE public.py_frame_object SET f_fastlocals = fast_arr WHERE ob_base = frame_id;
END;
$$ LANGUAGE plpgsql;
