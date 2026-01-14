-- Migration to add CPython-style internal object tables
-- Created at: 2026-01-14 22:00:00

-- 1. PyObject (The root of all objects)
create table public."PyObject" (
  id uuid primary key default gen_random_uuid(),
  ob_type uuid -- To be linked to PyTypeObject
);

-- 2. PyTypeObject (Defines types)
create table public."PyTypeObject" (
  id uuid primary key default gen_random_uuid(),
  ob_base uuid references public."PyObject"(id) on delete cascade unique,
  tp_name text not null,
  tp_bases uuid, -- To be linked to PyTupleObject
  tp_dict uuid   -- To be linked to PyDictObject
);

-- Link PyObject to its type
alter table public."PyObject" 
add constraint fk_py_object_type foreign key (ob_type) references public."PyTypeObject"(id);

-- 3. PyUnicodeObject
create table public."PyUnicodeObject" (
  id uuid primary key default gen_random_uuid(),
  ob_base uuid references public."PyObject"(id) on delete cascade unique,
  str_value text
);

-- 4. PyTupleObject
create table public."PyTupleObject" (
  id uuid primary key default gen_random_uuid(),
  ob_base uuid references public."PyObject"(id) on delete cascade unique,
  ob_item uuid[] -- Array of PyObject IDs
);

-- 5. PyListObject
create table public."PyListObject" (
  id uuid primary key default gen_random_uuid(),
  ob_base uuid references public."PyObject"(id) on delete cascade unique,
  ob_item uuid[] -- Array of PyObject IDs
);

-- 6. PyDictObject
create table public."PyDictObject" (
  id uuid primary key default gen_random_uuid(),
  ob_base uuid references public."PyObject"(id) on delete cascade unique,
  ma_table jsonb -- Metadata or placeholder for the hash table structure
);

-- 7. PyDictEntry (Entries for PyDictObject)
create table public."PyDictEntry" (
  id uuid primary key default gen_random_uuid(),
  dict_id uuid references public."PyDictObject"(id) on delete cascade,
  me_key uuid references public."PyObject"(id),
  me_value uuid references public."PyObject"(id)
);

-- 8. PyInstanceObject (Class instances)
create table public."PyInstanceObject" (
  id uuid primary key default gen_random_uuid(),
  ob_base uuid references public."PyObject"(id) on delete cascade unique,
  in_dict uuid references public."PyDictObject"(id)
);

-- Finalize PyTypeObject relationships
alter table public."PyTypeObject"
add constraint fk_py_type_objects_tp_bases foreign key (tp_bases) references public."PyTupleObject"(id),
add constraint fk_py_type_objects_tp_dict foreign key (tp_dict) references public."PyDictObject"(id);

-- Enable Row Level Security
alter table public."PyObject" enable row level security;
alter table public."PyTypeObject" enable row level security;
alter table public."PyUnicodeObject" enable row level security;
alter table public."PyTupleObject" enable row level security;
alter table public."PyListObject" enable row level security;
alter table public."PyDictObject" enable row level security;
alter table public."PyDictEntry" enable row level security;
alter table public."PyInstanceObject" enable row level security;

-- Default Policies (Allow authenticated users to read everything for now)
create policy "Authenticated users can view PyObject" on public."PyObject" for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view PyTypeObject" on public."PyTypeObject" for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view PyUnicodeObject" on public."PyUnicodeObject" for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view PyTupleObject" on public."PyTupleObject" for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view PyListObject" on public."PyListObject" for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view PyDictObject" on public."PyDictObject" for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view PyDictEntry" on public."PyDictEntry" for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view PyInstanceObject" on public."PyInstanceObject" for select using (auth.role() = 'authenticated');
