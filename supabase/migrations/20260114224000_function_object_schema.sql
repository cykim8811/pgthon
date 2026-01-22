-- ============================================================================
-- Migration: Function, Code, and Frame Object Schema
-- Created: 2026-01-14 22:40:00
--
-- Purpose:
--   Defines the database schema for CPython's PyFunctionObject, PyCodeObject,
--   and PyFrameObject structures. This implements the minimal fields required
--   for function execution:
--
--   PyFunctionObject:
--   - func_code: Code object (the function's body)
--   - func_globals: Global variables dictionary (execution environment)
--   - func_defaults: Default arguments tuple (optional, NULL if none)
--   - func_closure: Closure tuple (optional, NULL if no closure)
--
--   PyCodeObject:
--   - co_code: Bytecode instructions (bytes object)
--   - co_consts: Constants tuple
--   - co_names: Names tuple
--   - co_filename: Source filename (string object)
--   - co_name: Function/code name (string object)
--
--   PyFrameObject:
--   - f_code: Code object being executed
--   - f_globals: Global variables dictionary
--   - f_locals: Local variables dictionary
--   - f_back: Previous frame (NULL if this is the top frame)
--
-- Key Design Principles:
--   - Shared-PK inheritance: all ob_base = py_object.id
--   - All references point to py_object.id, maintaining CPython's "PyObject*"
--     pointer abstraction
--   - Type checking is done at runtime via ob_type
-- ============================================================================

-- py_function_object (Implements CPython's PyFunctionObject)
-- Function objects in Python. Stores the code, globals, and optional
-- default arguments and closure.
create table public.py_function_object (
  -- Shared-PK: the function object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  
  -- func_code: A code object, the __code__ attribute
  -- In CPython, this is PyCodeObject*. References a py_code_object.
  -- Type checking is done at runtime via ob_type.
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
-- pointer abstraction. Type safety is enforced at runtime by checking ob_type,
-- following CPython's design principle.

-- py_code_object (Implements CPython's PyCodeObject)
-- Code objects represent compiled Python bytecode. They contain the instructions
-- and metadata needed to execute a function or module.
create table public.py_code_object (
  -- Shared-PK: the code object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  
  -- co_code: Bytecode instructions (bytes object)
  -- The actual bytecode instructions to execute.
  co_code uuid references public.py_object(id) not null,
  
  -- co_consts: Constants tuple
  -- Tuple of constants used by the code (literals, etc.)
  co_consts uuid references public.py_object(id) not null,
  
  -- co_names: Names tuple
  -- Tuple of names (strings) used by the code (variable names, function names, etc.)
  co_names uuid references public.py_object(id) not null,
  
  -- co_filename: Source filename (string object)
  -- The name of the file from which the code was compiled.
  co_filename uuid references public.py_object(id) not null,
  
  -- co_name: Function/code name (string object)
  -- The name of the function, class, or module this code represents.
  co_name uuid references public.py_object(id) not null
);

-- py_frame_object (Implements CPython's PyFrameObject)
-- Frame objects represent execution frames. Each function call creates a new frame
-- that tracks the execution state (locals, globals, code being executed).
create table public.py_frame_object (
  -- Shared-PK: the frame object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  
  -- f_code: Code object being executed
  -- The code object that this frame is executing.
  f_code uuid references public.py_object(id) not null,
  
  -- f_globals: Global variables dictionary
  -- The global namespace for this frame's execution.
  f_globals uuid references public.py_object(id) not null,
  
  -- f_locals: Local variables dictionary
  -- The local namespace for this frame's execution (local variables, arguments).
  f_locals uuid references public.py_object(id) not null,
  
  -- f_back: Previous frame (NULL if this is the top frame)
  -- The frame that called this one. NULL for the top-level frame.
  f_back uuid references public.py_object(id)
);

-- Enable Row Level Security
alter table public.py_function_object enable row level security;
alter table public.py_code_object enable row level security;
alter table public.py_frame_object enable row level security;

-- Default Policies (Allow authenticated users to read everything for now)
-- TODO: These policies should be refined as the security model evolves.
create policy "Authenticated users can view py_function_object" 
  on public.py_function_object 
  for select 
  using (auth.role() = 'authenticated');

create policy "Authenticated users can view py_code_object" 
  on public.py_code_object 
  for select 
  using (auth.role() = 'authenticated');

create policy "Authenticated users can view py_frame_object" 
  on public.py_frame_object 
  for select 
  using (auth.role() = 'authenticated');
