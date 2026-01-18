#!/bin/bash

# Database Connection Info
DB_HOST="127.0.0.1"
DB_PORT="54322"
DB_USER="postgres"
DB_NAME="postgres"
# PGPASSWORD is usually 'postgres' for local supabase

export PGPASSWORD="postgres"

echo "==========================================="
echo "Running Elytra VM Test Suite"
echo "==========================================="

# Function to run a single test file
run_test() {
    local file=$1
    # Use docker exec to run psql inside the container
    docker exec -i supabase_db_elytra psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$file" > /tmp/test_out.log 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ PASS: $file"
        # Optional: Show 'TEST PASSED' notices from log
        if grep -q "TEST PASSED" /tmp/test_out.log; then
             grep "TEST PASSED" /tmp/test_out.log | sed 's/^/   /'
        fi
    else
        echo "❌ FAIL: $file"
        cat /tmp/test_out.log
        exit 1
    fi
}

# 0. Setup
run_test "supabase/tests/00_setup/01_helpers.sql"

# 1. Objects
for f in supabase/tests/01_objects/*.sql; do run_test "$f"; done

# 2. Ops
for f in supabase/tests/02_ops/*.sql; do run_test "$f"; done

# 3. Control Flow
for f in supabase/tests/03_control_flow/*.sql; do run_test "$f"; done

# 5. Collections
for f in supabase/tests/05_collections/*.sql; do run_test "$f"; done

echo "==========================================="
echo "🎉 All Tests Passed!"
echo "==========================================="
