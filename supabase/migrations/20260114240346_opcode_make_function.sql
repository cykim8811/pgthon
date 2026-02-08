-- ============================================================================
-- Migration: MAKE_FUNCTION Opcode (132) — CPython 3.11
-- Created: 2026-01-14 24:03:46
--
-- Purpose:
--   MAKE_FUNCTION(flags): Creates a new function object from a code object
--   and qualified name on the stack, with optional defaults, kwdefaults,
--   annotations, and closure.
--
-- CPython 3.11 MAKE_FUNCTION stack layout (TOS first):
--   qualname  <-- TOS
--   codeobj
--   [closure tuple]      if flags & 0x08
--   [annotations dict]   if flags & 0x04
--   [kwdefaults dict]    if flags & 0x02
--   [defaults tuple]     if flags & 0x01
--
-- Pop order:
--   1. Pop qualname (TOS) — string, used as func_qualname (not stored)
--   2. Pop codeobj
--   3. If flags & 0x08: pop closure tuple -> func_closure
--   4. If flags & 0x04: pop annotations dict -> discard (not stored)
--   5. If flags & 0x02: pop kwdefaults dict -> func_kwdefaults
--   6. If flags & 0x01: pop defaults tuple -> func_defaults
--
-- Depends: ceval_core (py_stack_push/pop), function_object_schema, bootstrap
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_opcode_MAKE_FUNCTION(frame_id UUID, flags INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_FUNCTION_TYPE UUID := '00000000-0000-4000-a000-000000000017';

    v_qualname UUID;
    v_codeobj UUID;
    v_closure UUID := NULL;
    v_annotations UUID := NULL;
    v_kwdefaults UUID := NULL;
    v_defaults UUID := NULL;

    v_func_globals UUID;
    v_func_id UUID;
BEGIN
    -- Pop qualname (TOS)
    v_qualname := public.py_stack_pop(frame_id);

    -- Pop code object
    v_codeobj := public.py_stack_pop(frame_id);

    -- Pop optional components based on flags (CPython 3.11 order)
    IF (flags & 8) != 0 THEN  -- 0x08: closure
        v_closure := public.py_stack_pop(frame_id);
    END IF;

    IF (flags & 4) != 0 THEN  -- 0x04: annotations
        v_annotations := public.py_stack_pop(frame_id);
        -- annotations not stored in current schema; discard
    END IF;

    IF (flags & 2) != 0 THEN  -- 0x02: kwdefaults
        v_kwdefaults := public.py_stack_pop(frame_id);
    END IF;

    IF (flags & 1) != 0 THEN  -- 0x01: defaults
        v_defaults := public.py_stack_pop(frame_id);
    END IF;

    -- Get globals from current frame
    SELECT f_globals INTO v_func_globals
    FROM public.py_frame_object
    WHERE ob_base = frame_id;

    -- Create new function object
    v_func_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_func_id, ID_FUNCTION_TYPE);
    INSERT INTO public.py_function_object (ob_base, func_code, func_globals, func_defaults, func_kwdefaults, func_closure)
    VALUES (v_func_id, v_codeobj, v_func_globals, v_defaults, v_kwdefaults, v_closure);

    -- Push function object onto stack
    PERFORM public.py_stack_push(frame_id, v_func_id);
END;
$$ LANGUAGE plpgsql;
