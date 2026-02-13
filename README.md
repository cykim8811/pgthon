# Pgthon

A CPython 3.11 bytecode VM implemented entirely in PL/pgSQL.

Pgthon reconstructs CPython's object model, type system, and bytecode interpreter as a relational database schema. Every object is a row. Every type slot is a stored procedure. The interpreter loop is a PL/pgSQL function.

## Quick Start

```bash
# Prerequisites: Docker, Python 3.11

make all        # Start DB, load schema, run tests
make repl       # Interactive REPL
```

```
>>> 1 + 2
3
>>> x = [1, 2, 3]
>>> len(x)
3
>>> abs(-42)
42
```

## Commands

| Command | Description |
|---------|-------------|
| `make db` | Start PostgreSQL container |
| `make schema` | Clean reset + load all SQL |
| `make test` | Run all 87 test suites |
| `make all` | Full cycle (schema + test) |
| `make repl` | Interactive REPL |
| `make down` | Stop containers |

## Architecture

The core is 103 SQL files implementing CPython's internals in PostgreSQL:

**Object Model** — CPython's `PyObject*` becomes UUID foreign keys. `py_object` is the base table; type-specific tables extend it (`py_long_object`, `py_unicode_object`, `py_list_object`, `py_dict_object`, ...).

**Type System** — `py_type_object` implements CPython's type slots as `regproc` references: `tp_call`, `tp_hash`, `tp_richcompare`, `tp_iter`, `nb_add`, `sq_length`, `mp_subscript`, and more.

**Bytecode VM** — `py_eval_frame()` is the interpreter loop. It reads 2-byte wordcode instructions from `py_code_object.co_code`, dispatches to `py_opcode_*` handler functions, and manages the value stack as a UUID array.

**Bootstrap** — Type objects (`type`, `object`, `int`, `str`, `list`, `dict`, ...) and singletons (`None`, `True`, `False`) are bootstrapped with fixed UUIDs, mirroring CPython's initialization.

### SQL Source Layout

| Files | Description |
|-------|-------------|
| `000-001` | Object schema, bootstrap |
| `002-008` | Runtime, functions, exceptions, builtins |
| `009-026` | Type slots (`tp_call`, `tp_hash`, `nb_add`, ...) |
| `027-094` | Opcode handlers (one per file) |
| `095-100` | Exception dispatch opcodes |
| `101` | `py_eval_frame` — the interpreter loop |
| `102` | `py_run` — JSON RPC entry point |

## What's Implemented

- **Types**: `int`, `float`, `str`, `bytes`, `bool`, `list`, `tuple`, `dict`, `set`, `NoneType`, `function`, `code`, `slice`, `range`
- **Arithmetic**: `+`, `-`, `*`, `/`, `//`, `%`, `**`, `&`, `|`, `^`, `<<`, `>>`, `~`, unary `-`/`+`
- **Comparison**: `<`, `>`, `==`, `!=`, `<=`, `>=`, `is`, `is not`, `in`, `not in`
- **Control flow**: `if`/`elif`/`else`, `for`, `while`, `try`/`except`, `raise`
- **Functions**: `def`, closures, `*args`, `**kwargs`, default arguments
- **Classes**: `class`, `__init__`, inheritance, bound methods, `__build_class__`
- **Builtins**: `len`, `abs`, `print`, `range`, `isinstance`, `hasattr`, `getattr`, `setattr`, `id`
- **80+ opcodes**: `LOAD_CONST`, `BINARY_OP`, `CALL`, `MAKE_FUNCTION`, `FOR_ITER`, `BUILD_MAP`, comprehensions, f-strings, star unpacking, ...

## Testing

`pgthon.py` compiles Python source to CPython 3.11 bytecode and sends it to the VM via `py_run()`. This is a testing tool — the project itself is the SQL.

```bash
python3 pgthon.py "1 + 2"    # One-shot
python3 pgthon.py             # REPL
```

## Requirements

- Docker
- Python 3.11 (for `pgthon.py` — must match the bytecode format the VM expects)
