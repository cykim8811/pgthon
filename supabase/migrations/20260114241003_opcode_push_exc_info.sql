-- ============================================================================
-- Migration: Opcode PUSH_EXC_INFO (35)
-- Created: 2026-01-14 24:10:03
--
-- Purpose: Pop v; push current exception (as tuple of 3); push v.
-- Depends: ceval_exception_dispatch (py_tuple_from_3, py_err_get_raised), ceval_core (stack).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_PUSH_EXC_INFO(p_frame_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
  exc_type_id uuid;
  exc_value_id uuid;
  exc_tb_id uuid;
  saved_id uuid;
BEGIN
  v_id := public.py_stack_pop(p_frame_id);
  SELECT e.exc_type_id, e.exc_value_id, e.exc_traceback_id
  INTO exc_type_id, exc_value_id, exc_tb_id
  FROM public.py_err_get_raised() e;
  IF exc_type_id IS NULL THEN
    PERFORM public.py_stack_push(p_frame_id, v_id);
    RETURN;
  END IF;
  saved_id := public.py_tuple_from_3(exc_type_id, exc_value_id, exc_tb_id);
  PERFORM public.py_stack_push(p_frame_id, saved_id);
  PERFORM public.py_stack_push(p_frame_id, v_id);
END;
$$;
