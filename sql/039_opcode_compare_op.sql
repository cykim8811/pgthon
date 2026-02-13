-- ============================================================================
-- Migration: Opcode COMPARE_OP (107) — 240313 (opcode block)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_opcode_COMPARE_OP(frame_id uuid, compare_op integer)
RETURNS void AS $$
DECLARE
    right_id uuid;
    left_id  uuid;
    res_id   uuid;
    not_impl uuid := '00000000-0000-4000-b000-000000000012';
    left_tp_name text;
    right_tp_name text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    right_id := public.py_stack_pop(frame_id);
    left_id  := public.py_stack_pop(frame_id);
    res_id   := public.py_object_richcompare(left_id, right_id, compare_op);
    IF res_id = not_impl THEN
        SELECT tp_name INTO left_tp_name FROM public.py_type_object t JOIN public.py_object o ON o.ob_type = t.ob_base WHERE o.id = left_id;
        SELECT tp_name INTO right_tp_name FROM public.py_type_object t JOIN public.py_object o ON o.ob_type = t.ob_base WHERE o.id = right_id;
        PERFORM public.py_err_set_type_error(compare_op::text || ' not supported between instances of ''' || COALESCE(left_tp_name, 'None') || ''' and ''' || COALESCE(right_tp_name, 'None') || '''');
        RETURN;
    END IF;
    PERFORM public.py_stack_push(frame_id, res_id);
END;
$$ LANGUAGE plpgsql;
