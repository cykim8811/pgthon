# Elytra

A CPython 3.11 virtual machine implemented entirely in PostgreSQL.

Elytra reconstructs CPython's object model, type system, and bytecode interpreter as PL/pgSQL functions and relational tables. Every Python object is a row. Every type slot is a `regproc`. Every opcode is a stored procedure. The bytecode loop runs inside a single `SELECT py_eval_frame(...)` call.

## Why

CPython's internals — `PyObject`, `PyTypeObject`, the eval loop, the type slot machinery — are elegant but buried under thousands of lines of C, macros, and reference counting. Elytra strips away the C and re-expresses these ideas as a relational schema, making the architecture queryable, inspectable, and surprisingly faithful.

This is not a Python-to-SQL transpiler. It is the VM itself, reimplemented in SQL.

## What Works

**84 opcodes** covering arithmetic, control flow, function calls, closures, exception handling, comprehensions, f-strings, and star-unpacking. **22 bootstrapped types** including `object`, `type`, `str`, `int`, `float`, `list`, `dict`, `tuple`, `bool`, `set`, `bytes`, `function`, `code`, `slice`, and four iterator types. **86 integration tests**, all passing.

You can define classes, instantiate objects, call methods, raise and catch exceptions, build closures, run list comprehensions, and format f-strings — all executing inside PostgreSQL.

```
# This Python code compiles to bytecode that Elytra executes in PostgreSQL:

class Dog:
    def __init__(self, name):
        self.name = name

    def speak(self):
        return self.name + ' says woof'

d = Dog('Rex')
print(d.speak())   # Rex says woof
```

## Architecture

### Object Model

CPython's pointer-based `PyObject*` becomes UUID foreign keys. Every Python object has a row in `py_object` with an `ob_type` reference to its type. Type-specific data lives in extension tables (`py_long_object`, `py_unicode_object`, `py_list_object`, etc.) linked by shared primary key — mirroring CPython's struct inheritance.

```
py_object          py_long_object       py_type_object
┌──────────────┐   ┌──────────────┐     ┌──────────────────┐
│ id (PK)      │   │ ob_base (FK) │──── │ ob_base (FK)     │
│ ob_type (FK) │   │ long_value   │     │ tp_name          │
└──────────────┘   └──────────────┘     │ tp_call (regproc)│
                                        │ tp_hash (regproc)│
                                        │ tp_repr (regproc)│
                                        │ tp_as_sequence   │
                                        │ tp_as_mapping    │
                                        │ tp_as_number     │
                                        │ ...              │
                                        └──────────────────┘
```

### Type Slot Dispatch

Type slots (`tp_call`, `tp_hash`, `tp_richcompare`, `tp_str`, `tp_repr`, `tp_iter`, `nb_add`, `sq_length`, `mp_subscript`, etc.) are stored as `regproc` — PostgreSQL's function-pointer equivalent. Dispatch is a single `EXECUTE format('SELECT %I($1)', slot_func)`.

Each slot follows CPython's exact dispatch chain:
- `PyObject_Str()` → tp_str → fallback to `PyObject_Repr()`
- `PyObject_Repr()` → tp_repr → fallback to `<type object>`
- `PyObject_IsTrue()` → nb_bool → mp_length → sq_length → default true
- `PyObject_GetItem()` → mp_subscript → TypeError
- `PySequence_Contains()` → sq_contains → TypeError

### Bytecode Execution

`py_eval_frame(thread_state_id, frame_id)` is the interpreter loop. It reads 2-byte wordcode instructions from `py_code_object.co_code`, dispatches through a CASE statement to `py_opcode_*` handler functions, manages `f_valuestack` (a UUID array) as the operand stack, and handles CPython 3.11's exception table format for try/except.

### Bootstrap

The bootstrap migration solves the chicken-and-egg problem of `type` being an instance of itself and `object` being the base of `type`. It runs in five phases: create raw `py_object` rows, create `py_type_object` entries, wire `ob_type` references, create type `__dict__` dictionaries, and set `tp_bases` / `tp_dict`. This mirrors CPython's `_Py_ReadyTypes()` initialization.

## Project Structure

```
supabase/migrations/     104 migration files (the source code)
  ├── python_object_schema.sql     PyObject, PyTypeObject, method slot tables
  ├── python_bootstrap.sql         type/object/str/int/... + None/True/False singletons
  ├── function_object_schema.sql   PyCodeObject, PyFrameObject, PyFunctionObject
  ├── type_method_slots.sql        sq_length, mp_length, PyObject_Size
  ├── tp_call_slot.sql             Call protocol + PRECALL/CALL dispatch
  ├── tp_hash_slot.sql             Hash-based dict lookup
  ├── tp_richcompare_slot.sql      Comparison operators + dict key equality
  ├── builtin_print.sql            tp_str/tp_repr handlers + print()
  ├── binary_add.sql               nb_add dispatch (int+int, str+str, float+float)
  ├── ceval_eval_frame.sql         The interpreter loop
  ├── opcode_*.sql                 One file per opcode (50+ files)
  └── py_run.sql                   JSON-in → bytecode execution → JSON-out RPC

supabase/tests/          86 sequential test suites
docs/                    22 design documents
app/                     React Router 7 + Supabase playground UI
```

