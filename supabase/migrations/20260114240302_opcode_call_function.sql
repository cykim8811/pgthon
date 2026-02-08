-- ============================================================================
-- Migration: Opcode PRECALL (166) + CALL (171) — CPython 3.11 call protocol
-- 240302 (opcode block). Replaces former CALL_FUNCTION (141).
--
-- Design: docs/CALL_PROTOCOL_3_11_DESIGN.md
-- PRECALL n: no-op (prepare for CALL with n positional args).
-- CALL n: pop n positional args, pop callable; py_object_call(callable, args, NULL); push result.
-- Depends: ceval_opcodes_basic (py_object_call), tp_call_slot, ceval_core.
-- ============================================================================

-- PRECALL (166): CPython 3.11 — prepare for call. Elytra: no-op.
CREATE OR REPLACE FUNCTION public.py_opcode_PRECALL(frame_id UUID, n INTEGER)
RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF n < 0 THEN
        RAISE EXCEPTION 'PRECALL: n must be non-negative, got %', n;
    END IF;
    -- No-op for Elytra (tracing/debugging could use n here later).
END;
$$ LANGUAGE plpgsql;

-- CALL (171): CPython 3.11. kw_names_const_i: when set (by preceding KW_NAMES 172), co_consts[kw_names_const_i]
-- is the tuple of keyword names; pop that many keyword values, build kwargs, then n positional, callable.
CREATE OR REPLACE FUNCTION public.py_opcode_CALL(
    frame_id UUID, n INTEGER, kw_names_const_i INTEGER DEFAULT NULL)
RETURNS VOID AS $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_NULL_OBJ UUID := '00000000-0000-4000-b000-000000000030';
    func_obj_id UUID;
    args UUID[];
    kwargs_dict_id UUID;
    result_id UUID;
    code_obj_id UUID;
    co_consts_id UUID;
    consts_items uuid[];
    kw_names_tuple_id UUID;
    kw_names_items uuid[];
    k INTEGER;
    i INTEGER;
    j INTEGER;
    name_ob_type UUID;
    current_stack uuid[];
    stack_len INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF n < 0 THEN
        RAISE EXCEPTION 'CALL: n must be non-negative, got %', n;
    END IF;

    kwargs_dict_id := NULL;
    IF kw_names_const_i IS NOT NULL THEN
        SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
        SELECT co_consts INTO co_consts_id FROM public.py_code_object WHERE ob_base = code_obj_id;
        SELECT ob_item INTO consts_items FROM public.py_tuple_object WHERE ob_base = co_consts_id;
        kw_names_tuple_id := consts_items[kw_names_const_i + 1];
        SELECT ob_item INTO kw_names_items FROM public.py_tuple_object WHERE ob_base = kw_names_tuple_id;
        k := array_length(kw_names_items, 1);
        IF k IS NULL THEN
            k := 0;
        END IF;
        FOR j IN 1..k LOOP
            SELECT ob_type INTO name_ob_type FROM public.py_object WHERE id = kw_names_items[j];
            IF name_ob_type IS DISTINCT FROM ID_STR_TYPE THEN
                RAISE EXCEPTION 'CALL: keyword name must be str (co_consts[%] tuple element), got non-str', kw_names_const_i;
            END IF;
        END LOOP;
        kwargs_dict_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (kwargs_dict_id, ID_DICT_TYPE);
        INSERT INTO public.py_dict_object (ob_base) VALUES (kwargs_dict_id);
        FOR j IN 1..k LOOP
            PERFORM public.py_dict_set_item(
                kwargs_dict_id,
                kw_names_items[k - j + 1],
                public.py_stack_pop(frame_id)
            );
        END LOOP;
    END IF;

    args := array[]::UUID[];
    FOR i IN 1..n LOOP
        args := array_prepend(public.py_stack_pop(frame_id), args);
    END LOOP;
    func_obj_id := public.py_stack_pop(frame_id);

    -- CPython 3.11 PUSH_NULL: if TOS is the null placeholder, pop it (bound method call).
    SELECT f_valuestack INTO current_stack FROM public.py_frame_object WHERE ob_base = frame_id;
    stack_len := array_length(current_stack, 1);
    IF stack_len IS NOT NULL AND stack_len >= 1 AND current_stack[stack_len] = ID_NULL_OBJ THEN
        UPDATE public.py_frame_object SET f_valuestack = current_stack[1:stack_len - 1] WHERE ob_base = frame_id;
    END IF;

    result_id := public.py_object_call(func_obj_id, args, kwargs_dict_id);

    IF result_id IS NULL THEN
        RETURN;
    END IF;
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
