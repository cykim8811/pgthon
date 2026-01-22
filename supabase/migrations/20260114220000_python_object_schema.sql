-- ============================================================================
-- Migration: CPython Object Model Schema
-- Created: 2026-01-14 22:00:00
--
-- Purpose:
--   Defines the database schema that implements CPython's internal object
--   model structures. This migration creates the "type system" - the tables
--   that represent CPython's PyObject, PyTypeObject, PyUnicodeObject, etc.
--
--   This is analogous to defining C structs in a header file. It establishes
--   the structure, but does not create any actual objects. The actual builtin
--   type objects (object, type, str, etc.) are created in the bootstrap
--   migration that follows.
--
-- Key Design Principles:
--   - All object identity is unified through py_object.id (PyObject.id)
--   - Subtype tables use shared-PK inheritance (ob_base = py_object.id)
--   - All references point to py_object.id, maintaining CPython's "PyObject*"
--     pointer abstraction
-- ============================================================================

-- 1. py_object (Implements CPython's PyObject: root header of all objects)
--    Every Python object in Elytra is represented by a row in this table.
--    This is the "base class" that all other object types extend.
create table public.py_object (
  id uuid primary key default gen_random_uuid(),
  ob_type uuid -- Points to a type object (py_type_object)
);

-- 2. py_type_object (Implements CPython's PyTypeObject: defines types)
--    Type objects themselves are also PyObjects (shared-PK inheritance).
--    This table extends py_object with type-specific metadata.
create table public.py_type_object (
  -- Shared-PK: the type object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  tp_name text not null,
  tp_bases uuid, -- Points to a tuple object (py_tuple_object) containing base types
  tp_dict uuid   -- Points to a dict object (py_dict_object) containing type attributes
);

-- Link PyObject to its type (ob_type is a PyTypeObject, whose identity is its PyObject id)
alter table public.py_object
add constraint fk_py_object_type foreign key (ob_type) references public.py_type_object(ob_base);

-- 3. py_unicode_object (Implements CPython's PyUnicodeObject)
--    String objects in Python. The str_value field stores the actual string data.
create table public.py_unicode_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  str_value text
);

-- 4. py_tuple_object (Implements CPython's PyTupleObject)
--    Immutable sequences. ob_item is an array of PyObject IDs.
create table public.py_tuple_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  ob_item uuid[] -- Array of PyObject IDs (elements of the tuple)
);

-- 5. py_list_object (Implements CPython's PyListObject)
--    Mutable sequences. ob_item is an array of PyObject IDs.
create table public.py_list_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  ob_item uuid[] -- Array of PyObject IDs (elements of the list)
);

-- 6. py_dict_object (Implements CPython's PyDictObject)
--    Dictionary/mapping objects. Key-value pairs are stored in py_dict_entry.
create table public.py_dict_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade
);

-- 7. py_dict_entry (Implements CPython's PyDictEntry: entries for dict)
--    Individual key-value pairs within a dictionary.
--    Note: This is not a shared-PK table because entries are not standalone objects.
create table public.py_dict_entry (
  id uuid primary key default gen_random_uuid(),
  dict_id uuid references public.py_dict_object(ob_base) on delete cascade,
  me_key uuid references public.py_object(id),   -- Key object (must be hashable)
  me_value uuid references public.py_object(id) -- Value object
);

-- 8. py_instance_object (Implements CPython's PyInstanceObject: instances)
--    Instances of user-defined classes. in_dict stores instance attributes.
create table public.py_instance_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  in_dict uuid references public.py_dict_object(ob_base) -- Instance attribute dictionary
);

-- 9. py_none_object (Implements CPython's Py_None: the None singleton)
--    None is a special singleton object in Python. In CPython, it's represented
--    as a special PyObject instance, not a PyInstanceObject. This table provides
--    a consistent structure for representing None, following the same pattern
--    as other builtin object types.
create table public.py_none_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade
);

-- Finalize PyTypeObject relationships
-- These constraints ensure tp_bases and tp_dict point to valid tuple/dict objects.
alter table public.py_type_object
add constraint fk_py_type_objects_tp_bases foreign key (tp_bases) references public.py_tuple_object(ob_base),
add constraint fk_py_type_objects_tp_dict foreign key (tp_dict) references public.py_dict_object(ob_base);

-- Enable Row Level Security
-- All CPython object model tables are protected by RLS.
alter table public.py_object enable row level security;
alter table public.py_type_object enable row level security;
alter table public.py_unicode_object enable row level security;
alter table public.py_tuple_object enable row level security;
alter table public.py_list_object enable row level security;
alter table public.py_dict_object enable row level security;
alter table public.py_dict_entry enable row level security;
alter table public.py_instance_object enable row level security;
alter table public.py_none_object enable row level security;

-- Default Policies (Allow authenticated users to read everything for now)
-- TODO: These policies should be refined as the security model evolves.
create policy "Authenticated users can view py_object" on public.py_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_type_object" on public.py_type_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_unicode_object" on public.py_unicode_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_tuple_object" on public.py_tuple_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_list_object" on public.py_list_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_dict_object" on public.py_dict_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_dict_entry" on public.py_dict_entry for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_instance_object" on public.py_instance_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_none_object" on public.py_none_object for select using (auth.role() = 'authenticated');
