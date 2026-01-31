-- ============================================================================
-- Migration: py_get_opcode_size — Python 3.11 고증 (uniform 2-byte instruction)
-- Created: 2026-01-14 24:07:00
--
-- Purpose:
--   Python 3.6+ (hence 3.11) uses a uniform 2-byte instruction format:
--   every instruction is (opcode 1 byte + argument 1 byte). HAVE_ARGUMENT(90)
--   only indicates whether the argument is semantically used; storage is
--   always 2 bytes. So py_get_opcode_size returns 2 for all opcodes.
--
-- Reference:
--   - Python 3.11 dis docs: "each bytecode instruction uses 2 bytes"
--   - Include/opcode.h: HAVE_ARGUMENT 90, HAS_ARG(op) = (op) >= 90
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_get_opcode_size(opcode INTEGER)
RETURNS INTEGER AS $$
BEGIN
    IF opcode < 0 OR opcode > 255 THEN
        RAISE EXCEPTION 'Invalid opcode: % (must be 0-255)', opcode;
    END IF;
    -- Python 3.6+ uniform format: all instructions are 2 bytes (opcode + arg).
    RETURN 2;
END;
$$ LANGUAGE plpgsql;
