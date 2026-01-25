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

# 4. VM Stack Operations Test
echo "=== Phase 4: VM Stack Operations ==="
if run_test "supabase/tests/04_vm_stack_operations.sql"; then
    echo ""
else
    echo ""
    echo "❌ VM stack operations test failed. Cannot continue."
    exit 1
fi

# 5. VM Opcode Utilities Test
echo "=== Phase 5: VM Opcode Utilities ==="
if run_test "supabase/tests/05_vm_opcode_utils.sql"; then
    echo ""
else
    echo ""
    echo "❌ VM opcode utilities test failed. Cannot continue."
    exit 1
fi

# 6. VM Integration Test
echo "=== Phase 6: VM Integration ==="
if run_test "supabase/tests/06_vm_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ VM integration test failed. Cannot continue."
    exit 1
fi

# 7. VM Frame Evaluation Test
echo "=== Phase 7: VM Frame Evaluation ==="
if run_test "supabase/tests/07_vm_eval_frame.sql"; then
    echo ""
else
    echo ""
    echo "❌ VM frame evaluation test failed. Cannot continue."
    exit 1
fi

# 8. VM Basic Opcodes Test
echo "=== Phase 8: VM Basic Opcodes ==="
if run_test "supabase/tests/08_vm_opcodes_basic.sql"; then
    echo ""
else
    echo ""
    echo "❌ VM basic opcodes test failed. Cannot continue."
    exit 1
fi

# 9. VM Advanced Integration Test
echo "=== Phase 9: VM Advanced Integration ==="
if run_test "supabase/tests/09_vm_integration_advanced.sql"; then
    echo ""
else
    echo ""
    echo "❌ VM advanced integration test failed. Cannot continue."
    exit 1
fi

# 10. VM STORE_NAME Opcode Test
echo "=== Phase 10: VM STORE_NAME Opcode ==="
if run_test "supabase/tests/10_vm_opcode_store_name.sql"; then
    echo ""
else
    echo ""
    echo "❌ VM STORE_NAME opcode test failed. Cannot continue."
    exit 1
fi

# 11. VM STORE_NAME Integration Test
echo "=== Phase 11: VM STORE_NAME Integration ==="
if run_test "supabase/tests/11_vm_integration_store_name.sql"; then
    echo ""
else
    echo ""
    echo "❌ VM STORE_NAME integration test failed. Cannot continue."
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
echo "  ✅ 04: VM Stack Operations Test"
echo "  ✅ 05: VM Opcode Utilities Test"
echo "  ✅ 06: VM Integration Test"
echo "  ✅ 07: VM Frame Evaluation Test"
echo "  ✅ 08: VM Basic Opcodes Test"
echo "  ✅ 09: VM Advanced Integration Test"
echo "  ✅ 10: VM STORE_NAME Opcode Test"
echo "  ✅ 11: VM STORE_NAME Integration Test"
echo ""
echo "Total: 12 test suites passed ✨"
echo ""
echo "Note: Additional tests can be added to supabase/tests/ directory"
echo ""
