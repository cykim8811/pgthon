-- ============================================================================
-- Exception handling schema (CPython 3.11) — 의존성 순서: 224000 직후, 225000 직전
-- 20260114224100_exception_schema.sql
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md, docs/CODE_OBJECT_3_11.md, docs/MIGRATION_EXCEPTION_ORDER.md
-- builtin_functions(225000), type_method_slots(226000), tp_hash_slot(235000)에서
-- py_err_occurred / py_err_set_type_error / py_err_set_name_error 를 쓰려면
-- 이 스키마·bootstrap이 먼저 적용되어야 함.
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
-- 4b. py_code_object: add CPython 3.11 optional fields (CODE_OBJECT_3_11.md)
-- ----------------------------------------------------------------------------
alter table public.py_code_object add column if not exists co_posonlyargcount integer default 0;
alter table public.py_code_object add column if not exists co_kwonlyargcount integer default 0;
alter table public.py_code_object add column if not exists co_nlocals integer;
alter table public.py_code_object add column if not exists co_stacksize integer;
alter table public.py_code_object add column if not exists co_flags integer default 0;
alter table public.py_code_object add column if not exists co_firstlineno integer default 0;
comment on column public.py_code_object.co_posonlyargcount is 'CPython 3.11: positional-only arg count. 0 if not set.';
comment on column public.py_code_object.co_kwonlyargcount is 'CPython 3.11: keyword-only arg count. 0 if not set.';
comment on column public.py_code_object.co_nlocals is 'CPython 3.11: number of local vars. NULL = derive from co_varnames.';
comment on column public.py_code_object.co_stacksize is 'CPython 3.11: stack depth. NULL = VM may ignore.';
comment on column public.py_code_object.co_flags is 'CPython 3.11: CO_OPTIMIZED, CO_NEWLOCALS, etc. 0 if not set.';
comment on column public.py_code_object.co_firstlineno is 'CPython 3.11: first source line (traceback). 0 if not set.';

-- ----------------------------------------------------------------------------
-- 5. Bootstrap: exception types (BaseException, Exception, TypeError, ...)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  ID_OBJECT_TYPE uuid := '00000000-0000-4000-a000-000000000001';
  ID_TYPE_TYPE   uuid := '00000000-0000-4000-a000-000000000002';
  ID_DICT_TYPE   uuid := '00000000-0000-4000-a000-000000000006';  -- builtin dict type (bootstrap 223000)
  ID_TUPLE_TYPE  uuid := '00000000-0000-4000-a000-000000000007';
  ID_TUPLE_BASES_OBJECT uuid := (select u.ob_base from public.py_type_object t join public.py_tuple_object u on u.ob_base = t.tp_bases where t.ob_base = ID_OBJECT_TYPE limit 1);
  ID_BASE_EXCEPTION_TYPE uuid := '00000000-0000-4000-a000-000000000020';
  ID_EXCEPTION_TYPE      uuid := '00000000-0000-4000-a000-000000000021';
  ID_TYPE_ERROR_TYPE     uuid := '00000000-0000-4000-a000-000000000022';
  ID_VALUE_ERROR_TYPE    uuid := '00000000-0000-4000-a000-000000000023';
  ID_NAME_ERROR_TYPE     uuid := '00000000-0000-4000-a000-000000000024';
  ID_TRACEBACK_TYPE      uuid := '00000000-0000-4000-a000-000000000025';
  ID_RUNTIME_ERROR_TYPE  uuid := '00000000-0000-4000-a000-000000000026';
  ID_ATTRIBUTE_ERROR_TYPE uuid := '00000000-0000-4000-a000-000000000027';
  ID_INDEX_ERROR_TYPE    uuid := '00000000-0000-4000-a000-000000000028';
  ID_KEY_ERROR_TYPE      uuid := '00000000-0000-4000-a000-000000000029';
  ID_STOP_ITERATION_TYPE uuid := '00000000-0000-4000-a000-00000000002a';
  ID_ZERO_DIVISION_ERROR_TYPE uuid := '00000000-0000-4000-a000-00000000002b';
  ID_DICT_BASE_EXCEPTION uuid := gen_random_uuid();
  ID_DICT_EXCEPTION      uuid := gen_random_uuid();
  ID_DICT_TYPE_ERROR     uuid := gen_random_uuid();
  ID_DICT_VALUE_ERROR    uuid := gen_random_uuid();
  ID_DICT_NAME_ERROR     uuid := gen_random_uuid();
  ID_DICT_TRACEBACK      uuid := gen_random_uuid();
  ID_DICT_RUNTIME_ERROR  uuid := gen_random_uuid();
  ID_DICT_ATTRIBUTE_ERROR uuid := gen_random_uuid();
  ID_DICT_INDEX_ERROR    uuid := gen_random_uuid();
  ID_DICT_KEY_ERROR      uuid := gen_random_uuid();
  ID_DICT_STOP_ITERATION uuid := gen_random_uuid();
  ID_DICT_ZERO_DIVISION_ERROR uuid := gen_random_uuid();
  ID_TUPLE_BASES_BASE_EXCEPTION uuid := gen_random_uuid();
  ID_TUPLE_BASES_EXCEPTION      uuid := gen_random_uuid();
