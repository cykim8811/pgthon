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
--   STORE_NAME/LOAD_NAME의 이름공간 조회·저장 구현은 235000(tp_hash_slot)의
--   hash 기반 dict API(py_dict_get_item, py_dict_set_item)에 의존한다.
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
-- py_call_cfunction: (func_obj_id, args, kwargs_id). METH_O/METH_NOARGS: kwargs_id IS NOT NULL => TypeError.
CREATE OR REPLACE FUNCTION public.py_call_cfunction(
    func_obj_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ml_meth regproc;
    ml_flags INTEGER;
    result_id UUID;
    arg_count INTEGER;
    func_name TEXT;
    ml_name_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_cfunction_object WHERE ob_base = func_obj_id) THEN
        RAISE EXCEPTION 'py_call_cfunction: Function object with id % does not exist', func_obj_id;
    END IF;

    SELECT m_ml_meth, m_ml_flags, m_ml_name INTO ml_meth, ml_flags, ml_name_id
    FROM public.py_cfunction_object
    WHERE ob_base = func_obj_id;

    IF ml_meth IS NULL THEN
        RAISE EXCEPTION 'py_call_cfunction: Function implementation (m_ml_meth) not found for function %', func_obj_id;
    END IF;

    -- Reject kwargs for conventions that do not accept keyword arguments (METH_KEYWORDS = 2 does accept)
    IF kwargs_id IS NOT NULL THEN
        IF (ml_flags & 2) = 0 AND ((ml_flags & 8) != 0 OR (ml_flags & 4) != 0 OR (ml_flags & 1) != 0) THEN
            SELECT str_value INTO func_name
            FROM public.py_unicode_object
            WHERE ob_base = ml_name_id;
            -- CPython: "len() takes no keyword arguments" (name without quotes)
            RAISE EXCEPTION 'TypeError: %() takes no keyword arguments', COALESCE(func_name, 'builtin');
        END IF;
    END IF;

    arg_count := COALESCE(array_length(args, 1), 0);

    IF (ml_flags & 8) != 0 THEN  -- METH_O
        IF arg_count != 1 THEN
            RAISE EXCEPTION 'py_call_cfunction: METH_O function expects 1 argument, got %', COALESCE(arg_count, 0);
        END IF;
        EXECUTE format('SELECT %I($1)', ml_meth::text) USING args[1] INTO result_id;

    ELSIF (ml_flags & 4) != 0 THEN  -- METH_NOARGS
        IF arg_count != 0 THEN
            RAISE EXCEPTION 'py_call_cfunction: METH_NOARGS function expects 0 arguments, got %', arg_count;
        END IF;
        EXECUTE format('SELECT %I()', ml_meth::text) INTO result_id;

    ELSIF (ml_flags & 2) != 0 THEN  -- METH_KEYWORDS: (func_obj_id, args, kwargs_id) RETURNS UUID
        EXECUTE format('SELECT %I($1, $2, $3)', ml_meth::text) USING func_obj_id, args, kwargs_id INTO result_id;

    ELSIF (ml_flags & 1) != 0 THEN  -- METH_VARARGS
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
-- py_opcode_CALL_FUNCTION: pops args and func, calls py_object_call(..., NULL), pushes result.
CREATE OR REPLACE FUNCTION public.py_opcode_CALL_FUNCTION(frame_id UUID, arg_count INTEGER)
RETURNS VOID AS $$
DECLARE
    func_obj_id UUID;
    args UUID[];
    i INTEGER;
    result_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF arg_count < 0 THEN
        RAISE EXCEPTION 'CALL_FUNCTION: arg_count must be non-negative, got %', arg_count;
    END IF;

    args := array[]::UUID[];
    FOR i IN 1..arg_count LOOP
        args := array_prepend(public.py_stack_pop(frame_id), args);
    END LOOP;
    func_obj_id := public.py_stack_pop(frame_id);

    result_id := public.py_object_call(func_obj_id, args, NULL);

    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- CALL_FUNCTION_KW Opcode (positional + keyword arguments)