Migrations are the project's source code, not disposable schema changes. They are edited in place.

## Running

```bash
# Start Supabase (PostgreSQL 17 on port 54322)
pnpm dlx supabase start

# Reset database (applies all migrations)
pnpm dlx supabase db reset

# Run all 86 integration tests
./run_tests.sh

# Full cycle
pnpm dlx supabase db reset && ./run_tests.sh

# Start the playground UI
pnpm dev
```

## Implemented Type Slots

| Category | Slots |
|----------|-------|
| Type-level | `tp_call`, `tp_hash`, `tp_richcompare`, `tp_str`, `tp_repr`, `tp_iter`, `tp_iternext` |
| Numeric | `nb_add`, `nb_subtract`, `nb_multiply`, `nb_absolute`, `nb_negative`, `nb_positive`, `nb_floor_divide`, `nb_true_divide`, `nb_remainder`, `nb_power`, `nb_and`, `nb_or`, `nb_xor`, `nb_lshift`, `nb_rshift`, `nb_invert`, `nb_bool` |
| Sequence | `sq_length`, `sq_concat`, `sq_repeat`, `sq_contains` |
| Mapping | `mp_length`, `mp_subscript`, `mp_ass_subscript` |

## Implemented Opcodes (84)

**Load/Store:** LOAD_CONST, LOAD_NAME, LOAD_FAST, LOAD_GLOBAL, LOAD_ATTR, LOAD_METHOD, STORE_NAME, STORE_FAST, STORE_GLOBAL, STORE_ATTR, DELETE_FAST, DELETE_GLOBAL, DELETE_ATTR

**Arithmetic:** BINARY_ADD, BINARY_SUBTRACT, BINARY_MULTIPLY, BINARY_OP (all inplace + extended ops), UNARY_NEGATIVE, UNARY_POSITIVE, UNARY_NOT, UNARY_INVERT

**Subscript:** BINARY_SUBSCR, STORE_SUBSCR, DELETE_SUBSCR, BUILD_SLICE

**Container:** BUILD_TUPLE, BUILD_LIST, BUILD_MAP, BUILD_SET, BUILD_CONST_KEY_MAP, LIST_TO_TUPLE, UNPACK_SEQUENCE, UNPACK_EX, LIST_EXTEND, SET_UPDATE, DICT_UPDATE, DICT_MERGE, LIST_APPEND, SET_ADD, MAP_ADD

**Comparison:** COMPARE_OP, IS_OP, CONTAINS_OP

**Control flow:** JUMP_FORWARD, JUMP_BACKWARD, POP_JUMP_FORWARD_IF_FALSE/TRUE/NONE/NOT_NONE, POP_JUMP_BACKWARD_IF_FALSE/TRUE/NONE/NOT_NONE, JUMP_IF_FALSE_OR_POP, JUMP_IF_TRUE_OR_POP, FOR_ITER, GET_ITER

**Functions:** PUSH_NULL, PRECALL, CALL, KW_NAMES, CALL_FUNCTION_EX, MAKE_FUNCTION, LOAD_BUILD_CLASS, RETURN_VALUE

**Closures:** MAKE_CELL, LOAD_CLOSURE, LOAD_DEREF, STORE_DEREF, DELETE_DEREF, COPY_FREE_VARS

**Exceptions:** PUSH_EXC_INFO, CHECK_EXC_MATCH, POP_EXCEPT, RAISE_VARARGS, RERAISE

**String:** FORMAT_VALUE, BUILD_STRING

**Other:** POP_TOP, COPY, SWAP, RESUME, NOP, EXTENDED_ARG, CACHE

## Persistent Objects

Every Python object is a row in PostgreSQL. After execution commits, all objects — strings, ints, lists, class instances, functions — persist in the database permanently. Unlike CPython where everything lives in process memory and vanishes on exit, Elytra's objects survive restarts and can be queried with plain SQL. This is not a feature that had to be built; it falls out naturally from the architecture.

## Transactional Execution

Because every Python object is a row and every mutation is a SQL write, Elytra gets **transactional Python execution** for free. You can roll back an entire function call — every object created, every variable assigned, every dict entry inserted — as if it never happened. This is something regular CPython cannot do.

```sql
BEGIN;
SAVEPOINT before_risky;

SELECT py_run('{"source": "some_risky_function()"}');

-- Python error? Roll back all side effects of that call.
ROLLBACK TO before_risky;

-- Everything before the savepoint is untouched.
COMMIT;
```

Python-level exceptions (try/except) work independently of this — they use a manual exception state table, not PostgreSQL's `RAISE EXCEPTION`, so they don't abort the transaction. Transactional rollback is an orthogonal capability you can layer on top.

## Design Principles

**CPython fidelity is the constraint.** Every dispatch chain, every fallback order, every slot convention matches CPython 3.11. Having fewer features than CPython is acceptable. Implementing something differently from CPython is not.

**No hacks.** If a test would pass with a hardcoded shortcut but fail for user-defined types, the shortcut is not allowed. Dispatch goes through slots. Equality goes through `tp_richcompare`. Truth testing goes through `nb_bool` then length slots.

**Migrations are code.** Schema files are edited in place, not overridden by ALTER migrations. Each opcode gets its own file. The migration order is the build order.

## License

MIT
