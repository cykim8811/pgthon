#!/bin/bash

# =====================================================
# Elytra VM Test Suite Runner
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
echo "🧪 Elytra VM Test Suite"
echo "==========================================="
echo ""

# Function to run a single test file
run_test() {
    local file=$1
    local test_name=$(basename "$file" .sql)
    
    # Use docker exec to run psql inside the container
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$file" > /tmp/test_out.log 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ PASS: $test_name"
        # Show test passed notices
        if grep -q "TEST PASSED" /tmp/test_out.log; then
            grep "TEST PASSED" /tmp/test_out.log | head -3 | sed 's/^/   /'
            local count=$(grep -c "TEST PASSED" /tmp/test_out.log)
            if [ "$count" -gt 3 ]; then
                echo "   ... and $((count - 3)) more tests"
            fi
        fi
    else
        echo "❌ FAIL: $test_name"
        echo ""
        cat /tmp/test_out.log
        echo ""
        exit 1
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

# 0. Setup (Helper Functions)
echo "=== Phase 0: Setup ==="
run_test "supabase/tests/00_setup.sql"
echo ""

# 1. Object Model
echo "=== Phase 1: Object Model ==="
run_test "supabase/tests/01_object_model.sql"
echo ""

# 2. Built-ins and Methods  
echo "=== Phase 2: Built-ins & Methods ==="
run_test "supabase/tests/02_builtins_and_methods.sql"
echo ""

# 3. VM Helpers
echo "=== Phase 3: VM Helpers ==="
run_test "supabase/tests/03_vm_helpers.sql"
echo ""

# 4. Arithmetic
echo "=== Phase 4: Arithmetic Operations ==="
run_test "supabase/tests/04_arithmetic.sql"
echo ""

# 5. Bytecode Execution
echo "=== Phase 5: Bytecode Execution ==="
run_test "supabase/tests/05_bytecode_execution.sql"
echo ""

# 6. Object Protocol
echo "=== Phase 6: Object Protocol ==="
run_test "supabase/tests/06_object_protocol.sql"
echo ""

# 7. Integration Tests
echo "=== Phase 7: Integration ==="
run_test "supabase/tests/07_integration.sql"
echo ""

# 8. Frame Objects
echo "=== Phase 8: Frame Objects ==="
run_test "supabase/tests/08_frames.sql"
echo ""

# ===================================================
# Summary
# ===================================================

echo "==========================================="
echo "🎉 All Tests Passed!"
echo "==========================================="
echo ""
echo "Summary:"
echo "  ✅ 00: Setup (Helper Functions)"
echo "  ✅ 01: Object Model & Type System"
echo "  ✅ 02: Built-ins & Methods"
echo "  ✅ 03: VM Helpers"
echo "  ✅ 04: Arithmetic Operations"
echo "  ✅ 05: Bytecode Execution"
echo "  ✅ 06: Object Protocol"
echo "  ✅ 07: Integration Tests"
echo "  ✅ 08: Frame Objects & Introspection"
echo ""
echo "Total: 9 test suites passed ✨"
echo ""