-- ============================================================================
--
-- Operand: single byte arg = (nk << 4) | na where na = number of positional
-- args (0-15), nk = number of keyword args (0-15). Matches minimal encoding
-- for 2-byte instruction; CPython 3.10 uses opcode 142 with different encoding.
--
-- Stack (top to bottom): [kwval_nk, ..., kwval_1, kwname_nk, ..., kwname_1,
--                        pos_na, ..., pos_1, callable]
-- Pop order: nk keyword values, nk keyword names (must be str), na positional,
-- then callable. Build kwargs dict via py_dict_set_item; call
-- py_object_call(func_id, args, kwargs_id).
--
-- Key names must be strings (ob_type = str type); validated by ob_type only.
--
CREATE OR REPLACE FUNCTION public.py_opcode_CALL_FUNCTION_KW(frame_id UUID, arg INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    na INTEGER;
    nk INTEGER;
    func_obj_id UUID;
    args UUID[];
    kwargs_dict_id UUID;
    kwvals UUID[];
    kwnames UUID[];
    result_id UUID;
    j INTEGER;
    name_ob_type UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF arg < 0 OR arg > 255 THEN
        RAISE EXCEPTION 'CALL_FUNCTION_KW: arg must be 0-255, got %', arg;
    END IF;

    na := arg & 15;
    nk := (arg >> 4) & 15;

    kwvals := array[]::UUID[];
    FOR j IN 1..nk LOOP
        kwvals := array_prepend(public.py_stack_pop(frame_id), kwvals);
    END LOOP;

    kwnames := array[]::UUID[];
    FOR j IN 1..nk LOOP
        kwnames := array_prepend(public.py_stack_pop(frame_id), kwnames);
    END LOOP;

    FOR j IN 1..array_length(kwnames, 1) LOOP
        SELECT ob_type INTO name_ob_type FROM public.py_object WHERE id = kwnames[j];
        IF name_ob_type IS DISTINCT FROM ID_STR_TYPE THEN
            RAISE EXCEPTION 'CALL_FUNCTION_KW: keyword name must be str (ob_type check), got non-str';
        END IF;
    END LOOP;

    args := array[]::UUID[];
    FOR j IN 1..na LOOP
        args := array_prepend(public.py_stack_pop(frame_id), args);
    END LOOP;
    func_obj_id := public.py_stack_pop(frame_id);

    kwargs_dict_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (kwargs_dict_id, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (ob_base) VALUES (kwargs_dict_id);

    FOR j IN 1..nk LOOP
        PERFORM public.py_dict_set_item(kwargs_dict_id, kwnames[j], kwvals[j]);
    END LOOP;

    result_id := public.py_object_call(func_obj_id, args, kwargs_dict_id);
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- BUILD_TUPLE / BUILD_LIST Opcodes (CPython 102, 103)
-- ============================================================================
--
-- BUILD_TUPLE(count): Pop count items from stack; TOS = last element of tuple.
-- BUILD_LIST(count): Same for list. Type IDs from bootstrap (fixed UUID, no tp_name).
--

CREATE OR REPLACE FUNCTION public.py_opcode_BUILD_TUPLE(frame_id UUID, count INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    items UUID[] := '{}';
    new_id UUID;
    i INTEGER;
    elem_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF count < 0 THEN
        RAISE EXCEPTION 'BUILD_TUPLE: count must be non-negative, got %', count;
    END IF;
    FOR i IN 1..count LOOP
        elem_id := public.py_stack_pop(frame_id);
        items := array_prepend(elem_id, items);
    END LOOP;
    new_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (new_id, ID_TUPLE_TYPE);
    INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (new_id, items);
    PERFORM public.py_stack_push(frame_id, new_id);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.py_opcode_BUILD_LIST(frame_id UUID, count INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    items UUID[] := '{}';
    new_id UUID;
    i INTEGER;
    elem_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;
    IF count < 0 THEN
        RAISE EXCEPTION 'BUILD_LIST: count must be non-negative, got %', count;
    END IF;
    FOR i IN 1..count LOOP
        elem_id := public.py_stack_pop(frame_id);
        items := array_prepend(elem_id, items);
    END LOOP;
    new_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (new_id, ID_LIST_TYPE);
    INSERT INTO public.py_list_object (ob_base, ob_item) VALUES (new_id, items);
    PERFORM public.py_stack_push(frame_id, new_id);
END;
$$ LANGUAGE plpgsql;
