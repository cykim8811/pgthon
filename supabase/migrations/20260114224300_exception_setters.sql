-- ============================================================================
-- Exception setters (CPython 고증) — 의존성 순서: 224200 직후, 225000 직전
-- 20260114224300_exception_setters.sql
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md §2.7, docs/MIGRATION_EXCEPTION_ORDER.md
-- py_str_from_text, py_tuple_from_1, py_err_set_type_error, py_err_set_name_error, py_err_set_value_error
-- builtin_functions(225000), type_method_slots(226000), tp_hash_slot(235000)에서 사용.
-- ============================================================================

-- Fixed: str 00000000-0000-4000-a000-000000000003
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
-- CPython 고증: tuple 타입은 PyTuple_Type 상수 참조. 부트스트랩 tuple 타입 UUID 사용.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_tuple_from_1(p_elem uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  id_tuple_type constant uuid := '00000000-0000-4000-a000-000000000007';
  new_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.py_object (id, ob_type) VALUES (new_id, id_tuple_type);
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
-- py_err_set_attribute_error: set AttributeError(message) as current exception
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_set_attribute_error(p_message text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  attribute_error_type_id uuid := '00000000-0000-4000-a000-000000000027';
  msg_id uuid;
  args_id uuid;
  inst_id uuid := gen_random_uuid();
BEGIN
  msg_id := public.py_str_from_text(p_message);
  args_id := public.py_tuple_from_1(msg_id);
  INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, attribute_error_type_id);
  INSERT INTO public.py_base_exception_object (ob_base, ob_args) VALUES (inst_id, args_id);
  PERFORM public.py_err_set_object(attribute_error_type_id, inst_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- py_err_set_index_error: set IndexError(message) as current exception
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_set_index_error(p_message text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  index_error_type_id uuid := '00000000-0000-4000-a000-000000000028';
  msg_id uuid;
  args_id uuid;
  inst_id uuid := gen_random_uuid();
BEGIN
  msg_id := public.py_str_from_text(p_message);
  args_id := public.py_tuple_from_1(msg_id);
  INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, index_error_type_id);
  INSERT INTO public.py_base_exception_object (ob_base, ob_args) VALUES (inst_id, args_id);
  PERFORM public.py_err_set_object(index_error_type_id, inst_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- py_err_set_stop_iteration: set StopIteration as current exception
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_set_stop_iteration()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  stop_iteration_type_id uuid := '00000000-0000-4000-a000-00000000002a';
  msg_id uuid;
  args_id uuid;
  inst_id uuid := gen_random_uuid();
BEGIN
  msg_id := public.py_str_from_text('');
  args_id := public.py_tuple_from_1(msg_id);
  INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, stop_iteration_type_id);
  INSERT INTO public.py_base_exception_object (ob_base, ob_args) VALUES (inst_id, args_id);
  PERFORM public.py_err_set_object(stop_iteration_type_id, inst_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- py_err_set_key_error: set KeyError(message) as current exception
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_set_key_error(p_message text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  key_error_type_id uuid := '00000000-0000-4000-a000-000000000029';
  msg_id uuid;
  args_id uuid;
  inst_id uuid := gen_random_uuid();
BEGIN
  msg_id := public.py_str_from_text(p_message);
  args_id := public.py_tuple_from_1(msg_id);
  INSERT INTO public.py_object (id, ob_type) VALUES (inst_id, key_error_type_id);
  INSERT INTO public.py_base_exception_object (ob_base, ob_args) VALUES (inst_id, args_id);
  PERFORM public.py_err_set_object(key_error_type_id, inst_id);
END;
$$;
