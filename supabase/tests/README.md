# Elytra Test Suite

Comprehensive test suite for the Elytra Python VM implementation in PostgreSQL.

## Test Structure

Tests are organized to mirror the migration structure, with each test file testing features from corresponding migrations:

| Test File | Migrations Tested | Description |
|-----------|-------------------|-------------|
| `00_setup.sql` | - | Test helper functions (assertions) |
| `01_object_model.sql` | 01-03 | Object model, type system, singletons |
| `02_builtins_and_methods.sql` | 04-06 | Built-in functions, __builtins__, type methods |
| `03_vm_helpers.sql` | 07-08 | VM object creation and helper functions |
| `04_arithmetic.sql` | 09 | Arithmetic operations and native dispatch |
| `05_bytecode_execution.sql` | 11-12 | Bytecode assembler and interpreter |
| `06_object_protocol.sql` | 07, 10-11 | Attribute access, method binding, getattr |
| `07_integration.sql` | All | End-to-end integration tests |

## Running Tests

### Run All Tests

```bash
./test.sh
```

###Run Individual Test

```bash
# Direct psql execution
docker exec -i supabase_db_elytra psql -U postgres -d postgres < supabase/tests/01_object_model.sql

# Or via supabase CLI
supabase db reset
psql -U postgres -h 127.0.0.1 -p 54322 -d postgres < supabase/tests/01_object_model.sql
```

## Test Coverage

### 1. Object Model Tests (`01_object_model.sql`)

- ✅ Core types exist (13 types expected)
- ✅ Type names correct (object, type, str, int, list, dict, etc.)
- ✅ Singletons exist (None, True, False)
- ✅ True has value 1, False has value 0
- ✅ Type hierarchy (bool inherits from int)

### 2. Built-ins and Methods Tests (`02_builtins_and_methods.sql`)

- ✅ __builtins__ dictionary exists
- ✅ Core types registered in __builtins__ (int, str, list, dict, etc.)
- ✅ Type methods registered (str.upper, int.__add__, list.append, etc.)
- ✅ Magic methods exist (__add__, __sub__, etc.)

### 3. VM Helpers Tests (`03_vm_helpers.sql`)

- ✅ `vm_create_int()` creates integer objects
- ✅ `vm_create_str()` creates string objects
- ✅ `vm_get_none()` returns None singleton
- ✅ `vm_assembler_get_or_create_const()` parses int/str
- ✅ `vm_is_true()` truth testing (True, False, None, 0, non-zero)
- ✅ `vm_compare()` comparison operations (<, <=, ==, !=, >, >=)

### 4. Arithmetic Tests (`04_arithmetic.sql`)

- ✅ Integer addition (10 + 20 = 30)
- ✅ String concatenation ("Hello" + " World")
- ✅ Native dispatch for __add__, __sub__, __mul__, __floordiv__, __mod__
- ✅ Arithmetic with various values

### 5. Bytecode Execution Tests (`05_bytecode_execution.sql`)

- ✅ Simple constant return (`LOAD_CONST`, `RETURN_VALUE`)
- ✅ Variables (`LOAD_FAST`, `STORE_FAST`)
- ✅ Binary addition (`BINARY_ADD`)
- ✅ Chained operations
- ✅ Comparisons (`COMPARE_OP`)
- ✅ Conditional jumps (`POP_JUMP_IF_FALSE`)
- ✅ Complex expressions with multiple variables

### 6. Object Protocol Tests (`06_object_protocol.sql`)

- ✅ `vm_getattr()` attribute lookup
- ✅ Bound method creation
- ✅ `vm_lookup_in_type()` type dictionary search
- ✅ Descriptor protocol (function → bound method)
- ✅ Method calls via bound methods

### 7. Integration Tests (`07_integration.sql`)

- ✅ Complete multi-step programs
- ✅ Conditional logic (if/else simulation)
- ✅ String operations in VM
- ✅ Object inspector JSON output
- ✅ REPL API (`vm_execute_source`)
- ✅ Multi-variable calculations

## Test Helpers

### Assertion Functions

