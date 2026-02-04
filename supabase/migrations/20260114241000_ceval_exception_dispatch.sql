-- ============================================================================
-- Exception dispatch in py_eval_frame (CPython 3.11)
-- 20260114241000_ceval_exception_dispatch.sql
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md
-- - py_err_restore: restore exception state (for POP_EXCEPT)
-- - py_stack_trim, py_stack_peek: for unwinding and CHECK_EXC_MATCH
-- - py_type_issubclass: for CHECK_EXC_MATCH (isinstance)
-- - RAISE_VARARGS(130), RERAISE(119), POP_EXCEPT(89), PUSH_EXC_INFO(35), CHECK_EXC_MATCH(36)
-- - py_eval_frame: only dispatch when this opcode just set the exception (NOT had_err AND py_err_occurred())
-- ============================================================================

-- Fixed UUIDs (from exception schema / bootstrap)
-- RuntimeError: 00000000-0000-4000-a000-000000000026
-- None: 00000000-0000-4000-b000-000000000001
-- type type: 00000000-0000-4000-a000-000000000002

-- ----------------------------------------------------------------------------
-- py_err_restore: restore exception state (type, value, traceback)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_restore(p_type_id uuid, p_value_id uuid, p_traceback_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.py_exception_state
  SET exc_type_id = p_type_id, exc_value_id = p_value_id, exc_traceback_id = p_traceback_id
  WHERE id = '00000000-0000-4000-e000-000000000001';
END;
$$;

COMMENT ON FUNCTION public.py_err_restore(uuid, uuid, uuid) IS
  'Restore error indicator (for POP_EXCEPT).';

-- ----------------------------------------------------------------------------
-- py_stack_trim: trim frame stack to depth (for exception unwinding)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_stack_trim(p_frame_id uuid, p_depth integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  cur_stack uuid[];
BEGIN
  SELECT f_valuestack INTO cur_stack FROM public.py_frame_object WHERE ob_base = p_frame_id;
  IF cur_stack IS NULL THEN
    RETURN;
  END IF;
  IF p_depth < 0 THEN
    p_depth := 0;
  END IF;
  IF array_length(cur_stack, 1) IS NOT NULL THEN
    UPDATE public.py_frame_object
    SET f_valuestack = cur_stack[1:least(array_length(cur_stack, 1), p_depth)]
    WHERE ob_base = p_frame_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.py_stack_trim(uuid, integer) IS
  'Trim value stack to at most depth elements (exception unwinding).';

-- ----------------------------------------------------------------------------
-- py_stack_peek: return TOS without popping (for CHECK_EXC_MATCH)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_stack_peek(p_frame_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT f_valuestack[array_length(f_valuestack, 1)]
  FROM public.py_frame_object
  WHERE ob_base = p_frame_id AND array_length(f_valuestack, 1) > 0;
$$;

COMMENT ON FUNCTION public.py_stack_peek(uuid) IS
  'Return top of stack without popping.';

-- ----------------------------------------------------------------------------
-- py_type_issubclass: true if sub_type is super_type or subclass (for CHECK_EXC_MATCH)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_type_issubclass(p_sub_type_id uuid, p_super_type_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  bases uuid[];
  tp_bases_id uuid;
  i integer;
BEGIN
  IF p_sub_type_id IS NULL OR p_super_type_id IS NULL THEN
    RETURN FALSE;
  END IF;
  IF p_sub_type_id = p_super_type_id THEN
    RETURN TRUE;
  END IF;
  SELECT y.tp_bases INTO tp_bases_id FROM public.py_type_object y WHERE y.ob_base = p_sub_type_id;
  IF tp_bases_id IS NULL THEN
    RETURN FALSE;
  END IF;
  SELECT t.ob_item INTO bases FROM public.py_tuple_object t WHERE t.ob_base = tp_bases_id;
  IF bases IS NULL OR array_length(bases, 1) IS NULL THEN
    RETURN FALSE;
  END IF;
  FOR i IN 1 .. array_length(bases, 1) LOOP
    IF public.py_type_issubclass(bases[i], p_super_type_id) THEN
      RETURN TRUE;
    END IF;
  END LOOP;
  RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION public.py_type_issubclass(uuid, uuid) IS
  'True if sub_type is super_type or a subclass (for isinstance / CHECK_EXC_MATCH).';

-- ----------------------------------------------------------------------------
-- py_tuple_from_3: create tuple (a, b, c) for PUSH_EXC_INFO saved state
-- CPython 고증: tuple 타입은 PyTuple_Type 상수 참조. 부트스트랩 tuple 타입 UUID 사용.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_tuple_from_3(p_a uuid, p_b uuid, p_c uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  id_tuple_type constant uuid := '00000000-0000-4000-a000-000000000007';
  new_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.py_object (id, ob_type) VALUES (new_id, id_tuple_type);
  INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES (new_id, ARRAY[p_a, p_b, p_c]);
  RETURN new_id;
END;
$$;

-- Exception opcode handlers (130, 119, 35, 89, 36): 241001–241005 (one per file).
-- py_eval_frame은 재정의하지 않음. 단일 정의: 20260114241100_ceval_eval_frame_final.sql
