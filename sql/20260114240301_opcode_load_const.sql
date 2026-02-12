-- ============================================================================
-- Migration: Opcode LOAD_CONST (100) — 240301 (opcode block)
-- ============================================================================
-- VM opcode 100. Load constant from co_consts[arg] onto stack.
-- Depends: ceval_core (py_stack_push), function_object_schema (frame, code, tuple).

CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_CONST(frame_id UUID, const_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_consts_id UUID;
    const_obj_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF const_index < 0 THEN
        RAISE EXCEPTION 'LOAD_CONST: const_index must be non-negative, got %', const_index;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_CONST: Frame with id % does not have a code object', frame_id;
    END IF;
    SELECT co_consts INTO co_consts_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_consts_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_CONST: Code object with id % does not have co_consts', code_obj_id;
    END IF;
    SELECT ob_item[const_index + 1] INTO const_obj_id
    FROM public.py_tuple_object WHERE ob_base = co_consts_id;
    IF const_obj_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_CONST: Index % out of range for co_consts tuple', const_index;
    END IF;

    PERFORM public.py_stack_push(frame_id, const_obj_id);
END;
$$ LANGUAGE plpgsql;