BEGIN
  IF ID_TUPLE_BASES_OBJECT IS NULL THEN
    SELECT tp_bases INTO ID_TUPLE_BASES_OBJECT FROM public.py_type_object WHERE ob_base = ID_TYPE_TYPE LIMIT 1;
  END IF;

  INSERT INTO public.py_object (id, ob_type) VALUES
    (ID_BASE_EXCEPTION_TYPE, NULL),
    (ID_EXCEPTION_TYPE,      NULL),
    (ID_TYPE_ERROR_TYPE,    NULL),
    (ID_VALUE_ERROR_TYPE,   NULL),
    (ID_NAME_ERROR_TYPE,    NULL),
    (ID_TRACEBACK_TYPE,     NULL),
    (ID_RUNTIME_ERROR_TYPE, NULL),
    (ID_ATTRIBUTE_ERROR_TYPE, NULL),
    (ID_INDEX_ERROR_TYPE,   NULL),
    (ID_KEY_ERROR_TYPE,     NULL),
    (ID_STOP_ITERATION_TYPE, NULL),
    (ID_ZERO_DIVISION_ERROR_TYPE, NULL),
    (ID_DICT_BASE_EXCEPTION, NULL),
    (ID_DICT_EXCEPTION,      NULL),
    (ID_DICT_TYPE_ERROR,     NULL),
    (ID_DICT_VALUE_ERROR,    NULL),
    (ID_DICT_NAME_ERROR,     NULL),
    (ID_DICT_TRACEBACK,      NULL),
    (ID_DICT_RUNTIME_ERROR,  NULL),
    (ID_DICT_ATTRIBUTE_ERROR, NULL),
    (ID_DICT_INDEX_ERROR,    NULL),
    (ID_DICT_KEY_ERROR,      NULL),
    (ID_DICT_STOP_ITERATION, NULL),
    (ID_DICT_ZERO_DIVISION_ERROR, NULL),
    (ID_TUPLE_BASES_BASE_EXCEPTION, NULL),
    (ID_TUPLE_BASES_EXCEPTION,      NULL);

  INSERT INTO public.py_type_object (ob_base, tp_name) VALUES
    (ID_BASE_EXCEPTION_TYPE, 'BaseException'),
    (ID_EXCEPTION_TYPE,      'Exception'),
    (ID_TYPE_ERROR_TYPE,    'TypeError'),
    (ID_VALUE_ERROR_TYPE,   'ValueError'),
    (ID_NAME_ERROR_TYPE,    'NameError'),
    (ID_TRACEBACK_TYPE,     'traceback'),
    (ID_RUNTIME_ERROR_TYPE, 'RuntimeError'),
    (ID_ATTRIBUTE_ERROR_TYPE, 'AttributeError'),
    (ID_INDEX_ERROR_TYPE,   'IndexError'),
    (ID_KEY_ERROR_TYPE,     'KeyError'),
    (ID_STOP_ITERATION_TYPE, 'StopIteration'),
    (ID_ZERO_DIVISION_ERROR_TYPE, 'ZeroDivisionError');

  UPDATE public.py_object SET ob_type = ID_TYPE_TYPE
  WHERE id IN (ID_BASE_EXCEPTION_TYPE, ID_EXCEPTION_TYPE, ID_TYPE_ERROR_TYPE, ID_VALUE_ERROR_TYPE, ID_NAME_ERROR_TYPE, ID_TRACEBACK_TYPE, ID_RUNTIME_ERROR_TYPE, ID_ATTRIBUTE_ERROR_TYPE, ID_INDEX_ERROR_TYPE, ID_KEY_ERROR_TYPE, ID_STOP_ITERATION_TYPE, ID_ZERO_DIVISION_ERROR_TYPE);

  UPDATE public.py_object SET ob_type = ID_TUPLE_TYPE
  WHERE id IN (ID_TUPLE_BASES_BASE_EXCEPTION, ID_TUPLE_BASES_EXCEPTION);

  UPDATE public.py_object SET ob_type = ID_DICT_TYPE
  WHERE id IN (ID_DICT_BASE_EXCEPTION, ID_DICT_EXCEPTION, ID_DICT_TYPE_ERROR, ID_DICT_VALUE_ERROR, ID_DICT_NAME_ERROR, ID_DICT_TRACEBACK, ID_DICT_RUNTIME_ERROR, ID_DICT_ATTRIBUTE_ERROR, ID_DICT_INDEX_ERROR, ID_DICT_KEY_ERROR, ID_DICT_STOP_ITERATION, ID_DICT_ZERO_DIVISION_ERROR);

  INSERT INTO public.py_tuple_object (ob_base, ob_item) VALUES
    (ID_TUPLE_BASES_BASE_EXCEPTION, ARRAY[ID_OBJECT_TYPE]),
    (ID_TUPLE_BASES_EXCEPTION,      ARRAY[ID_BASE_EXCEPTION_TYPE]);

  INSERT INTO public.py_dict_object (ob_base) VALUES
    (ID_DICT_BASE_EXCEPTION),
    (ID_DICT_EXCEPTION),
    (ID_DICT_TYPE_ERROR),
    (ID_DICT_VALUE_ERROR),
    (ID_DICT_NAME_ERROR),
    (ID_DICT_TRACEBACK),
    (ID_DICT_RUNTIME_ERROR),
    (ID_DICT_ATTRIBUTE_ERROR),
    (ID_DICT_INDEX_ERROR),
    (ID_DICT_KEY_ERROR),
    (ID_DICT_STOP_ITERATION),
    (ID_DICT_ZERO_DIVISION_ERROR);

  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_BASE_EXCEPTION, tp_dict = ID_DICT_BASE_EXCEPTION WHERE ob_base = ID_BASE_EXCEPTION_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_BASE_EXCEPTION, tp_dict = ID_DICT_EXCEPTION WHERE ob_base = ID_EXCEPTION_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_TYPE_ERROR  WHERE ob_base = ID_TYPE_ERROR_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_VALUE_ERROR WHERE ob_base = ID_VALUE_ERROR_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_NAME_ERROR WHERE ob_base = ID_NAME_ERROR_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_BASE_EXCEPTION, tp_dict = ID_DICT_TRACEBACK WHERE ob_base = ID_TRACEBACK_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_RUNTIME_ERROR WHERE ob_base = ID_RUNTIME_ERROR_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_ATTRIBUTE_ERROR WHERE ob_base = ID_ATTRIBUTE_ERROR_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_INDEX_ERROR WHERE ob_base = ID_INDEX_ERROR_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_KEY_ERROR WHERE ob_base = ID_KEY_ERROR_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_STOP_ITERATION WHERE ob_base = ID_STOP_ITERATION_TYPE;
  UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_EXCEPTION, tp_dict = ID_DICT_ZERO_DIVISION_ERROR WHERE ob_base = ID_ZERO_DIVISION_ERROR_TYPE;
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
