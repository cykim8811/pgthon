-- ============================================================================
-- Migration: Function, Code, and Frame Object Schema
-- Created: 2026-01-14 22:40:00
--
-- Purpose:
--   Defines the database schema for CPython's PyFunctionObject, PyCodeObject,
--   PyFrameObject, PyCellObject, and PyMethodObject structures. This implements
--   the minimal fields required for function execution and method binding:
--
--   PyFunctionObject:
--   - func_code: Code object (the function's body)
--   - func_globals: Global variables dictionary (execution environment)
--   - func_defaults: Default arguments tuple (optional, NULL if none)
--   - func_kwdefaults: Keyword-only default arguments dict (optional, NULL if none)
--   - func_closure: Closure tuple (optional, NULL if no closure)
--
--   PyCodeObject:
--   - co_code: Bytecode instructions (unicode object storing bytecode)
--   - co_consts: Constants tuple
--   - co_names: Names tuple
--   - co_filename: Source filename (string object)
--   - co_name: Function/code name (string object)
--   - co_argcount: Number of positional arguments
--   - co_varnames: Local variable names tuple
--   - co_cellvars: Cell variable names tuple (variables referenced by closures)
--   - co_freevars: Free variable names tuple (variables from outer scopes)
--
--   PyFrameObject:
--   - f_code: Code object being executed
--   - f_globals: Global variables dictionary
--   - f_locals: Local variables dictionary
--   - f_builtins: Builtin symbol table dictionary
--   - f_back: Previous frame (NULL if this is the top frame)
--
--   PyCellObject:
--   - ob_ref: Reference to the cell contents (PyObject*)
--
--   PyMethodObject:
--   - im_func: The callable object implementing the method
--   - im_self: The instance it is bound to, or NULL (for unbound methods)
--   - im_class: The class that asked for the method
--
--   PyCFunction:
--   - m_ml: PyMethodDef structure pointer (contains function metadata)
--     - ml_name: Function name (string)
--     - ml_meth: C function pointer (not storable in DB, handled at runtime)
--     - ml_flags: Function flags (METH_* flags)
--     - ml_doc: Documentation string (optional)
--   - m_self: Self object (PyObject*), NULL for unbound functions
--   - m_module: Module object (PyObject*), NULL if not module-level
--
-- Key Design Principles:
--   - Shared-PK inheritance: all ob_base = py_object.id
--   - All references point to py_object.id, maintaining CPython's "PyObject*"
--     pointer abstraction
--   - Type checking is done at runtime via ob_type
-- ============================================================================

-- py_cell_object (Implements CPython's PyCellObject)
-- Cell objects store references to variables that are shared between nested
-- function scopes (closures). Each cell object holds a single PyObject reference.
create table public.py_cell_object (
  -- Shared-PK: the cell object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  
  -- ob_ref: Reference to the cell contents (PyObject*)
  -- The actual value stored in the cell. Can be NULL if the cell is empty.
  -- Type checking is done at runtime via ob_type of the referenced object.
  ob_ref uuid references public.py_object(id)
);

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
  
  -- func_kwdefaults: NULL or a dict
  -- Keyword-only default argument values. NULL if the function has no keyword-only
  -- default arguments. Must be a dict object when not NULL.
  -- Type checking is done at runtime via ob_type.
  func_kwdefaults uuid references public.py_object(id),
  
  -- func_closure: NULL or a tuple of cell objects
  -- Closure variables for nested functions. NULL if the function has no closure.
  -- Must be a tuple object when not NULL, containing PyCellObject instances.
  -- Type checking is done at runtime via ob_type.
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
  
  -- co_code: Bytecode instructions (unicode object)
  -- The actual bytecode instructions to execute, stored as a unicode object.
  -- In CPython this is bytes, but in Elytra we use unicode for storage.
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
  co_name uuid references public.py_object(id) not null,
  
  -- co_argcount: Number of positional arguments
  -- The total number of positional arguments (including positional-only arguments
  -- and arguments with default values). Required for function call argument matching.
  co_argcount integer not null,
  
  -- co_varnames: Local variable names tuple
  -- Tuple of strings containing the names of local variables (including arguments).
  -- Required for accessing local variables during function execution.
  co_varnames uuid references public.py_object(id) not null,
  
  -- co_cellvars: Cell variable names tuple
  -- Tuple of strings containing the names of variables that are referenced by
  -- nested functions (closures). These variables are stored in cell objects.
  co_cellvars uuid references public.py_object(id) not null,
  
  -- co_freevars: Free variable names tuple
  -- Tuple of strings containing the names of variables from outer scopes that
  -- are referenced by this function. These correspond to the cell objects in
  -- func_closure.
  co_freevars uuid references public.py_object(id) not null
);

-- py_cfunction_object (Implements CPython's PyCFunction)
-- C function objects represent builtin functions implemented in C.
-- These are the functions exposed as builtin_function_or_method in Python.
-- Examples: len, print, abs, max, min, sum, sorted, etc.
create table public.py_cfunction_object (
  -- Shared-PK: the C function object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  
  -- m_ml_name: Function name (from PyMethodDef.ml_name)
  -- The name of the C function as it appears in Python.
  -- Type checking is done at runtime via ob_type.
  m_ml_name uuid references public.py_object(id) not null,
  
  -- m_ml_flags: Function flags (from PyMethodDef.ml_flags)
  -- Flags indicating the calling convention (METH_NOARGS, METH_O, METH_VARARGS, etc.)
  -- Stored as integer to match CPython's ml_flags field.
  m_ml_flags integer not null,
  
  -- m_ml_doc: Documentation string (from PyMethodDef.ml_doc)
  -- The docstring for the function. NULL if no documentation is provided.
  -- Type checking is done at runtime via ob_type (must be string or None).
  m_ml_doc uuid references public.py_object(id),
  
  -- m_self: Self object (PyObject*)
  -- The instance the C function is bound to. NULL for unbound functions.
  -- When not NULL, this is a bound C method; when NULL, it's an unbound C function.
  -- Type checking is done at runtime via ob_type.
  m_self uuid references public.py_object(id),
  
  -- m_module: Module object (PyObject*)
  -- The module object associated with this C function. NULL if not module-level.
  -- Type checking is done at runtime via ob_type (must be module or None).
  m_module uuid references public.py_object(id)
);

-- Note: m_ml->ml_meth (the C function pointer) cannot be stored in the database.
-- The actual C function implementation is handled at runtime by the execution engine.
-- The m_ml_name and m_ml_flags are sufficient to identify and invoke the correct
-- C function implementation.

-- py_method_object (Implements CPython's PyMethodObject)
-- Method objects represent bound or unbound methods. When a function is accessed
-- from an instance, a bound method is created that stores the function and the
-- instance it's bound to. This enables the obj.method() syntax.
create table public.py_method_object (
  -- Shared-PK: the method object's identity is its PyObject id.
  ob_base uuid primary key references public.py_object(id) on delete cascade,
  
  -- im_func: The callable object implementing the method
  -- The function object (PyFunctionObject) that implements the method.
  -- Type checking is done at runtime via ob_type.
  im_func uuid references public.py_object(id) not null,
  
  -- im_self: The instance it is bound to, or NULL
  -- The instance the method is bound to. NULL for unbound methods.
  -- When not NULL, this is a bound method; when NULL, it's an unbound method.
  im_self uuid references public.py_object(id),
  
  -- im_class: The class that asked for the method
  -- The class/type object where the method was defined.
  -- Used to determine the method's context and for unbound method calls.
  im_class uuid references public.py_object(id) not null
);

-- py_frame_object (Implements CPython's PyFrameObject)
-- Frame objects represent execution frames. Each function call creates a new frame
-- that tracks the execution state (locals, globals, code being executed, value stack).
-- This is a stack-based VM, so each frame maintains its own evaluation stack.
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
  
  -- f_builtins: Builtin symbol table dictionary
  -- The builtin namespace containing builtin functions and types (len, print, range, etc.).
  -- Required for accessing builtin functions during execution.
  f_builtins uuid references public.py_object(id) not null,
  
  -- f_back: Previous frame (NULL if this is the top frame)
  -- The frame that called this one. NULL for the top-level frame.
  f_back uuid references public.py_object(id),
  
  -- f_valuestack: Evaluation stack (array of PyObject IDs)
  -- The stack where intermediate values are pushed/popped during bytecode execution.
  -- This is the core of the stack-based VM. Operations push operands onto this stack
  -- and pop results from it.
  f_valuestack uuid[] default array[]::uuid[],
  
  -- f_lasti: Last instruction executed
  -- Index of the last bytecode instruction that was executed. Used to track
  -- execution progress and for exception handling. -1 means no instruction executed yet.
  f_lasti integer default -1
);

-- Enable Row Level Security
alter table public.py_cell_object enable row level security;
alter table public.py_function_object enable row level security;
alter table public.py_code_object enable row level security;
alter table public.py_frame_object enable row level security;
alter table public.py_method_object enable row level security;
alter table public.py_cfunction_object enable row level security;

-- Default Policies (Allow authenticated users to read everything for now)
-- TODO: These policies should be refined as the security model evolves.
create policy "Authenticated users can view py_cell_object" 
  on public.py_cell_object 
  for select 
  using (auth.role() = 'authenticated');

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

create policy "Authenticated users can view py_method_object" 
  on public.py_method_object 
  for select 
  using (auth.role() = 'authenticated');

create policy "Authenticated users can view py_cfunction_object" 
  on public.py_cfunction_object 
  for select 
  using (auth.role() = 'authenticated');
