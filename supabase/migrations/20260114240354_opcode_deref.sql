-- ============================================================================
-- Migration: LOAD_DEREF(137), STORE_DEREF(138), DELETE_DEREF(139),
--            COPY_FREE_VARS(149) — CPython 3.11
-- 20260114240354
--
-- LOAD_DEREF(arg): cell = f_fastlocals[co_nlocals + arg]; push cell.ob_ref
-- STORE_DEREF(arg): cell = f_fastlocals[co_nlocals + arg]; cell.ob_ref = pop TOS
-- DELETE_DEREF(arg): cell = f_fastlocals[co_nlocals + arg]; cell.ob_ref = NULL
-- COPY_FREE_VARS(count): copy func_closure cells into f_fastlocals at offset
--   co_nlocals + len(co_cellvars)
--
-- CPython 3.11: ceval.c TARGET(LOAD_DEREF), TARGET(STORE_DEREF), etc.
-- Depends: function_object_schema, ceval_core, exception_setters
-- ============================================================================

-- ============================================================================
-- LOAD_DEREF (137)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_DEREF(frame_id UUID, arg INTEGER)
RETURNS VOID AS $$
DECLARE
    v_code_id UUID;
    v_co_nlocals INTEGER;
    v_co_varnames UUID;
    v_co_cellvars UUID;
    v_co_freevars UUID;
    v_slot INTEGER;
    v_fastlocals UUID[];
    v_cell_id UUID;
    v_value UUID;
    v_var_name TEXT;
    v_cellvars_items UUID[];
    v_freevars_items UUID[];
    v_cellvars_len INTEGER;
BEGIN
    SELECT f_code INTO v_code_id FROM public.py_frame_object WHERE ob_base = frame_id;

    SELECT co_nlocals, co_varnames, co_cellvars, co_freevars
    INTO v_co_nlocals, v_co_varnames, v_co_cellvars, v_co_freevars
    FROM public.py_code_object WHERE ob_base = v_code_id;

    IF v_co_nlocals IS NULL THEN
        SELECT COALESCE(array_length(ob_item, 1), 0) INTO v_co_nlocals
        FROM public.py_tuple_object WHERE ob_base = v_co_varnames;
    END IF;

    v_slot := v_co_nlocals + arg + 1; -- 1-based

    SELECT f_fastlocals INTO v_fastlocals FROM public.py_frame_object WHERE ob_base = frame_id;

    IF v_slot > COALESCE(array_length(v_fastlocals, 1), 0) THEN
        RAISE EXCEPTION 'LOAD_DEREF: slot % out of range (fastlocals len = %)', arg, COALESCE(array_length(v_fastlocals, 1), 0);
    END IF;

    v_cell_id := v_fastlocals[v_slot];
    IF v_cell_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_DEREF: no cell at slot %', arg;
    END IF;

    SELECT ob_ref INTO v_value FROM public.py_cell_object WHERE ob_base = v_cell_id;

    IF v_value IS NULL THEN
        -- Get variable name for error message
        SELECT ob_item INTO v_cellvars_items FROM public.py_tuple_object WHERE ob_base = v_co_cellvars;
        v_cellvars_len := COALESCE(array_length(v_cellvars_items, 1), 0);

        IF arg < v_cellvars_len THEN
            SELECT str_value INTO v_var_name FROM public.py_unicode_object WHERE ob_base = v_cellvars_items[arg + 1];
        ELSE
            SELECT ob_item INTO v_freevars_items FROM public.py_tuple_object WHERE ob_base = v_co_freevars;
            IF v_freevars_items IS NOT NULL AND (arg - v_cellvars_len + 1) <= array_length(v_freevars_items, 1) THEN
                SELECT str_value INTO v_var_name FROM public.py_unicode_object WHERE ob_base = v_freevars_items[arg - v_cellvars_len + 1];
            END IF;
        END IF;

        PERFORM public.py_err_set_name_error(
            format('free variable ''%s'' referenced before assignment in enclosing scope', COALESCE(v_var_name, '?'))
        );
        RETURN;
    END IF;

    PERFORM public.py_stack_push(frame_id, v_value);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- STORE_DEREF (138)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_STORE_DEREF(frame_id UUID, arg INTEGER)
RETURNS VOID AS $$
DECLARE
    v_code_id UUID;
    v_co_nlocals INTEGER;
    v_co_varnames UUID;
    v_slot INTEGER;
    v_fastlocals UUID[];
    v_cell_id UUID;
    v_value UUID;
