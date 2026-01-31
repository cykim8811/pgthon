#!/bin/bash

# =====================================================
# Elytra Test Suite Runner
# Description: Run all tests in sequence with Docker
# =====================================================

# Database Connection Info
DB_HOST="127.0.0.1"
DB_PORT="54322"
DB_USER="postgres"
DB_NAME="postgres"
DB_CONTAINER="supabase_db_elytra"

export PGPASSWORD="postgres"

echo "==========================================="
echo "🧪 Elytra Test Suite"
echo "==========================================="
echo ""

# Function to run a single test file
run_test() {
    local file=$1
    local test_name=$(basename "$file" .sql)
    
    if [ ! -f "$file" ]; then
        echo "⚠️  SKIP: $test_name (file not found)"
        return 0
    fi
    
    # Use docker exec to run psql inside the container
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$file" > /tmp/test_out.log 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ PASS: $test_name"
        # Show test passed notices (filter out verbose output, show key messages)
        if grep -q "✓" /tmp/test_out.log; then
            grep "✓" /tmp/test_out.log | head -5 | sed 's/^/   /'
            local count=$(grep -c "✓" /tmp/test_out.log)
            if [ "$count" -gt 5 ]; then
                echo "   ... and $((count - 5)) more checks"
            fi
        fi
        # Show summary if available
        if grep -q "Test Summary" /tmp/test_out.log; then
            grep -A 3 "Test Summary" /tmp/test_out.log | sed 's/^/   /'
        fi
        return 0
    else
        echo "❌ FAIL: $test_name"
        echo ""
        cat /tmp/test_out.log
        echo ""
        return 1
    fi
}

# Check if Docker container is running
if ! docker ps | grep -q "$DB_CONTAINER"; then
    echo "❌ Error: Supabase database container not running"
    echo "   Run: supabase start"
    exit 1
fi

echo "📦 Running tests against: $DB_CONTAINER"
echo ""

# ===================================================
# Run tests in order
# ===================================================

# 0. Bootstrap Validation (most fundamental test)
echo "=== Phase 0: Bootstrap Validation ==="
if run_test "supabase/tests/00_bootstrap_validation.sql"; then
    echo ""
else
    echo ""
    echo "❌ Bootstrap validation failed. Cannot continue."
    exit 1
fi

# 1. Function, Code, and Frame Schema Validation
echo "=== Phase 1: Function, Code, and Frame Schema ==="
if run_test "supabase/tests/01_function_code_frame_schema.sql"; then
    echo ""
else
    echo ""
    echo "❌ Schema validation failed. Cannot continue."
    exit 1
fi

# 2. Method Object Schema Validation
echo "=== Phase 2: Method Object Schema ==="
if run_test "supabase/tests/02_method_object_schema.sql"; then
    echo ""
else
    echo ""
    echo "❌ Method object schema validation failed. Cannot continue."
    exit 1
fi

# 3. Builtin Functions Integration Test
echo "=== Phase 3: Builtin Functions Integration ==="
if run_test "supabase/tests/03_builtin_functions_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ Builtin functions integration test failed. Cannot continue."
    exit 1
fi

# 4. Ceval Stack Operations Test
echo "=== Phase 4: Ceval Stack Operations ==="
if run_test "supabase/tests/04_ceval_stack_operations.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval stack operations test failed. Cannot continue."
    exit 1
fi

# 5. Ceval Opcode Utilities Test
echo "=== Phase 5: Ceval Opcode Utilities ==="
if run_test "supabase/tests/05_ceval_opcode_utils.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval opcode utilities test failed. Cannot continue."
    exit 1
fi

# 6. Ceval Integration Test
echo "=== Phase 6: Ceval Integration ==="
if run_test "supabase/tests/06_ceval_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval integration test failed. Cannot continue."
    exit 1
fi

# 7. Ceval Eval Frame Test
echo "=== Phase 7: Ceval Eval Frame ==="
if run_test "supabase/tests/07_ceval_eval_frame.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval eval frame test failed. Cannot continue."
    exit 1
fi

# 8. Ceval Basic Opcodes Test
echo "=== Phase 8: Ceval Basic Opcodes ==="
if run_test "supabase/tests/08_ceval_opcodes_basic.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval basic opcodes test failed. Cannot continue."
    exit 1
fi

# 9. Ceval Advanced Integration Test
echo "=== Phase 9: Ceval Advanced Integration ==="
if run_test "supabase/tests/09_ceval_integration_advanced.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval advanced integration test failed. Cannot continue."
    exit 1
fi

# 10. Ceval STORE_NAME Opcode Test
echo "=== Phase 10: Ceval STORE_NAME Opcode ==="
if run_test "supabase/tests/10_ceval_opcode_store_name.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval STORE_NAME opcode test failed. Cannot continue."
    exit 1
fi

# 11. Ceval STORE_NAME Integration Test
echo "=== Phase 11: Ceval STORE_NAME Integration ==="
if run_test "supabase/tests/11_ceval_integration_store_name.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval STORE_NAME integration test failed. Cannot continue."
    exit 1
