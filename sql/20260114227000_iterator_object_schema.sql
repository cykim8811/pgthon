-- ============================================================================
-- Migration: Iterator Object Schemas (CPython 3.11)
-- Created: 2026-01-14 22:70:00
--
-- Purpose:
--   Defines iterator object tables for list, tuple, dict, and str iterators.
--   Each iterator tracks a reference to the source container and an index
--   indicating the current position in the iteration.
--
-- CPython equivalents:
--   - listiterobject (listobject.c)
--   - tupleiterobject (tupleobject.c)
--   - dictiterobject (dictobject.c) — dict_keyiterator
--   - striterobject (unicodeobject.c)
-- ============================================================================

-- py_list_iterator_object (CPython's listiterobject)
create table public.py_list_iterator_object (
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  it_seq uuid references public.py_object(id) not null, -- The list being iterated
  it_index integer not null default 0                    -- Current position
);

-- py_tuple_iterator_object (CPython's tupleiterobject)
create table public.py_tuple_iterator_object (
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  it_seq uuid references public.py_object(id) not null, -- The tuple being iterated
  it_index integer not null default 0                    -- Current position
);

-- py_dict_keyiterator_object (CPython's dictiterobject for keys)
create table public.py_dict_keyiterator_object (
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  it_dict uuid references public.py_object(id) not null, -- The dict being iterated
  it_pos integer not null default 0                       -- Current entry position
);

-- py_str_iterator_object (CPython's striterobject)
create table public.py_str_iterator_object (
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  it_seq uuid references public.py_object(id) not null, -- The string being iterated
  it_index integer not null default 0                    -- Current character position
);

-- Enable Row Level Security
alter table public.py_list_iterator_object enable row level security;
alter table public.py_tuple_iterator_object enable row level security;
alter table public.py_dict_keyiterator_object enable row level security;
alter table public.py_str_iterator_object enable row level security;

-- Default Policies
create policy "Allow all py_list_iterator_object"
  on public.py_list_iterator_object for all using (true) with check (true);
create policy "Allow all py_tuple_iterator_object"
  on public.py_tuple_iterator_object for all using (true) with check (true);
create policy "Allow all py_dict_keyiterator_object"
  on public.py_dict_keyiterator_object for all using (true) with check (true);
create policy "Allow all py_str_iterator_object"
  on public.py_str_iterator_object for all using (true) with check (true);
