-- ============================================================================
-- Migration: Opcode PUSH_NULL (2) — CPython 3.11 call protocol
-- 20260114240319
--
-- Design: docs/CALL_PROTOCOL_3_11_DESIGN.md Phase 3
-- PUSH_NULL: push the stack-placeholder NULL singleton (for bound method calls).
-- Depends: python_bootstrap (ID_NULL_OBJ), ceval_core (py_stack_push).
-- ============================================================================

-- PUSH_NULL (2): CPython 3.11 — push call placeholder. Elytra: push null singleton.
-- Fixed UUID for null singleton must match python_bootstrap.sql (ID_NULL_OBJ).
CREATE OR REPLACE FUNCTION public.py_opcode_PUSH_NULL(frame_id UUID)
RETURNS VOID AS $$
DECLARE
    ID_NULL_OBJ UUID := '00000000-0000-4000-b000-000000000030';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    PERFORM public.py_stack_push(frame_id, ID_NULL_OBJ);
END;
$$ LANGUAGE plpgsql;
