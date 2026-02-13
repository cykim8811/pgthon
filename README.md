# Pgthon

Python on PostgreSQL. A CPython 3.11 bytecode VM implemented entirely in PL/pgSQL.

Pgthon faithfully reconstructs CPython's object model, type system, and bytecode interpreter as a relational database schema. Python code compiles on the host, then executes inside PostgreSQL.

## Quick Start

```bash
# Prerequisites: Docker, Python 3.11

# Start database, load schema, run tests
make all

# Run Python on PostgreSQL
python3 pgthon.py "1 + 2"         # 3
python3 pgthon.py "len([1,2,3])"  # 3
python3 pgthon.py "abs(-42)"      # 42

# Interactive REPL
python3 pgthon.py
>>> x = 10
>>> x + 5
15
```

## Commands

| Command | Description |
|---------|-------------|
| `make db` | Start PostgreSQL container |
| `make schema` | Clean reset + load all SQL files |
| `make test` | Run all tests |
| `make all` | Full cycle (schema + test) |
| `make run CODE="1+2"` | Run Python expression |
| `make repl` | Interactive REPL |
| `make down` | Stop containers |

## How It Works

1. **`pgthon.py`** compiles Python source to CPython 3.11 bytecode using `compile()`
2. The bytecode and metadata are serialized to JSON
3. **`py_run()`** in PostgreSQL creates the code object, frame, and globals dict
4. **`py_eval_frame()`** executes the bytecode — a PL/pgSQL loop dispatching 80+ opcodes
5. Results are serialized back to JSON and displayed

## Architecture

```
Python source
    |
    v
compile()          # Host-side: CPython 3.11 compiler
    |
    v
JSON payload       # bytecode (hex), consts, names, varnames, ...
    |
    v
py_run(JSONB)      # PostgreSQL: creates objects, frame, executes
    |
    v
py_eval_frame()    # PL/pgSQL: reads bytecode, dispatches opcodes
    |
    v
JSON result        # {result, globals, error}
```

### Database Schema

CPython's pointer-based `PyObject*` becomes UUID foreign keys. `py_object` is the base table; type-specific tables extend it:

- `py_long_object` (int), `py_float_object`, `py_unicode_object` (str)
- `py_list_object`, `py_tuple_object`, `py_dict_object`, `py_set_object`
- `py_code_object`, `py_function_object`, `py_frame_object`
- `py_type_object` with slots: `tp_call`, `tp_hash`, `tp_richcompare`, `nb_add`, ...

### SQL Source (`sql/`, 103 files)

| Group | Files | Description |
|-------|-------|-------------|
| Object model | `000-001` | `py_object`, type tables, bootstrap |
| Type slots | `009-026` | `tp_call`, `tp_hash`, `nb_add`, `sq_length`, ... |
| Opcodes | `027-100` | One file per opcode handler |
| Eval frame | `101` | Main interpreter loop |
| py_run | `102` | RPC entry point |

## What Works

- Arithmetic: `+`, `-`, `*`, `/`, `//`, `%`, `**`, bitwise ops
- Comparison: `<`, `>`, `==`, `!=`, `<=`, `>=`, `is`, `in`
- Variables: local, global, closures, del
- Control flow: `if/elif/else`, `for`, `while`, `try/except`
- Data structures: `list`, `tuple`, `dict`, `set`, `slice`
- Functions: `def`, closures, `*args`, `**kwargs`
- Classes: `class`, `__init__`, inheritance, bound methods
- Builtins: `len`, `abs`, `print`, `range`, `isinstance`, `hasattr`, `getattr`, `setattr`, `id`
- Type constructors: `int()`, `str()`, `float()`, `bool()`, `list()`, `tuple()`, `dict()`
- Comprehensions, f-strings, star unpacking

## Requirements

- Docker
- Python 3.11 (exact version required — bytecode format must match)
