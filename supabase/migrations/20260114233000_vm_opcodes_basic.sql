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
--   - py_opcode_STORE_NAME: (defined in 235000 tp_hash_slot, hash-based dict)
--   - py_opcode_LOAD_NAME: (defined in 235000 tp_hash_slot, hash-based dict)
--
-- Design:
--   - Each opcode handler is a separate function
--   - Handlers operate on the frame's evaluation stack
--   - Handlers follow CPython's exact behavior
--
-- CPython Compatibility:
--   - LOAD_CONST: Reads from co_consts[arg] and pushes to stack
--   - STORE_NAME: Pops value from stack and stores it in f_locals dict
--   - LOAD_NAME: Looks up name in locals → globals → builtins and pushes to stack
--   - Operand (arg) is the index into co_names/co_consts tuple
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

-- STORE_NAME and LOAD_NAME are defined in 20260114235000_tp_hash_slot.sql
-- (hash-based dict lookup via py_dict_set_item / py_dict_get_item).

-- ============================================================================
-- CALL_FUNCTION Opcode Support Functions
-- ============================================================================

-- py_call_cfunction: Call a C function (builtin function)
--
-- Parameters:
--   func_obj_id: UUID of the PyCFunction object
--   args: Array of argument object IDs (UUID[])
--
-- Returns:
--   UUID: The PyObject ID returned by the function
--
-- Behavior:
--   Calls a builtin C function based on its m_ml_meth and m_ml_flags.
--   Currently supports METH_O (single argument) calling convention.
--   This is equivalent to CPython's PyCFunction_Call().
--
--   In CPython:
--   - PyCFunction_Call checks m_ml_flags to determine calling convention
--   - METH_O (0x0008): Takes exactly one argument (PyObject*)
--   - METH_VARARGS (0x0001): Takes variable arguments (PyObject* args tuple)
--   - METH_NOARGS (0x0004): Takes no arguments
--
-- Usage:
--   result_id := py_call_cfunction(func_obj_id, ARRAY[arg1_id]);
--
-- CPython Reference:
--   This function implements the core logic of PyCFunction_Call in
--   Objects/methodobject.c. It dispatches to the appropriate calling convention
--   based on m_ml_flags.
--
CREATE OR REPLACE FUNCTION public.py_call_cfunction(func_obj_id UUID, args UUID[])
RETURNS UUID AS $$
DECLARE
    ml_meth regproc;
    ml_flags INTEGER;
    result_id UUID;
    arg_count INTEGER;
BEGIN
    -- Validate function object exists
    IF NOT EXISTS (SELECT 1 FROM public.py_cfunction_object WHERE ob_base = func_obj_id) THEN
        RAISE EXCEPTION 'py_call_cfunction: Function object with id % does not exist', func_obj_id;
    END IF;
    
    -- Get function metadata
    SELECT m_ml_meth, m_ml_flags INTO ml_meth, ml_flags
    FROM public.py_cfunction_object
    WHERE ob_base = func_obj_id;
    
    IF ml_meth IS NULL THEN
        RAISE EXCEPTION 'py_call_cfunction: Function implementation (m_ml_meth) not found for function %', func_obj_id;
    END IF;
    
    -- Get argument count (array_length returns NULL for empty arrays, so use COALESCE)
    arg_count := COALESCE(array_length(args, 1), 0);
    
    -- Dispatch based on calling convention (m_ml_flags)
    -- CPython flags: METH_NOARGS=0x0004, METH_O=0x0008, METH_VARARGS=0x0001
    IF (ml_flags & 8) != 0 THEN  -- METH_O: single argument
        IF arg_count != 1 THEN
            RAISE EXCEPTION 'py_call_cfunction: METH_O function expects 1 argument, got %', COALESCE(arg_count, 0);
        END IF;
        
        -- Call function with single argument
        EXECUTE format('SELECT %I($1)', ml_meth::text) USING args[1] INTO result_id;
        
    ELSIF (ml_flags & 4) != 0 THEN  -- METH_NOARGS: no arguments
        IF arg_count != 0 THEN
            RAISE EXCEPTION 'py_call_cfunction: METH_NOARGS function expects 0 arguments, got %', arg_count;
        END IF;
        
        -- Call function with no arguments
        EXECUTE format('SELECT %I()', ml_meth::text) INTO result_id;
        
    ELSIF (ml_flags & 1) != 0 THEN  -- METH_VARARGS: variable arguments (tuple)
        -- METH_VARARGS functions receive a tuple of arguments
        -- For now, we'll support simple cases. Full implementation would require
        -- unpacking the tuple and calling with appropriate number of arguments.
        RAISE EXCEPTION 'py_call_cfunction: METH_VARARGS calling convention not yet implemented';
        
    ELSE
        RAISE EXCEPTION 'py_call_cfunction: Unsupported calling convention (m_ml_flags=%)', ml_flags;
    END IF;
    
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- CALL_FUNCTION Opcode
-- ============================================================================

-- py_opcode_CALL_FUNCTION: Call a function with positional arguments
--
-- Parameters:
--   frame_id: UUID of the frame object
--   arg_count: INTEGER number of positional arguments (from bytecode operand)
--
-- Behavior:
--   Pops arg_count arguments from the stack (in reverse order), then pops the
--   function object, calls it with the arguments, and pushes the result.
--   This is equivalent to CPython's CALL_FUNCTION opcode.
--
--   In CPython:
--   - CALL_FUNCTION pops function and args from stack
--   - Dispatches based on function type (builtin_function_or_method, function, etc.)
--   - Calls the function and pushes result onto stack
--
-- Usage:
--   PERFORM py_opcode_CALL_FUNCTION(frame_id, arg_count);
--
-- CPython Reference:
--   This opcode is defined in Python/ceval.c and corresponds to opcode 141.
--   It implements function calls with positional arguments only.
--
CREATE OR REPLACE FUNCTION public.py_opcode_CALL_FUNCTION(frame_id UUID, arg_count INTEGER)
RETURNS VOID AS $$
DECLARE
    func_obj_id UUID;
    args UUID[];
    i INTEGER;
    result_id UUID;
BEGIN
    -- Validate frame exists
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    
    -- Validate arg_count is non-negative
    IF arg_count < 0 THEN
        RAISE EXCEPTION 'CALL_FUNCTION: arg_count must be non-negative, got %', arg_count;
    END IF;
    
    -- 1. Pop arguments from stack (in reverse order)
    -- CPython: Arguments are pushed left-to-right, so we pop right-to-left
    args := array[]::UUID[];
    FOR i IN 1..arg_count LOOP
        args := array_prepend(public.py_stack_pop(frame_id), args);
    END LOOP;
    
    -- 2. Pop function object from stack
    func_obj_id := public.py_stack_pop(frame_id);
    
    -- 3. Call the object using its tp_call slot
    -- CPython: PyObject_Call() checks Py_TYPE(obj)->tp_call and calls it
    -- This is the CPython-faithful way to check if an object is callable
    -- and invoke it, rather than checking type name strings.
    result_id := public.py_object_call(func_obj_id, args);
    
    -- 4. Push result onto stack
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
