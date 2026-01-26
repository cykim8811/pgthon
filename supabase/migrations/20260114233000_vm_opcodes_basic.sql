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
    
    arg_count := array_length(args, 1);
    
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
