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
--   - py_opcode_STORE_NAME: Store a value from stack into locals dictionary
--   - py_opcode_LOAD_NAME: Load a name from namespace (locals → globals → builtins)
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

-- ============================================================================
-- STORE_NAME Opcode
-- ============================================================================

-- py_opcode_STORE_NAME: Store a value from stack into locals dictionary
--
-- Parameters:
--   frame_id: UUID of the frame object
--   name_index: INTEGER index into co_names tuple (0-based, from bytecode operand)
--
-- Behavior:
--   Pops a value from the evaluation stack and stores it in the frame's
--   f_locals dictionary with the name from co_names[name_index] as the key.
--   This is equivalent to CPython's STORE_NAME opcode.
--
--   In CPython:
--   - STORE_NAME pops a value from the stack
--   - Stores it in frame->f_locals[co_names[arg]]
--   - If the key already exists, the value is updated (dict assignment)
--
-- Usage:
--   PERFORM py_opcode_STORE_NAME(frame_id, name_index);
--
-- CPython Reference:
--   This opcode is defined in Python/ceval.c and corresponds to opcode 90.
--   It stores values into the local namespace (variable assignment).
--
CREATE OR REPLACE FUNCTION public.py_opcode_STORE_NAME(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    f_locals_id UUID;
    value_obj_id UUID;
    existing_entry_id UUID;
BEGIN
    -- Validate frame exists
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    
    -- Validate name_index is non-negative
    IF name_index < 0 THEN
        RAISE EXCEPTION 'STORE_NAME: name_index must be non-negative, got %', name_index;
    END IF;
    
    -- 1. Get code object from frame
    SELECT f_code INTO code_obj_id
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Frame with id % does not have a code object', frame_id;
    END IF;
    
    -- 2. Get co_names tuple from code object
    SELECT co_names INTO co_names_id
    FROM public.py_code_object
    WHERE ob_base = code_obj_id;
    
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Code object with id % does not have co_names', code_obj_id;
    END IF;
    
    -- 3. Get name string object from co_names tuple
    -- PostgreSQL arrays are 1-based, so name_index + 1
    -- CPython uses 0-based indexing, so name_index from bytecode is 0-based
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object
    WHERE ob_base = co_names_id;
    
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Index % out of range for co_names tuple', name_index;
    END IF;
    
    -- 4. Get locals dictionary from frame
    SELECT f_locals INTO f_locals_id
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF f_locals_id IS NULL THEN
        RAISE EXCEPTION 'STORE_NAME: Frame with id % does not have f_locals', frame_id;
    END IF;
    
    -- 5. Pop value from evaluation stack
    value_obj_id := public.py_stack_pop(frame_id);
    
    -- 6. Store value in locals dictionary
    -- CPython behavior: If key exists, update value; if not, create new entry
    -- Check if entry already exists
    SELECT id INTO existing_entry_id
    FROM public.py_dict_entry
    WHERE dict_id = f_locals_id
    AND me_key = name_str_id;
    
    IF existing_entry_id IS NOT NULL THEN
        -- Update existing entry
        UPDATE public.py_dict_entry
        SET me_value = value_obj_id
        WHERE id = existing_entry_id;
    ELSE
        -- Insert new entry
        INSERT INTO public.py_dict_entry (dict_id, me_key, me_value)
        VALUES (f_locals_id, name_str_id, value_obj_id);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- LOAD_NAME Opcode
-- ============================================================================

-- py_opcode_LOAD_NAME: Load a name from namespace onto stack
--
-- Parameters:
--   frame_id: UUID of the frame object
--   name_index: INTEGER index into co_names tuple (0-based, from bytecode operand)
--
-- Behavior:
--   Looks up the name from co_names[name_index] in the namespace hierarchy
--   (locals → globals → builtins) and pushes the found object onto the
--   evaluation stack. This is equivalent to CPython's LOAD_NAME opcode.
--
--   In CPython:
--   - LOAD_NAME looks up frame->f_code->co_names[arg] in:
--     1. frame->f_locals (local namespace)
--     2. frame->f_globals (global namespace)
--     3. frame->f_builtins (builtin namespace)
--   - The first match is pushed onto the stack
--   - If not found in any namespace, raises NameError
--
-- Usage:
--   PERFORM py_opcode_LOAD_NAME(frame_id, name_index);
--
-- CPython Reference:
--   This opcode is defined in Python/ceval.c and corresponds to opcode 101.
--   It implements Python's name resolution rules (LEGB: Local, Enclosing, Global, Builtin).
--   Note: In CPython 3.x, LOAD_NAME is used for module-level code; function-level
--   code uses LOAD_FAST/LOAD_GLOBAL for optimization.
--
CREATE OR REPLACE FUNCTION public.py_opcode_LOAD_NAME(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    name_str TEXT;
    obj_id UUID;
    f_locals_id UUID;
    f_globals_id UUID;
    f_builtins_id UUID;
BEGIN
    -- Validate frame exists
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    
    -- Validate name_index is non-negative
    IF name_index < 0 THEN
        RAISE EXCEPTION 'LOAD_NAME: name_index must be non-negative, got %', name_index;
    END IF;
    
    -- 1. Get code object from frame
    SELECT f_code INTO code_obj_id
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Frame with id % does not have a code object', frame_id;
    END IF;
    
    -- 2. Get co_names tuple from code object
    SELECT co_names INTO co_names_id
    FROM public.py_code_object
    WHERE ob_base = code_obj_id;
    
    IF co_names_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Code object with id % does not have co_names', code_obj_id;
    END IF;
    
    -- 3. Get name string object from co_names tuple
    -- PostgreSQL arrays are 1-based, so name_index + 1
    -- CPython uses 0-based indexing, so name_index from bytecode is 0-based
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM public.py_tuple_object
    WHERE ob_base = co_names_id;
    
    IF name_str_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Index % out of range for co_names tuple', name_index;
    END IF;
    
    -- Get name string value for error message (if lookup fails)
    SELECT str_value INTO name_str
    FROM public.py_unicode_object
    WHERE ob_base = name_str_id;
    
    -- 4. Get namespace dictionaries from frame
    SELECT f_locals, f_globals, f_builtins
    INTO f_locals_id, f_globals_id, f_builtins_id
    FROM public.py_frame_object
    WHERE ob_base = frame_id;
    
    IF f_locals_id IS NULL OR f_globals_id IS NULL OR f_builtins_id IS NULL THEN
        RAISE EXCEPTION 'LOAD_NAME: Frame with id % does not have all required namespaces (locals, globals, builtins)', frame_id;
    END IF;
    
    -- 5. Namespace lookup: locals → globals → builtins
    -- CPython's exact lookup order: frame->f_locals, then frame->f_globals, then frame->f_builtins
    
    -- 5.1. Try locals first
    SELECT me_value INTO obj_id
    FROM public.py_dict_entry
    WHERE dict_id = f_locals_id
    AND me_key = name_str_id;
    
    IF obj_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;
    
    -- 5.2. Try globals second
    SELECT me_value INTO obj_id
    FROM public.py_dict_entry
    WHERE dict_id = f_globals_id
    AND me_key = name_str_id;
    
    IF obj_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;
    
    -- 5.3. Try builtins third
    SELECT me_value INTO obj_id
    FROM public.py_dict_entry
    WHERE dict_id = f_builtins_id
    AND me_key = name_str_id;
    
    IF obj_id IS NOT NULL THEN
        PERFORM public.py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;
    
    -- 6. Name not found in any namespace - raise NameError
    -- CPython raises: NameError: name 'X' is not defined
    RAISE EXCEPTION 'NameError: name ''%'' is not defined', COALESCE(name_str, 'unknown');
END;
$$ LANGUAGE plpgsql;
