-- Migration to add CPython-style internal object tables
-- Created at: 2026-01-14 22:00:00

-- 1. PyObject (The root of all objects)
create table public."PyObject" (
  id uuid primary key default gen_random_uuid(),
  ob_type uuid -- To be linked to PyTypeObject
);

-- 2. PyTypeObject (Defines types)
create table public."PyTypeObject" (
  -- Shared-PK: the type object's identity is its PyObject id.
  ob_base uuid primary key references public."PyObject"(id) on delete cascade,
  tp_name text not null,
  tp_bases uuid, -- To be linked to PyTupleObject
  tp_dict uuid   -- To be linked to PyDictObject
);

-- Link PyObject to its type (ob_type is a PyTypeObject, whose identity is its PyObject id)
alter table public."PyObject"
add constraint fk_py_object_type foreign key (ob_type) references public."PyTypeObject"(ob_base);

-- 3. PyUnicodeObject
create table public."PyUnicodeObject" (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public."PyObject"(id) on delete cascade,
  str_value text
);

-- 4. PyTupleObject
create table public."PyTupleObject" (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public."PyObject"(id) on delete cascade,
  ob_item uuid[] -- Array of PyObject IDs
);

-- 5. PyListObject
create table public."PyListObject" (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public."PyObject"(id) on delete cascade,
  ob_item uuid[] -- Array of PyObject IDs
);

-- 6. PyDictObject
create table public."PyDictObject" (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public."PyObject"(id) on delete cascade
);

-- 7. PyDictEntry (Entries for PyDictObject)
create table public."PyDictEntry" (
  id uuid primary key default gen_random_uuid(),
  dict_id uuid references public."PyDictObject"(ob_base) on delete cascade,
  me_key uuid references public."PyObject"(id),
  me_value uuid references public."PyObject"(id)
);

-- 8. PyInstanceObject (Class instances)
create table public."PyInstanceObject" (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public."PyObject"(id) on delete cascade,
  in_dict uuid references public."PyDictObject"(ob_base)
);

-- Finalize PyTypeObject relationships
alter table public."PyTypeObject"
add constraint fk_py_type_objects_tp_bases foreign key (tp_bases) references public."PyTupleObject"(ob_base),
add constraint fk_py_type_objects_tp_dict foreign key (tp_dict) references public."PyDictObject"(ob_base);

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
