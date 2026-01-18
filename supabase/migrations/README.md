# Elytra Database Migrations

This directory contains the database migrations for the Elytra project - a PostgreSQL-based Python Virtual Machine implementation.

## Migration Structure

The migrations are organized logically by functionality, following a clear progression from basic infrastructure to complete VM implementation:

### 📋 Core Infrastructure (00-05)

| File | Description |
|------|-------------|
| `20260118210000_core_schema.sql` | User profiles, workspaces, and permissions with RLS |
| `20260118210100_python_object_model.sql` | Python object model tables (types, primitives, collections) |
| `20260118210200_python_bootstrap.sql` | Bootstrap core Python types (object, type, str, int, list, dict, etc.) |
| `20260118210300_python_singletons.sql` | Create None, True, False singleton objects |
| `20260118210400_builtin_functions.sql` | Register built-in functions (len, print, id, type) |
| `20260118210500_builtins_dict.sql` | Create and populate __builtins__ dictionary |

### 🏗️ Type System (06)

| File | Description |
|------|-------------|
| `20260118210600_type_methods.sql` | Register methods for all built-in types (str, int, list, dict, object) |

### ⚙️ VM Core (07-11)

| File | Description |
|------|-------------|
| `20260118210700_vm_object_protocol.sql` | Object attribute access, type lookup, descriptor protocol |
| `20260118210800_vm_helpers.sql` | Helper functions for object creation and manipulation |
| `20260118210900_vm_native_dispatch.sql` | Native function dispatcher and arithmetic operations |
| `20260118211000_vm_call.sql` | Function call mechanism (bound methods, native, bytecode) |
| `20260118211100_vm_interpreter.sql` | **Core bytecode interpreter** (vm_run_frame) |

### 🛠️ Development Tools (12-13)

| File | Description |
|------|-------------|
| `20260118211200_vm_assembler.sql` | Bytecode assembler (text → code objects) |
| `20260118211300_vm_tools.sql` | Object inspector and REPL API |

### 🔐 Security (14)

| File | Description |
|------|-------------|
| `20260118211400_permissions.sql` | RLS policies and function permissions |

## Key Concepts

### Python Object Model in PostgreSQL

Each Python object is represented across multiple tables:
- **py_object**: Base object with type reference
- **py_type_object**: Type definitions with __dict__ and MRO
- **Specialized tables**: py_long_object, py_unicode_object, py_list_object, etc.

### Fixed UUIDs

Core types and singletons use fixed UUIDs for reliability:
```
object:  00000000-0000-4000-a000-000000000001
type:    00000000-0000-4000-a000-000000000002
str:     00000000-0000-4000-a000-000000000003
int:     00000000-0000-4000-a000-000000000004
...
None:    00000000-0000-4000-b000-000000000001
True:    00000000-0000-4000-b000-000000000002
False:   00000000-0000-4000-b000-000000000003
```

### VM Execution Flow

1. **Assemble**: `vm_assemble(source)` → code object
2. **Execute**: `vm_run_frame(code, locals, globals)` → result
3. **Bytecode**: Stack-based execution with opcodes like:
   - LOAD_CONST, LOAD_FAST, STORE_FAST
   - BINARY_ADD, COMPARE_OP
   - POP_JUMP_IF_FALSE, JUMP_ABSOLUTE
   - CALL_FUNCTION, RETURN_VALUE

### Supported Opcodes

The interpreter (`vm_run_frame`) currently supports:
- **Stack Operations**: LOAD_CONST, LOAD_FAST, STORE_FAST, POP_TOP
- **Attributes**: LOAD_ATTR
- **Arithmetic**: BINARY_ADD (via __add__ dispatch)
- **Comparisons**: COMPARE_OP (<, <=, ==, !=, >, >=)
- **Control Flow**: POP_JUMP_IF_FALSE, POP_JUMP_IF_TRUE, JUMP_FORWARD, JUMP_ABSOLUTE
- **Functions**: CALL_FUNCTION, RETURN_VALUE

## Usage

### Running Migrations

```bash
# Start Supabase locally
supabase start

# Migrations are applied automatically in order
# Or manually reset:
supabase db reset
```

### Testing the VM

```sql
-- Execute bytecode via REPL helper
SELECT vm_execute_source('
LOAD_CONST 10
STORE_FAST a
LOAD_CONST 20
STORE_FAST b
LOAD_FAST a
LOAD_FAST b
BINARY_ADD
RETURN_VALUE
');

-- Inspect the result
SELECT vm_inspect_object('<result_uuid>');
```

### Web Interface

The VM can be used via the web REPL at `/repl`, which calls:
```typescript
const { data } = await supabase.rpc("vm_execute_source", {
    p_source: assemblyCode
});
```

## Architecture Highlights

### Object Protocol
- **vm_getattr**: Implements Python's attribute access with descriptor support
- **vm_lookup_in_type**: Searches type hierarchy (simplified MRO)
- **vm_descriptor_get**: Handles function → bound method conversion

### Call Mechanism
- **Bound methods**: Unwrap and prepend `self`
- **Native functions**: Dispatch to `vm_native_dispatch`
- **Bytecode functions**: Create locals, bind args, run frame

### Native Methods
Extensible via:
1. Direct CASE in `vm_native_dispatch`
2. Dynamic dispatch to `vm_native_<name>` functions

## Development

### Adding New Methods

1. Register in `type_methods.sql`:
```sql
(ID_DICT_STR, 'my_method')
```

2. Implement in `vm_native_dispatch.sql`:
```sql
WHEN 'my_method' THEN
    -- implementation
    RETURN result;
```

### Adding New Opcodes

Edit `vm_interpreter.sql`:
```sql
WHEN 'MY_OPCODE' THEN
    -- stack manipulation
    -- operation logic
```

## Migration from Old Structure

The previous 31 migrations were consolidated into 15 logical units:
- ✅ Better organization by concern
- ✅ Clearer dependencies
- ✅ Easier to understand and maintain
- ✅ Same functionality, cleaner structure

Original migrations preserved in `migrations_old/`.

## References

- **CPython Internals**: Type system, descriptor protocol, bytecode format
- **PostgreSQL**: PL/pgSQL, UUID, arrays, JSONB
- **Supabase**: RLS, PostgREST RPC

---

Built with ❤️ for educational exploration of Python internals