BEGIN
    SELECT f_code INTO v_code_id FROM public.py_frame_object WHERE ob_base = frame_id;

    SELECT co_nlocals, co_varnames INTO v_co_nlocals, v_co_varnames
    FROM public.py_code_object WHERE ob_base = v_code_id;

    IF v_co_nlocals IS NULL THEN
        SELECT COALESCE(array_length(ob_item, 1), 0) INTO v_co_nlocals
        FROM public.py_tuple_object WHERE ob_base = v_co_varnames;
    END IF;

    v_slot := v_co_nlocals + arg + 1;

    -- Pop value from stack
    v_value := public.py_stack_pop(frame_id);

    SELECT f_fastlocals INTO v_fastlocals FROM public.py_frame_object WHERE ob_base = frame_id;

    IF v_slot > COALESCE(array_length(v_fastlocals, 1), 0) THEN
        RAISE EXCEPTION 'STORE_DEREF: slot % out of range', arg;
    END IF;

    v_cell_id := v_fastlocals[v_slot];
    IF v_cell_id IS NULL THEN
        RAISE EXCEPTION 'STORE_DEREF: no cell at slot %', arg;
    END IF;

    -- Set cell contents
    UPDATE public.py_cell_object SET ob_ref = v_value WHERE ob_base = v_cell_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- DELETE_DEREF (139)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_DELETE_DEREF(frame_id UUID, arg INTEGER)
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

    v_slot := v_co_nlocals + arg + 1;

    SELECT f_fastlocals INTO v_fastlocals FROM public.py_frame_object WHERE ob_base = frame_id;

    IF v_slot > COALESCE(array_length(v_fastlocals, 1), 0) THEN
        RAISE EXCEPTION 'DELETE_DEREF: slot % out of range', arg;
    END IF;

    v_cell_id := v_fastlocals[v_slot];
    IF v_cell_id IS NULL THEN
        RAISE EXCEPTION 'DELETE_DEREF: no cell at slot %', arg;
    END IF;

    UPDATE public.py_cell_object SET ob_ref = NULL WHERE ob_base = v_cell_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- COPY_FREE_VARS (149)
-- ============================================================================
-- Copies cells from the calling function's closure (func_closure tuple) into
-- this frame's f_fastlocals at offset co_nlocals + len(co_cellvars).
-- This is emitted at the start of functions that have free variables.
CREATE OR REPLACE FUNCTION public.py_opcode_COPY_FREE_VARS(frame_id UUID, count INTEGER)
RETURNS VOID AS $$
DECLARE
    v_code_id UUID;
    v_co_nlocals INTEGER;
    v_co_varnames UUID;
    v_co_cellvars UUID;
    v_cellvars_len INTEGER;
    v_fastlocals UUID[];
    v_closure_tuple UUID;
    v_closure_items UUID[];
    v_slot INTEGER;
    v_func_id UUID;
    i INTEGER;
BEGIN
    SELECT f_code INTO v_code_id FROM public.py_frame_object WHERE ob_base = frame_id;

    SELECT co_nlocals, co_varnames, co_cellvars
    INTO v_co_nlocals, v_co_varnames, v_co_cellvars
    FROM public.py_code_object WHERE ob_base = v_code_id;

    IF v_co_nlocals IS NULL THEN
        SELECT COALESCE(array_length(ob_item, 1), 0) INTO v_co_nlocals
        FROM public.py_tuple_object WHERE ob_base = v_co_varnames;
    END IF;

    SELECT COALESCE(array_length(ob_item, 1), 0) INTO v_cellvars_len
    FROM public.py_tuple_object WHERE ob_base = v_co_cellvars;

    -- Find the function object that created this frame.
    -- The closure is stored in func_closure on the py_function_object.
    -- We need to find which function has this code object and was used to create this frame.
    -- In CPython, the function object is available via the calling frame.
    -- For Elytra, we look up the function by its func_code matching this frame's f_code.
    -- A better approach: the caller should have stored the func_id somewhere.
    -- For now, we look up the most recently created function with this code object.
    -- Actually, in CPython 3.11, COPY_FREE_VARS reads from the function object
    -- associated with the frame. We need to store a reference.
    --
    -- WORKAROUND: Store func_closure cells by finding the function object for this code.
    -- The py_call_function handler should pass the closure into the frame.
    -- Let's look for func_closure from a function with matching func_code.
    SELECT func_closure INTO v_closure_tuple
    FROM public.py_function_object
    WHERE func_code = v_code_id
    LIMIT 1;

    IF v_closure_tuple IS NULL THEN
        -- No closure to copy (this shouldn't happen if COPY_FREE_VARS is emitted)
        RETURN;
    END IF;

    SELECT ob_item INTO v_closure_items
    FROM public.py_tuple_object WHERE ob_base = v_closure_tuple;

    IF v_closure_items IS NULL OR array_length(v_closure_items, 1) < count THEN
        RAISE EXCEPTION 'COPY_FREE_VARS: closure has fewer than % cells', count;
    END IF;

    SELECT f_fastlocals INTO v_fastlocals FROM public.py_frame_object WHERE ob_base = frame_id;

    -- Copy cells into f_fastlocals at offset co_nlocals + cellvars_len
    FOR i IN 0..(count - 1) LOOP
        v_slot := v_co_nlocals + v_cellvars_len + i + 1; -- 1-based
        WHILE COALESCE(array_length(v_fastlocals, 1), 0) < v_slot LOOP
            v_fastlocals := array_append(v_fastlocals, NULL::uuid);
        END LOOP;
        v_fastlocals[v_slot] := v_closure_items[i + 1];
    END LOOP;

    UPDATE public.py_frame_object SET f_fastlocals = v_fastlocals WHERE ob_base = frame_id;
END;
$$ LANGUAGE plpgsql;
