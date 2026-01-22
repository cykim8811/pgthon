-- ============================================================================
-- Migration: Function Object Schema
-- Created: 2026-01-14 22:40:00
--
-- Purpose:
--   Defines the database schema for CPython's PyFunctionObject structure.
--   This implements the minimal fields required for function objects:
--   - func_code: Code object (the function's body)
--   - func_globals: Global variables dictionary (execution environment)
--   - func_defaults: Default arguments tuple (optional, NULL if none)
--   - func_closure: Closure tuple (optional, NULL if no closure)
--
--   Note: func_code currently references PyObject. When PyCodeObject is
--   implemented, this can be refined to reference py_code_object specifically.
--   For now, this maintains CPython's structure while allowing future extension.
--
-- Key Design Principles:
--   - Shared-PK inheritance: py_function_object.ob_base = py_object.id
--   - All references point to py_object.id, maintaining CPython's "PyObject*"
--     pointer abstraction
--   - NULL values for func_defaults and func_closure are allowed (many
--     functions don't have default args or closures)
-- ============================================================================

-- py_function_object (Implements CPython's PyFunctionObject)
-- Function objects in Python. Stores the code, globals, and optional
-- default arguments and closure.
create table public.py_function_object (
  -- Shared-PK: the function object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  
  -- func_code: A code object, the __code__ attribute
  -- In CPython, this is PyCodeObject*. For now, we reference PyObject
  -- and can refine to py_code_object when it's implemented.
  func_code uuid references public.py_object(id) not null,
  
  -- func_globals: A dictionary (other mappings won't do)
  -- This is the global namespace where the function was defined.
  -- Must be a dict object. Type checking is done at runtime via ob_type.
  func_globals uuid references public.py_object(id) not null,
  
  -- func_defaults: NULL or a tuple
  -- Default argument values. NULL if the function has no default arguments.
  -- Must be a tuple object when not NULL. Type checking is done at runtime via ob_type.
  func_defaults uuid references public.py_object(id),
  
  -- func_closure: NULL or a tuple of cell objects
  -- Closure variables for nested functions. NULL if the function has no closure.
  -- Must be a tuple object when not NULL. Type checking is done at runtime via ob_type.
  -- Note: Cell objects (PyCellObject) are not yet implemented, so this
  -- currently references a tuple of PyObjects. This can be refined later.
  func_closure uuid references public.py_object(id)
);

-- Note: All references point to py_object.id, maintaining CPython's "PyObject*"
-- pointer abstraction. Type safety (ensuring func_globals is a dict, func_defaults
-- and func_closure are tuples) is enforced at runtime by checking ob_type,
-- following CPython's design principle.

-- Enable Row Level Security
alter table public.py_function_object enable row level security;

-- Default Policy (Allow authenticated users to read everything for now)
-- TODO: These policies should be refined as the security model evolves.
create policy "Authenticated users can view py_function_object" 
  on public.py_function_object 
  for select 
  using (auth.role() = 'authenticated');
