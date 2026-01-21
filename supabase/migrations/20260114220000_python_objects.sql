-- Migration to add CPython-style internal object tables
-- Created at: 2026-01-14 22:00:00

-- 1. py_object (Implements CPython's PyObject: root header of all objects)
create table public.py_object (
  id uuid primary key default gen_random_uuid(),
  ob_type uuid -- Points to a type object (py_type_object)
);

-- 2. py_type_object (Implements CPython's PyTypeObject: defines types)
create table public.py_type_object (
  -- Shared-PK: the type object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  tp_name text not null,
  tp_bases uuid, -- Points to a tuple object (py_tuple_object)
  tp_dict uuid   -- Points to a dict object (py_dict_object)
);

-- Link PyObject to its type (ob_type is a PyTypeObject, whose identity is its PyObject id)
alter table public.py_object
add constraint fk_py_object_type foreign key (ob_type) references public.py_type_object(ob_base);

-- 3. py_unicode_object (Implements CPython's PyUnicodeObject)
create table public.py_unicode_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  str_value text
);

-- 4. py_tuple_object (Implements CPython's PyTupleObject)
create table public.py_tuple_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  ob_item uuid[] -- Array of PyObject IDs
);

-- 5. py_list_object (Implements CPython's PyListObject)
create table public.py_list_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  ob_item uuid[] -- Array of PyObject IDs
);

-- 6. py_dict_object (Implements CPython's PyDictObject)
create table public.py_dict_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade
);

-- 7. py_dict_entry (Implements CPython's PyDictEntry: entries for dict)
create table public.py_dict_entry (
  id uuid primary key default gen_random_uuid(),
  dict_id uuid references public.py_dict_object(ob_base) on delete cascade,
  me_key uuid references public.py_object(id),
  me_value uuid references public.py_object(id)
);

-- 8. py_instance_object (Implements CPython's PyInstanceObject: instances)
create table public.py_instance_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  in_dict uuid references public.py_dict_object(ob_base)
);

-- Finalize PyTypeObject relationships
alter table public.py_type_object
add constraint fk_py_type_objects_tp_bases foreign key (tp_bases) references public.py_tuple_object(ob_base),
add constraint fk_py_type_objects_tp_dict foreign key (tp_dict) references public.py_dict_object(ob_base);

-- Enable Row Level Security
alter table public.py_object enable row level security;
alter table public.py_type_object enable row level security;
alter table public.py_unicode_object enable row level security;
alter table public.py_tuple_object enable row level security;
alter table public.py_list_object enable row level security;
alter table public.py_dict_object enable row level security;
alter table public.py_dict_entry enable row level security;
alter table public.py_instance_object enable row level security;

-- Default Policies (Allow authenticated users to read everything for now)
create policy "Authenticated users can view py_object" on public.py_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_type_object" on public.py_type_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_unicode_object" on public.py_unicode_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_tuple_object" on public.py_tuple_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_list_object" on public.py_list_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_dict_object" on public.py_dict_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_dict_entry" on public.py_dict_entry for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_instance_object" on public.py_instance_object for select using (auth.role() = 'authenticated');
