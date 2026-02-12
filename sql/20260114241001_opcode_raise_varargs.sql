-- ============================================================================
-- Migration: Opcode RAISE_VARARGS (130)
-- Created: 2026-01-14 24:10:01
--
-- Purpose: argc 0=re-raise, 1=raise TOS, 2=raise TOS1 from TOS.
-- Depends: ceval_exception_dispatch (py_traceback_here), exception_setters (py_err_set_object).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_RAISE_VARARGS(p_frame_id uuid, p_argc integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  tos_id uuid;
  tos2_id uuid;
  exc_type_id uuid;
  exc_value_id uuid;
  obj_type_id uuid;
  runtime_error_type_id uuid := '00000000-0000-4000-a000-000000000026';
  none_id uuid := '00000000-0000-4000-b000-000000000001';
  type_type_id uuid := '00000000-0000-4000-a000-000000000002';
  lasti integer;
BEGIN
  SELECT f_lasti INTO lasti FROM public.py_frame_object WHERE ob_base = p_frame_id;
  IF lasti IS NULL THEN lasti := 0; END IF;

  IF p_argc = 0 THEN
    IF NOT public.py_err_occurred() THEN
      PERFORM public.py_err_set_object(runtime_error_type_id, NULL);
      PERFORM public.py_traceback_here(p_frame_id, lasti);
    END IF;
    RETURN;
  END IF;

  IF p_argc = 1 THEN
    tos_id := public.py_stack_pop(p_frame_id);
    SELECT ob_type INTO obj_type_id FROM public.py_object WHERE id = tos_id;
    IF obj_type_id = type_type_id THEN
      exc_type_id := tos_id;
      exc_value_id := none_id;
    ELSE
      exc_type_id := obj_type_id;
      exc_value_id := tos_id;
    END IF;
    PERFORM public.py_err_set_object(exc_type_id, exc_value_id);
    PERFORM public.py_traceback_here(p_frame_id, lasti);
    RETURN;
  END IF;

  IF p_argc = 2 THEN
    tos_id := public.py_stack_pop(p_frame_id);
    tos2_id := public.py_stack_pop(p_frame_id);
    SELECT ob_type INTO exc_type_id FROM public.py_object WHERE id = tos2_id;
    PERFORM public.py_err_set_object(exc_type_id, tos2_id);
    PERFORM public.py_traceback_here(p_frame_id, lasti);
    RETURN;
  END IF;
END;
$$;
