-- ============================================================================
-- Migration: Opcode RESUME (151) — CPython 3.11 function/generator entry
-- 20260114240320
--
-- Design: docs/OPCODE_3_11_ROADMAP.md, docs/EXCEPTION_HANDLING_DESIGN.md
-- RESUME: 3.11 compiler emits at start of frame (and after yield/await).
-- Argument (where): 0=function start, 1=after yield, 2=after yield from, 3=after await.
-- Elytra: no-op; read arg only for bytecode advance.
-- Depends: ceval_core.
-- ============================================================================

-- RESUME (151): CPython 3.11 — frame entry no-op. Elytra: no-op.
CREATE OR REPLACE FUNCTION public.py_opcode_RESUME(frame_id UUID, where_arg INTEGER)
RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    -- No-op (where_arg 0=start, 1=yield, 2=yield from, 3=await; unused in Elytra).
END;
$$ LANGUAGE plpgsql;
