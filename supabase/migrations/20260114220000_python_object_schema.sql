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

-- Method slot tables (CPython: PySequenceMethods*, PyMappingMethods*, PyNumberMethods*)
-- Created here so py_type_object can reference them. Populated in later migrations.
create table public.py_sequence_methods (
  id uuid primary key default gen_random_uuid(),
  sq_length regproc,
  sq_concat regproc,
  sq_repeat regproc
);
create table public.py_mapping_methods (
  id uuid primary key default gen_random_uuid(),
  mp_length regproc
);
create table public.py_number_methods (
  id uuid primary key default gen_random_uuid(),
  nb_absolute regproc,
  nb_add regproc,
  nb_subtract regproc,
  nb_multiply regproc,
  nb_negative regproc,
  nb_positive regproc
);

-- 2. py_type_object (Implements CPython's PyTypeObject: defines types)
--    Type objects themselves are also PyObjects (shared-PK inheritance).
--    This table extends py_object with type-specific metadata.
create table public.py_type_object (
  -- Shared-PK: the type object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  tp_name text not null,
  tp_bases uuid, -- Points to a tuple object containing base types (type checked at runtime)
  tp_dict uuid,  -- Points to a dict object containing type attributes (type checked at runtime)
  -- In CPython, each type object has its own __dict__ for storing type attributes.
  tp_call regproc,       -- CPython ternaryfunc tp_call; NULL = not callable. See 234000.
  tp_hash regproc,       -- CPython hashfunc tp_hash; NULL = unhashable. See 235000.
  tp_richcompare regproc, -- CPython richcmpfunc tp_richcompare; NULL = not implemented. See 234900.
  tp_as_sequence uuid references public.py_sequence_methods(id),
  tp_as_mapping uuid references public.py_mapping_methods(id),
  tp_as_number uuid references public.py_number_methods(id)
);

-- Link PyObject to its type (ob_type is a PyTypeObject, whose identity is its PyObject id)
-- Note: All references point to py_object.id, maintaining CPython's "PyObject*" pointer abstraction.
-- Type checking (ensuring ob_type points to a type object) is done at runtime.
alter table public.py_object
add constraint fk_py_object_type foreign key (ob_type) references public.py_object(id);

-- 3. py_unicode_object (Implements CPython's PyUnicodeObject)
--    String objects in Python. The str_value field stores the actual string data.
create table public.py_unicode_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  str_value text
);

-- 3b. py_bytes_object (Implements CPython's PyBytesObject)
--     Bytes objects in Python. The bytes_value field stores the actual byte data.
--     In CPython, PyBytesObject contains:
--     - ob_sval: C array storing the byte data (char ob_sval[1], flexible array)
--     - ob_shash: Cached hash value for dictionary lookups (Py_hash_t, -1 if not computed)
--     For minimal implementation, we only include the byte data (ob_sval equivalent).
--     Hash caching (ob_shash) is an optimization that can be added later if needed.
--     In PostgreSQL, we use bytea type which can store arbitrary binary data including NULL bytes.
create table public.py_bytes_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  bytes_value bytea not null -- Stores the byte data (equivalent to ob_sval in CPython)
  -- Note: ob_shash (hash cache) is omitted in minimal implementation
);

-- 3c. py_long_object (Implements CPython's PyLongObject)
--     Integer objects in Python. PostgreSQL's numeric type provides arbitrary
--     precision, which matches CPython's PyLongObject behavior for large integers.
create table public.py_long_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  long_value numeric not null -- Stores the integer value (arbitrary precision)
);

-- 3d. py_float_object (Implements CPython's PyFloatObject)
--     Floating-point objects in Python. ob_fval stores the double-precision value.
create table public.py_float_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  ob_fval double precision not null -- Stores the floating-point value
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
--    me_hash caches key's hash (CPython's PyDictKeyEntry.me_hash) for hash-based lookup.
--    Nullable until backfilled; 20260114235000_tp_hash_slot sets NOT NULL after backfill.
create table public.py_dict_entry (
  id uuid primary key default gen_random_uuid(),
  dict_id uuid references public.py_object(id) on delete cascade, -- Dict object (type checked at runtime)
  me_key uuid references public.py_object(id),   -- Key object (must be hashable)
  me_value uuid references public.py_object(id), -- Value object
  me_hash bigint                                 -- Cached hash of me_key (PyDictKeyEntry.me_hash). Set on insert/backfill.
);

-- 8. py_instance_object (Stores instance __dict__ for user-defined class instances)
--    In Python 3, all objects are PyObject (there is no PyInstanceObject struct).
--    However, instances of user-defined classes need to store their __dict__ (instance attributes).
--    This table provides a place to store the instance attribute dictionary.
--    Note: Not all PyObjects have entries here - only instances that have instance attributes.
create table public.py_instance_object (
  -- Shared-PK: the object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  in_dict uuid references public.py_object(id) -- Instance attribute dictionary (__dict__), type checked at runtime
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

-- 9b. py_bool_object (Implements CPython's PyBoolObject: True/False singletons)
--     In CPython, bool is a subtype of int; True and False are the only two instances.
--     Used as return values from tp_richcompare and elsewhere. Bootstrap creates exactly two rows.
create table public.py_bool_object (
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  bool_value boolean not null
);

-- 9c. py_not_implemented_object (Implements CPython's Py_NotImplemented singleton)
--     Returned by tp_richcompare when a type does not implement a comparison.
--     Bootstrap creates exactly one row. Same pattern as py_none_object.
create table public.py_not_implemented_object (
  ob_base uuid primary key references public.py_object(id) on delete cascade
);

-- 9d. py_null_object (CPython 3.11 PUSH_NULL: stack-only placeholder for calls)
--     Used by PUSH_NULL(2) for bound method / method call protocol. Not exposed to Python;
--     distinct from Py_None. Bootstrap creates exactly one row.
create table public.py_null_object (
  ob_base uuid primary key references public.py_object(id) on delete cascade
);

-- 10. py_module_object (Implements CPython's PyModuleObject)
--     Module objects represent Python modules. Each module has a namespace
--     dictionary (md_dict) that stores the module's attributes and a name (md_name).
--     In CPython, PyModuleObject contains md_dict, md_name, md_def, md_state, and md_weaklist.
--     For minimal implementation, we only include md_dict and md_name.
create table public.py_module_object (
  -- Shared-PK: the module object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  
  -- md_dict: Module namespace dictionary (PyObject*)
  -- The dictionary object that implements the module's namespace (__dict__).
  -- This is equivalent to the module's __dict__ attribute in Python.
  -- Must be a dict object. Type checking is done at runtime via ob_type.
  md_dict uuid references public.py_object(id) not null,
  
  -- md_name: Module name (PyObject*)
  -- The name of the module as a string object.
  -- Used for logging and identification purposes.
  -- Must be a string object. Type checking is done at runtime via ob_type.
  md_name uuid references public.py_object(id) not null
);

-- 11. py_slice_object (Implements CPython's PySliceObject)
--     slice(start, stop, step). Used by BUILD_SLICE opcode and BINARY_SUBSCR for slice indexing.
create table public.py_slice_object (
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  ob_start uuid references public.py_object(id),
  ob_stop uuid references public.py_object(id),
  ob_step uuid references public.py_object(id)
);

-- Finalize PyTypeObject relationships
-- Note: All references point to py_object.id, maintaining CPython's "PyObject*" pointer abstraction.
-- Type checking (ensuring tp_bases is a tuple and tp_dict is a dict) is done at runtime.
alter table public.py_type_object
add constraint fk_py_type_objects_tp_bases foreign key (tp_bases) references public.py_object(id),
add constraint fk_py_type_objects_tp_dict foreign key (tp_dict) references public.py_object(id);

-- Enable Row Level Security
-- All CPython object model tables are protected by RLS.
alter table public.py_object enable row level security;
alter table public.py_type_object enable row level security;
alter table public.py_unicode_object enable row level security;
alter table public.py_bytes_object enable row level security;
alter table public.py_long_object enable row level security;
alter table public.py_float_object enable row level security;
alter table public.py_tuple_object enable row level security;
alter table public.py_list_object enable row level security;
alter table public.py_dict_object enable row level security;
alter table public.py_dict_entry enable row level security;
alter table public.py_sequence_methods enable row level security;
alter table public.py_mapping_methods enable row level security;
alter table public.py_number_methods enable row level security;
alter table public.py_instance_object enable row level security;
alter table public.py_none_object enable row level security;
alter table public.py_bool_object enable row level security;
alter table public.py_not_implemented_object enable row level security;
alter table public.py_null_object enable row level security;
alter table public.py_module_object enable row level security;
alter table public.py_slice_object enable row level security;

-- Default Policies (Allow authenticated users to read everything for now)
-- TODO: These policies should be refined as the security model evolves.
create policy "Authenticated users can view py_object" on public.py_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_type_object" on public.py_type_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_unicode_object" on public.py_unicode_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_bytes_object" on public.py_bytes_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_long_object" on public.py_long_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_float_object" on public.py_float_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_tuple_object" on public.py_tuple_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_list_object" on public.py_list_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_dict_object" on public.py_dict_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_dict_entry" on public.py_dict_entry for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_sequence_methods" on public.py_sequence_methods for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_mapping_methods" on public.py_mapping_methods for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_number_methods" on public.py_number_methods for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_instance_object" on public.py_instance_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_none_object" on public.py_none_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_bool_object" on public.py_bool_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_not_implemented_object" on public.py_not_implemented_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_null_object" on public.py_null_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_module_object" on public.py_module_object for select using (auth.role() = 'authenticated');
create policy "Authenticated users can view py_slice_object" on public.py_slice_object for select using (auth.role() = 'authenticated');
