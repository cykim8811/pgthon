-- ============================================================================
-- Migration: VM Core Infrastructure
-- Created: 2026-01-14 23:00:00
--
-- Purpose:
--   Implements the core infrastructure for the Elytra VM (Virtual Machine).
--   This includes stack operations and opcode utilities that are the foundation
--   for bytecode execution.
--
--   Functions:
--   - py_stack_push: Push a PyObject ID onto the frame's evaluation stack
--   - py_stack_pop: Pop a PyObject ID from the frame's evaluation stack
--   - py_get_opcode_size: Get the size (in bytes) of an instruction for a given opcode
--
--   These operations mirror CPython's stack manipulation and bytecode parsing
--   in PyEval_EvalFrameEx, where values are pushed/popped from the frame's
--   value stack during bytecode execution.
--
-- Design:
--   - Stack is stored as uuid[] array in py_frame_object.f_valuestack
--   - Stack grows from left to right (array_append for push)
--   - Stack underflow raises exception (CPython behavior)
--   - Most opcodes use 2 bytes (opcode 1 byte + operand 1 byte)
--   - Some opcodes have no operand (1 byte total)
--   - Opcodes with EXTENDED_ARG use 4 bytes (handled separately)
--
-- CPython Compatibility:
--   - Python 3.6+: Standardized to 2-byte instructions (opcode + operand)
--   - Python 3.11+: Inline cache entries added, but instruction size unchanged
-- ============================================================================

-- ============================================================================
-- Stack Operations
-- ============================================================================

-- py_stack_push: Push a PyObject ID onto the frame's evaluation stack
-- 
-- Parameters:
--   frame_id: UUID of the frame object
--   obj_id: UUID of the PyObject to push onto the stack
--
-- Behavior:
--   Appends the object ID to the frame's f_valuestack array.
--   This is equivalent to CPython's stack push operation.
--
-- Usage:
--   PERFORM py_stack_push(frame_id, some_object_id);
--
CREATE OR REPLACE FUNCTION public.py_stack_push(frame_id UUID, obj_id UUID)
RETURNS VOID AS $$
BEGIN
    -- Validate frame exists
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    
    -- Validate object exists
    IF NOT EXISTS (SELECT 1 FROM public.py_object WHERE id = obj_id) THEN
        RAISE EXCEPTION 'PyObject with id % does not exist', obj_id;
    END IF;
    
    -- Push object onto stack (append to array)
    UPDATE public.py_frame_object
    SET f_valuestack = array_append(f_valuestack, obj_id)
    WHERE ob_base = frame_id;
END;
$$ LANGUAGE plpgsql;

-- py_stack_pop: Pop a PyObject ID from the frame's evaluation stack
--
-- Parameters:
--   frame_id: UUID of the frame object
--
-- Returns:
--   UUID of the PyObject that was popped from the stack
--
-- Behavior:
--   Removes and returns the topmost (rightmost) element from the stack.
--   Raises exception if stack is empty (stack underflow).
--   This is equivalent to CPython's stack pop operation.
--
-- Usage:
--   obj_id := py_stack_pop(frame_id);
--
CREATE OR REPLACE FUNCTION public.py_stack_pop(frame_id UUID)
RETURNS UUID AS $$
DECLARE
    stack_top INTEGER;
    result_id UUID;
    current_stack uuid[];
BEGIN
    -- Validate frame exists
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    
    -- Get current stack
    SELECT f_valuestack INTO current_stack
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    -- Check stack size
    stack_top := array_length(current_stack, 1);
    
    IF stack_top IS NULL OR stack_top = 0 THEN
        RAISE EXCEPTION 'Stack underflow: cannot pop from empty stack';
    END IF;
    
    -- Get top element (rightmost, last in array)
    result_id := current_stack[stack_top];
    
    -- Remove top element (slice array to exclude last element)
    UPDATE public.py_frame_object
    SET f_valuestack = current_stack[1:stack_top-1]
    WHERE ob_base = frame_id;
    
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Opcode Utilities
-- ============================================================================

-- py_get_opcode_size: Get the size (in bytes) of an instruction for a given opcode
--
-- Parameters:
--   opcode: INTEGER opcode value (0-255)
--
-- Returns:
--   INTEGER: Size of the instruction in bytes. Python 3.6+ uses uniform 2 bytes
--   (opcode 1 byte + argument 1 byte) for every instruction. HAVE_ARGUMENT(90)
--   only indicates whether the argument is semantically used; storage is always 2.
--
-- CPython Reference:
--   Python 3.6+ (hence 3.11): each bytecode instruction uses 2 bytes.
--   Include/opcode.h: HAVE_ARGUMENT 90, HAS_ARG(op) = (op) >= 90
--
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
