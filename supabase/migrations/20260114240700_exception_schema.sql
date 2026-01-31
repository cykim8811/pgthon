-- ============================================================================
-- Exception handling schema (CPython 3.11)
-- 20260114240700_exception_schema.sql
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md
-- 1. py_exception_state — current exception (error indicator)
-- 2. py_base_exception_object — exception instance (args)
-- 3. py_traceback_object — traceback chain
-- 4. py_code_object.co_exceptiontable — 3.11 exception table
-- 5. Bootstrap: BaseException, Exception, TypeError, ValueError, NameError
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. py_exception_state (error indicator, one row per execution context)
-- ----------------------------------------------------------------------------
create table public.py_exception_state (
  id uuid primary key default gen_random_uuid(),
  exc_type_id uuid references public.py_object(id),
  exc_value_id uuid references public.py_object(id),
  exc_traceback_id uuid references public.py_object(id)
);

comment on table public.py_exception_state is 'Current exception (CPython error indicator). exc_type_id NULL = no exception.';

-- Single row for single-threaded Elytra (fixed id so callers can UPDATE it)
insert into public.py_exception_state (id, exc_type_id, exc_value_id, exc_traceback_id)
values ('00000000-0000-4000-e000-000000000001', null, null, null);

-- ----------------------------------------------------------------------------
-- 2. py_base_exception_object (BaseException instance: args)
-- ----------------------------------------------------------------------------
create table public.py_base_exception_object (
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  ob_args uuid references public.py_object(id)
);

comment on table public.py_base_exception_object is 'Exception instance (CPython BaseException). ob_args = tuple of constructor args.';

-- ----------------------------------------------------------------------------
-- 3. py_traceback_object (traceback chain)
-- ----------------------------------------------------------------------------
create table public.py_traceback_object (
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  tb_next uuid references public.py_object(id),
  tb_frame uuid references public.py_object(id),
  tb_lasti integer not null
);

comment on table public.py_traceback_object is 'Traceback entry (CPython PyTracebackObject). tb_lasti = byte offset in frame.';

-- ----------------------------------------------------------------------------
-- 4. py_code_object: add co_exceptiontable (Python 3.11)
-- ----------------------------------------------------------------------------
alter table public.py_code_object
add column if not exists co_exceptiontable bytea;

comment on column public.py_code_object.co_exceptiontable is 'Exception table (3.11): start, end, target, depth. NULL = no try/except.';

-- ----------------------------------------------------------------------------
-- 5. Bootstrap: exception types (BaseException, Exception, TypeError, ...)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
  ID_TYPE_TYPE   uuid := '00000000-0000-4000-a000-000000000002';
  ID_TUPLE_TYPE  uuid := '00000000-0000-4000-a000-000000000007';
  ID_TUPLE_BASES_OBJECT uuid := (select u.ob_base from public.py_type_object t join public.py_tuple_object u on u.ob_base = t.tp_bases where t.ob_base = ID_OBJECT_TYPE limit 1);
  -- Exception type IDs (fixed)
  ID_BASE_EXCEPTION_TYPE uuid := '00000000-0000-4000-a000-000000000020';
  ID_EXCEPTION_TYPE      uuid := '00000000-0000-4000-a000-000000000021';
  ID_TYPE_ERROR_TYPE     uuid := '00000000-0000-4000-a000-000000000022';
  ID_VALUE_ERROR_TYPE    uuid := '00000000-0000-4000-a000-000000000023';
  ID_NAME_ERROR_TYPE     uuid := '00000000-0000-4000-a000-000000000024';
  ID_TRACEBACK_TYPE      uuid := '00000000-0000-4000-a000-000000000025';
  ID_RUNTIME_ERROR_TYPE  uuid := '00000000-0000-4000-a000-000000000026';
  -- tp_dict for each exception type + traceback type
  ID_DICT_BASE_EXCEPTION uuid := gen_random_uuid();
  ID_DICT_EXCEPTION      uuid := gen_random_uuid();
  ID_DICT_TYPE_ERROR     uuid := gen_random_uuid();
  ID_DICT_VALUE_ERROR    uuid := gen_random_uuid();
  ID_DICT_NAME_ERROR     uuid := gen_random_uuid();
  ID_DICT_TRACEBACK      uuid := gen_random_uuid();
  ID_DICT_RUNTIME_ERROR  uuid := gen_random_uuid();
  -- tp_bases tuples: (object,), (BaseException,), (Exception,)
  ID_TUPLE_BASES_BASE_EXCEPTION uuid := gen_random_uuid();
  ID_TUPLE_BASES_EXCEPTION      uuid := gen_random_uuid();
