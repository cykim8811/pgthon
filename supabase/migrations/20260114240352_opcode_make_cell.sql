-- ============================================================================
-- Migration: Opcode MAKE_CELL (135) — CPython 3.11
-- 20260114240352
--
-- MAKE_CELL(arg): Creates a cell object and stores it in
-- f_fastlocals[co_nlocals + arg]. This is emitted at function entry for
-- each variable in co_cellvars.
--
-- CPython 3.11: ceval.c TARGET(MAKE_CELL)
-- The cell starts empty (ob_ref = NULL). STORE_DEREF later sets ob_ref.
-- Depends: function_object_schema (py_cell_object), ceval_core
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_MAKE_CELL(frame_id UUID, arg INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    v_code_id UUID;
    v_co_nlocals INTEGER;
    v_co_varnames UUID;
    v_varnames_len INTEGER;
    v_slot INTEGER;
    v_cell_id UUID;
    v_fastlocals UUID[];
    v_current_val UUID;
BEGIN
    -- Get code object and nlocals
    SELECT f_code INTO v_code_id FROM public.py_frame_object WHERE ob_base = frame_id;

    SELECT co_nlocals, co_varnames INTO v_co_nlocals, v_co_varnames
    FROM public.py_code_object WHERE ob_base = v_code_id;

    -- If co_nlocals is NULL, derive from co_varnames length
    IF v_co_nlocals IS NULL THEN
        SELECT COALESCE(array_length(ob_item, 1), 0) INTO v_co_nlocals
        FROM public.py_tuple_object WHERE ob_base = v_co_varnames;
    END IF;

    -- Create new cell object
    v_cell_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_cell_id, ID_OBJECT_TYPE);

    -- Check if the corresponding local variable already has a value
    -- (e.g., a function parameter that's also a cell var)
    v_slot := v_co_nlocals + arg + 1; -- 1-based index
    SELECT f_fastlocals INTO v_fastlocals FROM public.py_frame_object WHERE ob_base = frame_id;

    IF v_slot <= COALESCE(array_length(v_fastlocals, 1), 0) THEN
        v_current_val := v_fastlocals[v_slot];
    ELSE
        v_current_val := NULL;
    END IF;

    -- If there was already a local in the slot (arg was a parameter),
    -- initialize cell with that value. Otherwise cell starts empty.
    INSERT INTO public.py_cell_object (ob_base, ob_ref) VALUES (v_cell_id, v_current_val);

    -- Store cell in f_fastlocals[co_nlocals + arg]
    -- Extend array if needed
    WHILE COALESCE(array_length(v_fastlocals, 1), 0) < v_slot LOOP
        v_fastlocals := array_append(v_fastlocals, NULL::uuid);
    END LOOP;
    v_fastlocals[v_slot] := v_cell_id;

    UPDATE public.py_frame_object SET f_fastlocals = v_fastlocals WHERE ob_base = frame_id;
END;
$$ LANGUAGE plpgsql;