fi

# 12. Ceval LOAD_NAME Opcode Test
echo "=== Phase 12: Ceval LOAD_NAME Opcode ==="
if run_test "supabase/tests/12_ceval_opcode_load_name.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval LOAD_NAME opcode test failed. Cannot continue."
    exit 1
fi

# 13. Ceval LOAD_NAME Integration Test
echo "=== Phase 13: Ceval LOAD_NAME Integration ==="
if run_test "supabase/tests/13_ceval_integration_load_name.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval LOAD_NAME integration test failed. Cannot continue."
    exit 1
fi

# 14. Ceval CALL_FUNCTION Opcode Test
echo "=== Phase 14: Ceval CALL_FUNCTION Opcode ==="
if run_test "supabase/tests/14_ceval_opcode_call_function.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval CALL_FUNCTION opcode test failed. Cannot continue."
    exit 1
fi

# 15. Ceval CALL_FUNCTION Integration Test
echo "=== Phase 15: Ceval CALL_FUNCTION Integration ==="
if run_test "supabase/tests/15_ceval_integration_call_function.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval CALL_FUNCTION integration test failed. Cannot continue."
    exit 1
fi

# 16. Ceval abs() Function Integration Test
echo "=== Phase 16: Ceval abs() Function Integration ==="
if run_test "supabase/tests/16_ceval_integration_abs.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval abs() function integration test failed. Cannot continue."
    exit 1
fi

# 17. tp_hash Slot System Test
echo "=== Phase 17: tp_hash Slot System ==="
if run_test "supabase/tests/17_tp_hash_slot.sql"; then
    echo ""
else
    echo ""
    echo "❌ tp_hash slot system test failed. Cannot continue."
    exit 1
fi

# 18. Dict Lookup Hash-Based Test
echo "=== Phase 18: Dict Lookup Hash-Based ==="
if run_test "supabase/tests/18_dict_lookup_hash.sql"; then
    echo ""
else
    echo ""
    echo "❌ Dict lookup hash-based test failed. Cannot continue."
    exit 1
fi

# 19. Ceval Full Pipeline Integration Test
echo "=== Phase 19: Ceval Full Pipeline Integration ==="
if run_test "supabase/tests/19_ceval_integration_full_pipeline.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval full pipeline integration test failed. Cannot continue."
    exit 1
fi

# 20. tp_richcompare Slot Test
echo "=== Phase 20: tp_richcompare Slot ==="
if run_test "supabase/tests/20_tp_richcompare_slot.sql"; then
    echo ""
else
    echo ""
    echo "❌ tp_richcompare slot test failed. Cannot continue."
    exit 1
fi

# 21. BINARY_ADD Slots (nb_add, sq_concat, dispatch)
echo "=== Phase 21: BINARY_ADD Slots ==="
if run_test "supabase/tests/21_binary_add_slots.sql"; then
    echo ""
else
    echo ""
    echo "❌ BINARY_ADD slots test failed. Cannot continue."
    exit 1
fi

# 22. BINARY_ADD Bytecode Integration (1+2, 'a'+'b', 1+'a'→TypeError)
echo "=== Phase 22: BINARY_ADD Bytecode Integration ==="
if run_test "supabase/tests/22_binary_add_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ BINARY_ADD bytecode integration test failed. Cannot continue."
    exit 1
fi

# 23. BINARY_SUBTRACT Slots (nb_subtract, py_object_subtract)
echo "=== Phase 23: BINARY_SUBTRACT Slots ==="
if run_test "supabase/tests/23_binary_subtract_slots.sql"; then
    echo ""
else
    echo ""
    echo "❌ BINARY_SUBTRACT slots test failed. Cannot continue."
    exit 1
fi

# 24. BINARY_SUBTRACT Bytecode Integration (5-3→2, 1-'a'→TypeError)
echo "=== Phase 24: BINARY_SUBTRACT Bytecode Integration ==="
if run_test "supabase/tests/24_binary_subtract_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ BINARY_SUBTRACT bytecode integration test failed. Cannot continue."
    exit 1
fi

# 25. BINARY_MULTIPLY Slots (nb_multiply, sq_repeat)
echo "=== Phase 25: BINARY_MULTIPLY Slots ==="
if run_test "supabase/tests/25_binary_multiply_slots.sql"; then
    echo ""
else
    echo ""
    echo "❌ BINARY_MULTIPLY slots test failed. Cannot continue."
    exit 1
fi

# 26. BINARY_MULTIPLY Bytecode Integration (2*3, 'a'*3, 2*'b', 'a'*'b'→TypeError)
echo "=== Phase 26: BINARY_MULTIPLY Bytecode Integration ==="
if run_test "supabase/tests/26_binary_multiply_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ BINARY_MULTIPLY bytecode integration test failed. Cannot continue."
    exit 1
fi

