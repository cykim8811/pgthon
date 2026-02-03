-- ============================================================================
-- Migration: Opcode RERAISE (119)
-- Created: 2026-01-14 24:10:02
--
-- Purpose: Pop TOS (exception), set as current, then unwinding (traceback_here).
-- Depends: ceval_exception_dispatch (py_traceback_here), exception_setters.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_RERAISE(p_frame_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  exc_id uuid;
  exc_type_id uuid;
  lasti integer;
BEGIN
  exc_id := public.py_stack_pop(p_frame_id);
  SELECT ob_type INTO exc_type_id FROM public.py_object WHERE id = exc_id;
  PERFORM public.py_err_set_object(exc_type_id, exc_id);
  SELECT f_lasti INTO lasti FROM public.py_frame_object WHERE ob_base = p_frame_id;
  IF lasti IS NULL THEN lasti := 0; END IF;
  PERFORM public.py_traceback_here(p_frame_id, lasti);
END;
$$;
