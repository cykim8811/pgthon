-- ============================================================================
-- Migration: Opcode LOAD_CLOSURE (136) — CPython 3.11
-- 20260114240353
--
-- LOAD_CLOSURE(arg): Push the cell object at f_fastlocals[co_nlocals + arg]
-- onto the stack. Used to build the closure tuple before MAKE_FUNCTION.
--
-- CPython 3.11: ceval.c TARGET(LOAD_CLOSURE)
-- In 3.11, LOAD_CLOSURE is an alias for LOAD_FAST at offset co_nlocals+arg.
-- Depends: function_object_schema (py_cell_object), ceval_core
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_CLOSURE(frame_id UUID, arg INTEGER)
RETURNS VOID AS $$
DECLARE
    v_code_id UUID;
    v_co_nlocals INTEGER;
    v_co_varnames UUID;
    v_slot INTEGER;
    v_fastlocals UUID[];
    v_cell_id UUID;
BEGIN
    SELECT f_code INTO v_code_id FROM public.py_frame_object WHERE ob_base = frame_id;

    SELECT co_nlocals, co_varnames INTO v_co_nlocals, v_co_varnames
    FROM public.py_code_object WHERE ob_base = v_code_id;

    IF v_co_nlocals IS NULL THEN
        SELECT COALESCE(array_length(ob_item, 1), 0) INTO v_co_nlocals
        FROM public.py_tuple_object WHERE ob_base = v_co_varnames;
    END IF;

    v_slot := v_co_nlocals + arg + 1; -- 1-based

    SELECT f_fastlocals INTO v_fastlocals FROM public.py_frame_object WHERE ob_base = frame_id;

    IF v_slot > COALESCE(array_length(v_fastlocals, 1), 0) THEN
        RAISE EXCEPTION 'LOAD_CLOSURE: slot % out of range', arg;
    END IF;

    v_cell_id := v_fastlocals[v_slot];
    IF v_cell_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_CLOSURE: cell at slot % is NULL', arg;
    END IF;

    PERFORM public.py_stack_push(frame_id, v_cell_id);
END;
$$ LANGUAGE plpgsql;