```sql
-- Boolean assertion
PERFORM public.test_assert(condition, 'Test description');

-- Integer equality
PERFORM public.test_assert_eq_int(actual, expected, 'Test description');

-- String equality
PERFORM public.test_assert_eq_str(actual, expected, 'Test description');

-- Not null check
PERFORM public.test_assert_not_null(value, 'Test description');
```

### Output

- **PASS**: Raises NOTICE with "TEST PASSED: ..."
- **FAIL**: Raises EXCEPTION with "TEST FAILED: ..." (stops execution)

## Supported Opcodes (Tested)

| Opcode | Test Coverage | Description |
|--------|--------------|-------------|
| `LOAD_CONST` | ✅ | Load constant onto stack |
| `LOAD_FAST` | ✅ | Load local variable |
| `STORE_FAST` | ✅ | Store to local variable |
| `BINARY_ADD` | ✅ | Add TOS and TOS1 |
| `COMPARE_OP` | ✅ | Compare TOS and TOS1 |
| `POP_JUMP_IF_FALSE` | ✅ | Conditional jump if false |
| `POP_JUMP_IF_TRUE` | ⚠️ | Conditional jump if true (partial) |
| `JUMP_ABSOLUTE` | ⚠️ | Absolute jump (indirect) |
| `RETURN_VALUE` | ✅ | Return TOS |
| `LOAD_ATTR` | ⚠️ | Load attribute (via unit tests) |
| `CALL_FUNCTION` | ⚠️ | Call function (via unit tests) |

## Adding New Tests

1. **Create test file**: `supabase/tests/NN_test_name.sql`
2. **Use DO block**:
   ```sql
   DO $$
   DECLARE
       -- variables
   BEGIN
       RAISE NOTICE E'\n=== Test Section Name ===';
       
       -- test code
       PERFORM public.test_assert(...);
       
       RAISE NOTICE E'\n=== All Tests Passed! ===\n';
   END $$;
   ```
3. **Update test.sh**: Add to run sequence
4. **Document**: Update this README

## Test Running Sequence

Tests run in order via `test.sh`:

1. **Setup** (00) - Create helper functions
2. **Object Model** (01) - Verify core types
3. **Built-ins** (02) - Verify functions and methods
4. **VM Helpers** (03) - Test creation/comparison
5. **Arithmetic** (04) - Test operations
6. **Bytecode** (05) - Test interpreter
7. **Protocol** (06) - Test attribute access
8. **Integration** (07) - End-to-end tests

## Expected Results

All tests should pass with output like:

```
===========================================
Running Elytra VM Test Suite
===========================================
✅ PASS: supabase/tests/00_setup.sql
✅ PASS: supabase/tests/01_object_model.sql
   TEST PASSED: Expected at least 13 types, found 13
   TEST PASSED: object type name
   ...
✅ PASS: supabase/tests/02_builtins_and_methods.sql
✅ PASS: supabase/tests/03_vm_helpers.sql
✅ PASS: supabase/tests/04_arithmetic.sql
✅ PASS: supabase/tests/05_bytecode_execution.sql
✅ PASS: supabase/tests/06_object_protocol.sql
✅ PASS: supabase/tests/07_integration.sql
===========================================
🎉 All Tests Passed!
===========================================
```

## Troubleshooting

### Test Fails

1. Check migration order - tests depend on specific migrations
2. Reset database: `supabase db reset`
3. Check for SQL syntax errors in test file
4. Review test output for specific failure

### Docker Connection Issues

```bash
# Check Docker is running
docker ps | grep supabase

# Restart Supabase
supabase stop
supabase start
```

### Missing Functions

If tests fail with "function does not exist":
1. Ensure all migrations have run: `supabase db reset`
2. Check migration files for SQL errors
3. Verify function names match exactly

## Migration Cleanup

Original tests preserved in `tests_old/`:
- `tests_old/00_setup/01_helpers.sql`
- `tests_old/01_objects/test_basic_types.sql`
- `tests_old/02_ops/test_arithmetic_vars.sql`
- `tests_old/03_control_flow/test_jump.sql`
- `tests_old/05_collections/test_list_manual.sql`

---

Built with ❤️ for comprehensive VM testing
