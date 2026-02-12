-- ============================================================================
-- Migration: Opcode LOAD_METHOD (160) — CPython 3.11
-- 20260114240349
--
-- LOAD_METHOD namei: TOS = obj. Pop obj, attr = getattr(obj, co_names[namei]).
-- - If attr is a bound method (py_method_object, im_self IS NOT NULL): push attr (1 value).
--   CALL will later pop args, pop callable (= bound method), call im_func(im_self, *args).
-- - Else (callable or other): push NULL, push attr (2 values). CALL will pop args, pop callable, pop NULL, call callable(args).
-- Design: docs/CALL_PROTOCOL_3_11_DESIGN.md, CPython 3.11 LOAD_METHOD semantics.
-- Depends: 240308 (LOAD_ATTR), 240319 (PUSH_NULL), python_bootstrap (ID_NULL_OBJ), py_method_object.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_METHOD(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    obj_id UUID;
    result_id UUID;
    ID_NULL_OBJ UUID := '00000000-0000-4000-b000-000000000030';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF name_index < 0 THEN
        RAISE EXCEPTION 'LOAD_METHOD: name_index must be non-negative, got %', name_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_METHOD: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_names INTO co_names_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_METHOD: Code object with id % does not have co_names', code_obj_id;
    END IF;
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object WHERE ob_base = co_names_id;
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_METHOD: Index % out of range for co_names tuple', name_index;
    END IF;

    obj_id := public.py_stack_pop(frame_id);
    result_id := public.py_object_getattr(obj_id, name_str_id);
    IF result_id IS NULL AND public.py_err_occurred() THEN
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.py_method_object
        WHERE ob_base = result_id AND im_self IS NOT NULL
    ) THEN
        PERFORM public.py_stack_push(frame_id, result_id);
    ELSE
        PERFORM public.py_stack_push(frame_id, ID_NULL_OBJ);
        PERFORM public.py_stack_push(frame_id, result_id);
    END IF;
END;
$$ LANGUAGE plpgsql;