BEGIN
  -- Resolve tp_bases (object,) if not found via join (fallback: same tuple used by other types)
  IF ID_TUPLE_BASES_OBJECT IS NULL THEN
    SELECT tp_bases INTO ID_TUPLE_BASES_OBJECT FROM public.py_type_object WHERE ob_base = ID_TYPE_TYPE LIMIT 1;
  END IF;

  -- Phase 1: py_object rows (ob_type = NULL)
  INSERT INTO public.py_object (id, ob_type) VALUES
    (ID_BASE_EXCEPTION_TYPE, NULL),
    (ID_EXCEPTION_TYPE,      NULL),
    (ID_TYPE_ERROR_TYPE,    NULL),
    (ID_VALUE_ERROR_TYPE,   NULL),
    (ID_NAME_ERROR_TYPE,    NULL),
    (ID_TRACEBACK_TYPE,     NULL),
    (ID_RUNTIME_ERROR_TYPE, NULL),
    (ID_DICT_BASE_EXCEPTION, NULL),
    (ID_DICT_EXCEPTION,      NULL),
    (ID_DICT_TYPE_ERROR,     NULL),
    (ID_DICT_VALUE_ERROR,    NULL),
    (ID_DICT_NAME_ERROR,     NULL),
    (ID_DICT_TRACEBACK,      NULL),
    (ID_DICT_RUNTIME_ERROR,  NULL),
    (ID_TUPLE_BASES_BASE_EXCEPTION, NULL),
    (ID_TUPLE_BASES_EXCEPTION,      NULL);

  -- Phase 2: py_type_object rows
  INSERT INTO public.py_type_object (ob_base, tp_name) VALUES
    (ID_BASE_EXCEPTION_TYPE, 'BaseException'),
    (ID_EXCEPTION_TYPE,      'Exception'),
    (ID_TYPE_ERROR_TYPE,    'TypeError'),
    (ID_VALUE_ERROR_TYPE,   'ValueError'),
    (ID_NAME_ERROR_TYPE,    'NameError'),
    (ID_TRACEBACK_TYPE,     'traceback'),
    (ID_RUNTIME_ERROR_TYPE, 'RuntimeError');

  -- Phase 3: ob_type = type
  UPDATE public.py_object SET ob_type = ID_TYPE_TYPE
  WHERE id IN (ID_BASE_EXCEPTION_TYPE, ID_EXCEPTION_TYPE, ID_TYPE_ERROR_TYPE, ID_VALUE_ERROR_TYPE, ID_NAME_ERROR_TYPE, ID_TRACEBACK_TYPE, ID_RUNTIME_ERROR_TYPE);

  UPDATE public.py_object SET ob_type = ID_TUPLE_TYPE
  WHERE id IN (ID_TUPLE_BASES_BASE_EXCEPTION, ID_TUPLE_BASES_EXCEPTION);

  UPDATE public.py_object SET ob_type = (SELECT ob_base FROM public.py_type_object WHERE tp_name = 'dict' LIMIT 1)
  WHERE id IN (ID_DICT_BASE_EXCEPTION, ID_DICT_EXCEPTION, ID_DICT_TYPE_ERROR, ID_DICT_VALUE_ERROR, ID_DICT_NAME_ERROR, ID_DICT_TRACEBACK, ID_DICT_RUNTIME_ERROR);

  -- Phase 4: tp_bases tuples (tuple contents)
  INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES
    (ID_TUPLE_BASES_BASE_EXCEPTION, ARRAY[ID_OBJECT_TYPE]),
    (ID_TUPLE_BASES_EXCEPTION,      ARRAY[ID_BASE_EXCEPTION_TYPE]);

  -- Phase 5: tp_dict (dict objects)
  INSERT INTO public.py_dict_object (ob_base) VALUES
    (ID_DICT_BASE_EXCEPTION),
    (ID_DICT_EXCEPTION),
    (ID_DICT_TYPE_ERROR),
    (ID_DICT_VALUE_ERROR),
    (ID_DICT_NAME_ERROR),
    (ID_DICT_TRACEBACK),
    (ID_DICT_RUNTIME_ERROR);

  -- Phase 6: tp_bases and tp_dict on type objects (BaseException extends object -> use ID_TUPLE_BASES_BASE_EXCEPTION)
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_BASE_EXCEPTION, tp_dict = ID_DICT_BASE_EXCEPTION WHERE ob_base = ID_BASE_EXCEPTION_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_BASE_EXCEPTION, tp_dict = ID_DICT_EXCEPTION WHERE ob_base = ID_EXCEPTION_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_TYPE_ERROR  WHERE ob_base = ID_TYPE_ERROR_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_VALUE_ERROR WHERE ob_base = ID_VALUE_ERROR_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_NAME_ERROR WHERE ob_base = ID_NAME_ERROR_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_BASE_EXCEPTION, tp_dict = ID_DICT_TRACEBACK WHERE ob_base = ID_TRACEBACK_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_RUNTIME_ERROR WHERE ob_base = ID_RUNTIME_ERROR_TYPE;
END $$;

-- RLS
alter table public.py_exception_state enable row level security;
alter table public.py_base_exception_object enable row level security;
alter table public.py_traceback_object enable row level security;

create policy "Allow read/write py_exception_state"
  on public.py_exception_state for all using (true) with check (true);
create policy "Allow read/write py_base_exception_object"
  on public.py_base_exception_object for all using (true) with check (true);
create policy "Allow read/write py_traceback_object"
  on public.py_traceback_object for all using (true) with check (true);
