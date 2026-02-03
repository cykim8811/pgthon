-- ============================================================================
-- Migration: Opcode POP_EXCEPT (89)
-- Created: 2026-01-14 24:10:05
--
-- Purpose: Pop saved state (tuple of 3); restore exception state via py_err_restore.
-- Depends: ceval_exception_dispatch (py_err_restore), ceval_core (stack).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_POP_EXCEPT(p_frame_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  saved_id uuid;
  items uuid[];
BEGIN
  saved_id := public.py_stack_pop(p_frame_id);
  SELECT ob_item INTO items FROM public.py_tuple_object WHERE ob_base = saved_id;
  IF items IS NOT NULL AND array_length(items, 1) >= 3 THEN
    PERFORM public.py_err_restore(items[1], items[2], items[3]);
  END IF;
END;
$$;
