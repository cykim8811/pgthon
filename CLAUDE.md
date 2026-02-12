# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pgthon implements CPython's object model and bytecode VM on PostgreSQL using PL/pgSQL. The goal is to faithfully reconstruct CPython 3.11's internal structures (objects, types, bytecode execution) as a relational database schema. The project also has a React Router frontend for a web interface, but the core work is in the SQL layer.

## Commands

```bash
# Database reset (runs all migrations fresh) — required before testing
pnpm dlx supabase db reset

# Run all integration tests (requires Supabase running)
./run_tests.sh

# Full test cycle (reset + test)
pnpm dlx supabase db reset && ./run_tests.sh

# Start Supabase locally (PostgreSQL 17 on port 54322, API on 54321)
pnpm dlx supabase start

# Frontend dev server
pnpm dev

# TypeScript type checking
pnpm typecheck

# Production build
pnpm build
```

Tests run via `docker exec` against the `supabase_db_pgthon` container. Each test is a standalone SQL file executed with `psql -v ON_ERROR_STOP=1`. Tests are in `supabase/tests/` and run sequentially in numbered order by `run_tests.sh`. There is no way to run a single test in isolation without the database being in the correct state (migrations applied); to run one test manually: `docker exec -i supabase_db_pgthon psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/<test_file>.sql`.

## Architecture

### Database Layer (the core of the project)

**Migrations** (`supabase/migrations/`, 72 files): These are the project's source code, not disposable schema changes. Edit existing migration files rather than creating new override migrations. The migration order matters — later files depend on earlier ones.

Key migration groups:
- **Object model**: `python_object_schema.sql` defines `py_object` and type-specific tables (`py_unicode_object`, `py_long_object`, `py_list_object`, `py_dict_object`, `py_tuple_object`, `py_float_object`, `py_bytes_object`, etc.)
- **Bootstrap**: `python_bootstrap.sql` creates singleton type objects (`type`, `object`, `str`, `int`, `list`, `dict`, `tuple`, `NoneType`, `bool`) and singletons (`None`, `True`, `False`)
- **Code/Frame/Function**: `function_object_schema.sql` defines `py_code_object`, `py_frame_object`, `py_function_object`
- **Exception system**: `exception_schema.sql`, `exception_helpers.sql`, `exception_setters.sql`, `exception_table_parsing.sql`
- **Type slots**: Separate files for `tp_call`, `tp_hash`, `tp_richcompare`, `nb_add/subtract/multiply`, `nb_absolute`, `sq_length/concat/repeat`, `mp_length`
- **Opcode handlers**: One file per opcode, named `*_opcode_<name>.sql`, each containing a `py_opcode_*` function
- **Eval frame**: `ceval_eval_frame.sql` — the main interpreter loop (`py_eval_frame`), dispatches opcodes via a CASE statement

**Object model mapping**: CPython's pointer-based `PyObject*` becomes UUID foreign keys. `ob_type` references the type object. `py_object` is the base table; type-specific tables extend it (e.g., `py_long_object` has `int_value NUMERIC`).

**Bytecode execution**: `py_eval_frame(frame_id)` reads 2-byte wordcode instructions from `py_code_object.co_code`, dispatches to `py_opcode_*` handler functions, manages `f_valuestack` (UUID array) as the operand stack, and handles exception table lookup on errors.

### Frontend (`app/`)

React Router 7 + Supabase + Tailwind CSS. Routes in `app/routes/`, components in `app/components/`. Path alias `~/*` maps to `./app/*`. The frontend is a thin web interface, not the focus of development.

### Design Documents (`docs/`)

22 design documents covering opcode roadmap, call protocol, bytecode encoding, exception handling, dict lookup, attribute access, and more. Read the relevant design doc before implementing any feature.

## Development Rules

**CPython fidelity is paramount.** Every implementation must match CPython 3.11's actual behavior. No temporary hacks, no test-only workarounds, no hardcoded shortcuts.

**On test failure**: If the first test run fails, stop and report the failure. Do not modify code to fix it without explicit user instruction. For simple bugs (typos, obvious mistakes), fix minimally and re-test. For structural issues, report the root cause analysis and stop.

**Migration file conventions**:
- Edit existing migration files when modifying schemas — do not create new migrations that ALTER existing tables
- New opcode handlers get one new migration file each, named `<timestamp>_opcode_<name>.sql`
- Add the opcode's CASE branch to `ceval_eval_frame.sql`

**Opcode implementation pattern**: Each opcode is a PL/pgSQL function `py_opcode_<NAME>(frame_id UUID) RETURNS void`. It reads/writes `f_valuestack`, `f_locals`, `f_globals` on the frame object. Refer to `docs/OPCODE_3_11_ROADMAP.md` for implementation status and priority.
