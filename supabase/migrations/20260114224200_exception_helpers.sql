-- ============================================================================
-- Exception helpers (CPython 3.11) — 의존성 순서: 224100 직후, 225000 직전
-- 20260114224200_exception_helpers.sql
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md, docs/MIGRATION_EXCEPTION_ORDER.md
-- py_err_set_object, py_err_clear, py_err_occurred, py_err_get_raised, py_traceback_here
-- ============================================================================

-- ----------------------------------------------------------------------------
-- py_err_set_object: set current exception (error indicator)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_set_object(p_type_id uuid, p_value_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.py_thread_state
  SET exc_type_id = p_type_id, exc_value_id = p_value_id, exc_traceback_id = NULL
  WHERE id = current_setting('pgthon.thread_state_id')::uuid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'py_thread_state row not found for id %', current_setting('pgthon.thread_state_id');
  END IF;
END;
$$;

COMMENT ON FUNCTION public.py_err_set_object(uuid, uuid) IS
  'Set error indicator (CPython PyErr_SetObject). Traceback filled separately via py_traceback_here.';

-- ----------------------------------------------------------------------------
-- py_err_clear: clear exception state
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_clear()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.py_thread_state
  SET exc_type_id = NULL, exc_value_id = NULL, exc_traceback_id = NULL
  WHERE id = current_setting('pgthon.thread_state_id')::uuid;
END;
$$;

COMMENT ON FUNCTION public.py_err_clear() IS
  'Clear error indicator (CPython PyErr_Clear).';

-- ----------------------------------------------------------------------------
-- py_err_occurred: true if an exception is set
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_occurred()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT exc_type_id IS NOT NULL
  FROM public.py_thread_state
  WHERE id = current_setting('pgthon.thread_state_id')::uuid;
$$;

COMMENT ON FUNCTION public.py_err_occurred() IS
  'True if error indicator is set (CPython PyErr_Occurred).';

-- ----------------------------------------------------------------------------
-- py_err_get_raised: return (exc_type_id, exc_value_id, exc_traceback_id)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_err_get_raised()
RETURNS TABLE(exc_type_id uuid, exc_value_id uuid, exc_traceback_id uuid)
LANGUAGE sql
STABLE
AS $$
  SELECT e.exc_type_id, e.exc_value_id, e.exc_traceback_id
  FROM public.py_thread_state e
  WHERE e.id = current_setting('pgthon.thread_state_id')::uuid;
$$;

COMMENT ON FUNCTION public.py_err_get_raised() IS
  'Return current exception (type, value, traceback). Empty row if no exception.';

-- ----------------------------------------------------------------------------
-- py_traceback_here: prepend current frame to current exception traceback
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_traceback_here(p_frame_id uuid, p_lasti integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  cur_tb_id uuid;
  new_tb_id uuid := gen_random_uuid();
  traceback_type_id uuid := '00000000-0000-4000-a000-000000000025';
BEGIN
  SELECT e.exc_traceback_id INTO cur_tb_id
  FROM public.py_thread_state e
  WHERE e.id = current_setting('pgthon.thread_state_id')::uuid;

  IF NOT FOUND OR (SELECT exc_type_id FROM public.py_thread_state WHERE id = current_setting('pgthon.thread_state_id')::uuid) IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.py_object (id, ob_type) VALUES (new_tb_id, traceback_type_id);
  INSERT INTO public.py_traceback_object (ob_base, tb_next, tb_frame, tb_lasti)
  VALUES (new_tb_id, cur_tb_id, p_frame_id, p_lasti);

  UPDATE public.py_thread_state
  SET exc_traceback_id = new_tb_id
  WHERE id = current_setting('pgthon.thread_state_id')::uuid;
END;
$$;

COMMENT ON FUNCTION public.py_traceback_here(uuid, integer) IS
  'Prepend frame to current exception traceback (CPython PyTraceBack_Here). lasti = byte offset in frame.';