# 27. COMPARE_OP Slots (py_object_richcompare reflected op)
echo "=== Phase 27: COMPARE_OP Slots ==="
if run_test "supabase/tests/27_compare_op_slots.sql"; then
    echo ""
else
    echo ""
    echo "❌ COMPARE_OP slots test failed. Cannot continue."
    exit 1
fi

# 28. COMPARE_OP Bytecode Integration (1<2→True, 1>2→False, 1==1→True, 1<'a'→TypeError)
echo "=== Phase 28: COMPARE_OP Bytecode Integration ==="
if run_test "supabase/tests/28_compare_op_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ COMPARE_OP bytecode integration test failed. Cannot continue."
    exit 1
fi

# 29. PyObject_IsTrue Slots
echo "=== Phase 29: PyObject_IsTrue Slots ==="
if run_test "supabase/tests/29_py_object_istrue_slots.sql"; then
    echo ""
else
    echo ""
    echo "❌ PyObject_IsTrue slots test failed. Cannot continue."
    exit 1
fi

# 30. Jump Bytecode Integration (JUMP_FORWARD, POP_JUMP_FORWARD_IF_FALSE)
echo "=== Phase 30: Jump Bytecode Integration ==="
if run_test "supabase/tests/30_jump_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ Jump bytecode integration test failed. Cannot continue."
    exit 1
fi

# 31. POP_TOP Bytecode Integration
echo "=== Phase 31: POP_TOP Bytecode Integration ==="
if run_test "supabase/tests/31_pop_top_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ POP_TOP bytecode integration test failed. Cannot continue."
    exit 1
fi

# 32. Exception Schema & Helpers (CPython 3.11)
echo "=== Phase 32: Exception Schema & Helpers ==="
if run_test "supabase/tests/32_exception_schema.sql"; then
    echo ""
else
    echo ""
    echo "❌ Exception schema & helpers test failed. Cannot continue."
    exit 1
fi

# ===================================================
# Summary
# ===================================================

echo "==========================================="
echo "🎉 All Tests Passed!"
echo "==========================================="
echo ""
echo "Summary:"
echo "  ✅ 00: Bootstrap Validation (Object Model & Type System)"
echo "  ✅ 01: Function, Code, and Frame Schema Validation"
echo "  ✅ 02: Method Object Schema Validation"
echo "  ✅ 03: Builtin Functions Integration Test"
echo "  ✅ 04: Ceval Stack Operations Test"
echo "  ✅ 05: Ceval Opcode Utilities Test"
echo "  ✅ 06: Ceval Integration Test"
echo "  ✅ 07: Ceval Eval Frame Test"
echo "  ✅ 08: Ceval Basic Opcodes Test"
echo "  ✅ 09: Ceval Advanced Integration Test"
echo "  ✅ 10: Ceval STORE_NAME Opcode Test"
echo "  ✅ 11: Ceval STORE_NAME Integration Test"
echo "  ✅ 12: Ceval LOAD_NAME Opcode Test"
echo "  ✅ 13: Ceval LOAD_NAME Integration Test"
echo "  ✅ 14: Ceval CALL_FUNCTION Opcode Test"
echo "  ✅ 15: Ceval CALL_FUNCTION Integration Test"
echo "  ✅ 16: Ceval abs() Function Integration Test"
echo "  ✅ 17: tp_hash Slot System Test"
echo "  ✅ 18: Dict Lookup Hash-Based Test"
echo "  ✅ 19: Ceval Full Pipeline Integration Test"
echo "  ✅ 20: tp_richcompare Slot Test"
echo "  ✅ 21: BINARY_ADD Slots (nb_add, sq_concat, dispatch)"
echo "  ✅ 22: BINARY_ADD Bytecode Integration (1+2, 'a'+'b', 1+'a'→TypeError)"
echo "  ✅ 23: BINARY_SUBTRACT Slots (nb_subtract)"
echo "  ✅ 24: BINARY_SUBTRACT Bytecode Integration (5-3→2, 1-'a'→TypeError)"
echo "  ✅ 25: BINARY_MULTIPLY Slots (nb_multiply, sq_repeat)"
echo "  ✅ 26: BINARY_MULTIPLY Bytecode Integration (2*3, 'a'*3, 2*'b', 'a'*'b'→TypeError)"
echo "  ✅ 27: COMPARE_OP Slots (py_object_richcompare reflected op)"
echo "  ✅ 28: COMPARE_OP Bytecode Integration (1<2→True, 1>2→False, 1==1→True, 1<'a'→TypeError)"
echo "  ✅ 29: PyObject_IsTrue Slots"
echo "  ✅ 30: Jump Bytecode Integration (JUMP_FORWARD, POP_JUMP_FORWARD_IF_FALSE)"
echo "  ✅ 31: POP_TOP Bytecode Integration"
echo "  ✅ 32: Exception Schema & Helpers (CPython 3.11)"
echo ""
echo "Total: 33 test suites passed ✨"
echo ""
echo "Note: Additional tests can be added to supabase/tests/ directory"
echo ""
