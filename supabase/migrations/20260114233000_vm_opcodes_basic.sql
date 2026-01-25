-- ============================================================================
-- Migration: VM Basic Opcodes
-- Created: 2026-01-14 23:30:00
--
-- Purpose:
--   Implements basic opcode handlers for the Elytra VM. These opcodes are
--   essential for executing simple bytecode sequences.
--
--   Opcodes:
--   - py_opcode_LOAD_CONST: Load a constant from co_consts tuple onto stack
--
-- Design:
--   - Each opcode handler is a separate function
--   - Handlers operate on the frame's evaluation stack
--   - Handlers follow CPython's exact behavior
--
-- CPython Compatibility:
--   - LOAD_CONST: Reads from co_consts[arg] and pushes to stack
--   - Operand (arg) is the index into co_consts tuple
--   - PostgreSQL arrays are 1-based, so arg + 1 is used
--
-- ============================================================================

-- ============================================================================
-- LOAD_CONST Opcode
-- ============================================================================

-- py_opcode_LOAD_CONST: Load a constant from co_consts tuple onto stack
--
-- Parameters:
--   frame_id: UUID of the frame object
--   const_index: INTEGER index into co_consts tuple (0-based, from bytecode operand)
--
-- Behavior:
--   Loads the constant at co_consts[const_index] and pushes it onto the
--   evaluation stack. This is equivalent to CPython's LOAD_CONST opcode.
--
--   In CPython:
--   - LOAD_CONST reads from frame->f_code->co_consts[arg]
--   - The value is pushed onto the evaluation stack
--
-- Usage:
--   PERFORM py_opcode_LOAD_CONST(frame_id, const_index);
--
-- CPython Reference:
--   This opcode is defined in Python/ceval.c and corresponds to opcode 100.
--   It loads constants (literals, names of builtin objects, etc.) onto the stack.
--
CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_CONST(frame_id UUID, const_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_consts_id UUID;
    const_obj_id UUID;
BEGIN
    -- Validate frame exists
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    
    -- Validate const_index is non-negative
    IF const_index < 0 THEN
        RAISE EXCEPTION 'LOAD_CONST: const_index must be non-negative, got %', const_index;
    END IF;
    
    -- 1. Get code object from frame
    SELECT f_code INTO code_obj_id
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_CONST: Frame with id % does not have a code object', frame_id;
    END IF;
    
    -- 2. Get co_consts tuple from code object
    SELECT co_consts INTO co_consts_id
    FROM public.py_code_object
    WHERE ob_base = code_obj_id;
    
    IF co_consts_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_CONST: Code object with id % does not have co_consts', code_obj_id;
    END IF;
    
    -- 3. Get constant object from co_consts tuple
    -- PostgreSQL arrays are 1-based, so const_index + 1
    -- CPython uses 0-based indexing, so const_index from bytecode is 0-based
    SELECT ob_item[const_index + 1] INTO const_obj_id
    FROM public.py_tuple_object
    WHERE ob_base = co_consts_id;
    
    IF const_obj_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_CONST: Index % out of range for co_consts tuple', const_index;
    END IF;
    
    -- 4. Push constant onto evaluation stack
    PERFORM public.py_stack_push(frame_id, const_obj_id);
END;
$$ LANGUAGE plpgsql;
