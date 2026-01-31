-- ============================================================================
-- Python-level exception setters (CPython 고증)
-- 20260114241100_python_exception_setters.sql
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md §2.7
-- VM/opcode 쪽에서는 PL/pgSQL RAISE EXCEPTION 대신
-- 예외 인스턴스 생성 + py_err_set_object 로 설정.
-- ============================================================================

-- Fixed: str type 00000000-0000-4000-a000-000000000003
-- TypeError 00000000-0000-4000-a000-000000000022
-- ValueError 00000000-0000-4000-a000-000000000023
-- NameError 00000000-0000-4000-a000-000000000024

-- ----------------------------------------------------------------------------
-- py_str_from_text: create str object from text (for exception messages)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_str_from_text(p_text text)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  str_type_id uuid := '00000000-0000-4000-a000-000000000003';
  new_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.py_object (id, ob_type) VALUES (new_id, str_type_id);
  INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (new_id, COALESCE(p_text, ''));
  RETURN new_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- py_tuple_from_1: create tuple (elem) for exception args
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_tuple_from_1(p_elem uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  tuple_type_id uuid;
  new_id uuid := gen_random_uuid();
BEGIN
  SELECT ob_base INTO tuple_type_id FROM public.py_type_object WHERE tp_name = 'tuple' LIMIT 1;
  IF tuple_type_id IS NULL THEN
    RAISE EXCEPTION 'tuple type not found';
  END IF;
  INSERT INTO public.py_object (id, ob_type) VALUES (new_id, tuple_type_id);
  INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (new_id, ARRAY[p_elem]);
  RETURN new_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- py_err_set_type_error: set TypeError(message) as current exception
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_set_type_error(p_message text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  type_error_type_id uuid := '00000000-0000-4000-a000-000000000022';
  msg_id uuid;
  args_id uuid;
  inst_id uuid := gen_random_uuid();
BEGIN
  msg_id := public.py_str_from_text(p_message);
  args_id := public.py_tuple_from_1(msg_id);
  INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, type_error_type_id);
  INSERT INTO public.py_base_exception_object (ob_base, ob_args) VALUES (inst_id, args_id);
  PERFORM public.py_err_set_object(type_error_type_id, inst_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- py_err_set_name_error: set NameError(message) as current exception
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_set_name_error(p_message text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  name_error_type_id uuid := '00000000-0000-4000-a000-000000000024';
  msg_id uuid;
  args_id uuid;
  inst_id uuid := gen_random_uuid();
BEGIN
  msg_id := public.py_str_from_text(p_message);
  args_id := public.py_tuple_from_1(msg_id);
  INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, name_error_type_id);
  INSERT INTO public.py_base_exception_object (ob_base, ob_args) VALUES (inst_id, args_id);
  PERFORM public.py_err_set_object(name_error_type_id, inst_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- py_err_set_value_error: set ValueError(message) as current exception
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_set_value_error(p_message text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  value_error_type_id uuid := '00000000-0000-4000-a000-000000000023';
  msg_id uuid;
  args_id uuid;
  inst_id uuid := gen_random_uuid();
BEGIN
  msg_id := public.py_str_from_text(p_message);
  args_id := public.py_tuple_from_1(msg_id);
  INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, value_error_type_id);
  INSERT INTO public.py_base_exception_object (ob_base, ob_args) VALUES (inst_id, args_id);
  PERFORM public.py_err_set_object(value_error_type_id, inst_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- py_eval_frame: add py_traceback_here(frame_id, i) when py_err_occurred()
-- (traceback must be filled before handler lookup)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_eval_frame(frame_id UUID)
RETURNS UUID AS $$
DECLARE
    code_obj_id UUID;
    co_code_id UUID;
    bytecode bytea;
    exc_table bytea;
    opcode INTEGER;
    arg INTEGER;
    i INTEGER := 0;
    instruction_size INTEGER;
    return_value UUID := NULL;
    should_return BOOLEAN := FALSE;
    bytecode_length INTEGER;
    next_i INTEGER := NULL;
    handler_target integer;
    handler_depth integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_frame_object WHERE ob_base = frame_id) THEN
        RAISE EXCEPTION 'Frame with id % does not exist', frame_id;
    END IF;

    SELECT f_code INTO code_obj_id FROM public.py_frame_object WHERE ob_base = frame_id;
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'Frame with id % does not have a code object', frame_id;
    END IF;

    SELECT co_code INTO co_code_id FROM public.py_code_object WHERE ob_base = code_obj_id;
    IF co_code_id IS NULL THEN
        RAISE EXCEPTION 'Code object with id % does not have co_code', code_obj_id;
    END IF;

    SELECT bytes_value INTO bytecode FROM public.py_bytes_object WHERE ob_base = co_code_id;
    IF bytecode IS NULL THEN
        RAISE EXCEPTION 'Bytes object with id % does not have bytes_value', co_code_id;
    END IF;

    SELECT co_exceptiontable INTO exc_table FROM public.py_code_object WHERE ob_base = code_obj_id;

    bytecode_length := length(bytecode);

    WHILE i < bytecode_length LOOP
        next_i := NULL;
        opcode := get_byte(bytecode, i);
        arg := get_byte(bytecode, i + 1);

        CASE opcode
            WHEN 1 THEN
                PERFORM public.py_opcode_POP_TOP(frame_id);
            WHEN 100 THEN
                PERFORM public.py_opcode_LOAD_CONST(frame_id, arg);
            WHEN 101 THEN
                PERFORM public.py_opcode_LOAD_NAME(frame_id, arg);
            WHEN 141 THEN
                PERFORM public.py_opcode_CALL_FUNCTION(frame_id, arg);
            WHEN 90 THEN
                PERFORM public.py_opcode_STORE_NAME(frame_id, arg);
            WHEN 23 THEN
                PERFORM public.py_opcode_BINARY_ADD(frame_id);
            WHEN 24 THEN
                PERFORM public.py_opcode_BINARY_SUBTRACT(frame_id);
            WHEN 20 THEN
                PERFORM public.py_opcode_BINARY_MULTIPLY(frame_id);
            WHEN 107 THEN
                PERFORM public.py_opcode_COMPARE_OP(frame_id, arg);
            WHEN 110 THEN
                next_i := i + 2 + arg * 2;
            WHEN 114 THEN
                next_i := public.py_opcode_POP_JUMP_FORWARD_IF_FALSE(frame_id, i, arg);
            WHEN 115 THEN
                next_i := public.py_opcode_POP_JUMP_FORWARD_IF_TRUE(frame_id, i, arg);
            WHEN 35 THEN
                PERFORM public.py_opcode_PUSH_EXC_INFO(frame_id);
            WHEN 36 THEN
                PERFORM public.py_opcode_CHECK_EXC_MATCH(frame_id);
            WHEN 83 THEN
                return_value := public.py_stack_pop(frame_id);
                should_return := TRUE;
                UPDATE public.py_frame_object SET f_lasti = i WHERE ob_base = frame_id;
                EXIT;
            WHEN 89 THEN
                PERFORM public.py_opcode_POP_EXCEPT(frame_id);
            WHEN 119 THEN
                PERFORM public.py_opcode_RERAISE(frame_id);
            WHEN 130 THEN
                PERFORM public.py_opcode_RAISE_VARARGS(frame_id, arg);
            ELSE
                RAISE EXCEPTION 'Unknown opcode: % at byte offset %', opcode, i;
        END CASE;

        IF public.py_err_occurred() THEN
            PERFORM public.py_traceback_here(frame_id, i);
            IF exc_table IS NOT NULL AND length(exc_table) > 0 THEN
                SELECT h.target_offset, h.depth INTO handler_target, handler_depth
                FROM public.py_get_exception_handler(exc_table, i / 2) h;
                IF FOUND THEN
                    PERFORM public.py_stack_trim(frame_id, handler_depth);
                    next_i := handler_target * 2;
                ELSE
                    RETURN NULL;
                END IF;
            ELSE
                RETURN NULL;
            END IF;
        END IF;

        IF opcode != 83 THEN
            UPDATE public.py_frame_object SET f_lasti = i WHERE ob_base = frame_id;
        END IF;

        instruction_size := public.py_get_opcode_size(opcode);
        IF next_i IS NOT NULL THEN
            i := next_i;
        ELSE
            i := i + instruction_size;
        END IF;
    END LOOP;

    IF should_return THEN
        RETURN return_value;
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;
