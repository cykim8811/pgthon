-- ============================================================================
-- Migration: Opcode CHECK_EXC_MATCH (36)
-- Created: 2026-01-14 24:10:04
--
-- Purpose: TOS = type, TOS1 = exc; pop type, push isinstance(exc, type) as True/False.
-- Depends: ceval_exception_dispatch (py_stack_peek, py_type_issubclass), ceval_core (stack).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_CHECK_EXC_MATCH(p_frame_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  match_type_id uuid;
  exc_id uuid;
  exc_type_id uuid;
  result_id uuid;
  type_type_id uuid := '00000000-0000-4000-a000-000000000002';
  true_id uuid := '00000000-0000-4000-b000-000000000010';
  false_id uuid := '00000000-0000-4000-b000-000000000011';
BEGIN
  match_type_id := public.py_stack_pop(p_frame_id);
  exc_id := public.py_stack_peek(p_frame_id);
  IF exc_id IS NULL THEN
    PERFORM public.py_stack_push(p_frame_id, false_id);
    RETURN;
  END IF;
  SELECT ob_type INTO exc_type_id FROM public.py_object WHERE id = exc_id;
  IF public.py_type_issubclass(exc_type_id, match_type_id) THEN
    result_id := true_id;
  ELSE
    result_id := false_id;
  END IF;
  PERFORM public.py_stack_push(p_frame_id, result_id);
END;
$$;
