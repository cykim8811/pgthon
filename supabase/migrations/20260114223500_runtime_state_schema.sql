-- ============================================================================
-- Runtime / Interpreter / Thread state hierarchy (CPython 3.11)
-- 20260114223500_runtime_state_schema.sql
--
-- CPython organises runtime state as:
--   PyRuntimeState → PyInterpreterState → PyThreadState
-- Exception state (error indicator) lives on PyThreadState.
--
-- These are C structs in CPython, NOT Python objects, so they are standalone
-- tables rather than py_object subclasses.
--
-- A PostgreSQL session variable (elytra.thread_state_id) acts as the
-- equivalent of CPython's _PyThreadState_GET() thread-local storage.
-- ============================================================================

-- 1. py_runtime_state (1 row per database — process-level singleton)
CREATE TABLE public.py_runtime_state (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid()
);

COMMENT ON TABLE public.py_runtime_state IS
  'CPython PyRuntimeState — one row per database (process singleton).';

-- 2. py_interpreter_state (N per runtime — one per interpreter)
CREATE TABLE public.py_interpreter_state (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  runtime_id UUID NOT NULL REFERENCES public.py_runtime_state(id),
  interp_builtins UUID REFERENCES public.py_object(id)
);

COMMENT ON TABLE public.py_interpreter_state IS
  'CPython PyInterpreterState — one per interpreter, references runtime.';

-- 3. py_thread_state (M per interpreter — one per "thread")
CREATE TABLE public.py_thread_state (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  interp_id UUID NOT NULL REFERENCES public.py_interpreter_state(id),
  -- Exception state (replaces py_exception_state)
  exc_type_id UUID REFERENCES public.py_object(id),
  exc_value_id UUID REFERENCES public.py_object(id),
  exc_traceback_id UUID REFERENCES public.py_object(id),
  -- Current frame
  current_frame UUID REFERENCES public.py_object(id),
  -- Recursion depth
  recursion_depth INTEGER DEFAULT 0
);

COMMENT ON TABLE public.py_thread_state IS
  'CPython PyThreadState — one per thread, holds exception state (error indicator).';

-- ----------------------------------------------------------------------------
-- Bootstrap: default runtime → interpreter → thread state
-- ----------------------------------------------------------------------------
INSERT INTO public.py_runtime_state (id)
VALUES ('00000000-0000-4000-e000-000000000010');

INSERT INTO public.py_interpreter_state (id, runtime_id, interp_builtins)
VALUES (
  '00000000-0000-4000-e000-000000000020',
  '00000000-0000-4000-e000-000000000010',
  '00000000-0000-4000-b000-000000000002'  -- builtins_module singleton
);

INSERT INTO public.py_thread_state (id, interp_id)
VALUES (
  '00000000-0000-4000-e000-000000000030',
  '00000000-0000-4000-e000-000000000020'
);

-- ----------------------------------------------------------------------------
-- RLS policies (allow all, matching existing convention)
-- ----------------------------------------------------------------------------
ALTER TABLE public.py_runtime_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_interpreter_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_thread_state ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow read/write py_runtime_state"
  ON public.py_runtime_state FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow read/write py_interpreter_state"
  ON public.py_interpreter_state FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow read/write py_thread_state"
  ON public.py_thread_state FOR ALL USING (true) WITH CHECK (true);
