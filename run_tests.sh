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

# 33. Exception Table Parsing (co_exceptiontable)
echo "=== Phase 33: Exception Table Parsing ==="
if run_test "supabase/tests/33_exception_table_parsing.sql"; then
    echo ""
else
    echo ""
    echo "❌ Exception table parsing test failed. Cannot continue."
    exit 1
fi

# 34. Try/Except Integration (exception table → handler → return)
echo "=== Phase 34: Try/Except Integration ==="
if run_test "supabase/tests/34_try_except_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ Try/except integration test failed. Cannot continue."
    exit 1
fi

# 35. tp_call kwargs rejection (CPython fidelity: len()/abs() take no keyword arguments)
echo "=== Phase 35: tp_call kwargs rejection ==="
if run_test "supabase/tests/35_tp_call_kwargs_reject.sql"; then
    echo ""
else
    echo ""
    echo "❌ tp_call kwargs rejection test failed. Cannot continue."
    exit 1
fi

# 36. CALL_FUNCTION_KW opcode integration (keyword args from bytecode → TypeError for len/abs)
echo "=== Phase 36: CALL_FUNCTION_KW Integration ==="
if run_test "supabase/tests/36_call_function_kw_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ CALL_FUNCTION_KW integration test failed. Cannot continue."
    exit 1
fi

# 37. METH_KEYWORDS builtin integration (first_kwarg accepts kwargs)
echo "=== Phase 37: METH_KEYWORDS Integration ==="
if run_test "supabase/tests/37_meth_keywords_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ METH_KEYWORDS integration test failed. Cannot continue."
    exit 1
fi

# 38. EXTENDED_ARG bytecode integration (opcode 144 prefix → extended operand)
echo "=== Phase 38: EXTENDED_ARG Integration ==="
if run_test "supabase/tests/38_extended_arg_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ EXTENDED_ARG integration test failed. Cannot continue."
    exit 1
fi

# 39. float slots integration (nb_add, nb_subtract, nb_multiply, tp_hash, tp_richcompare)
echo "=== Phase 39: float Slots Integration ==="
if run_test "supabase/tests/39_float_slots_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ float slots integration test failed. Cannot continue."
    exit 1
fi

# 40. bytes slots integration (sq_length, sq_concat, sq_repeat, tp_richcompare)
echo "=== Phase 40: bytes Slots Integration ==="
if run_test "supabase/tests/40_bytes_slots_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ bytes slots integration test failed. Cannot continue."
    exit 1
fi

# 41. BUILD_TUPLE / BUILD_LIST bytecode integration
echo "=== Phase 41: BUILD_TUPLE / BUILD_LIST Integration ==="
if run_test "supabase/tests/41_build_tuple_list_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ BUILD_TUPLE/BUILD_LIST integration test failed. Cannot continue."
    exit 1
fi

# 42. LOAD_ATTR bytecode integration (type(obj).tp_dict lookup, AttributeError)
echo "=== Phase 42: LOAD_ATTR Integration ==="
if run_test "supabase/tests/42_load_attr_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ LOAD_ATTR integration test failed. Cannot continue."
    exit 1
fi

# 43. LOAD_ATTR Phase 2 (instance __dict__, type+bases, not found → AttributeError)
echo "=== Phase 43: LOAD_ATTR Phase 2 Integration ==="
if run_test "supabase/tests/43_load_attr_phase2_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ LOAD_ATTR Phase 2 integration test failed. Cannot continue."
    exit 1
fi

# 44. STORE_ATTR Bytecode Integration (obj.x = value, then LOAD_ATTR; non-instance → AttributeError)
echo "=== Phase 44: STORE_ATTR Integration ==="
if run_test "supabase/tests/44_store_attr_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ STORE_ATTR integration test failed. Cannot continue."
    exit 1
fi

# 45. Bound Method Integration (getattr(inst,"f")→bound method; getattr(Type,"f")→func; bytecode LOAD_ATTR)
echo "=== Phase 45: Bound Method Integration ==="
if run_test "supabase/tests/45_bound_method_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ Bound method integration test failed. Cannot continue."
    exit 1
fi

# 46. Integrated Scenarios (LOAD_ATTR, STORE_ATTR, Bound Method, Type.attr combined)
echo "=== Phase 46: Integrated Scenarios ==="
if run_test "supabase/tests/46_integrated_scenarios.sql"; then
    echo ""
else
    echo ""
    echo "❌ Integrated scenarios test failed. Cannot continue."
    exit 1
fi

# 47. STORE_ATTR Class (C.x = v) — type object setattr, then LOAD_ATTR(C, "x") → v
echo "=== Phase 47: STORE_ATTR Class (C.x = v) Integration ==="
if run_test "supabase/tests/47_store_attr_class_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ STORE_ATTR class integration test failed. Cannot continue."
    exit 1
fi

# 48. DELETE_ATTR Bytecode Integration (del obj.x / del C.x → AttributeError when absent)
echo "=== Phase 48: DELETE_ATTR Integration ==="
if run_test "supabase/tests/48_delete_attr_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ DELETE_ATTR integration test failed. Cannot continue."
    exit 1
fi

echo "=== Phase 49: BINARY_OP(122) Integration ==="
if run_test "supabase/tests/49_binary_op_integration.sql"; then
    echo ""
else
    echo ""
    echo "❌ BINARY_OP(122) integration test failed. Cannot continue."
    exit 1
fi

# 50. LOAD_GLOBAL (116) Opcode Test (CPython 3.11: globals+builtins only)
echo "=== Phase 50: Ceval LOAD_GLOBAL Opcode ==="
if run_test "supabase/tests/50_ceval_opcode_load_global.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval LOAD_GLOBAL opcode test failed. Cannot continue."
    exit 1
fi

# 51. LOAD_GLOBAL Integration Test (bytecode + combined scenarios)
echo "=== Phase 51: Ceval LOAD_GLOBAL Integration ==="
if run_test "supabase/tests/51_ceval_integration_load_global.sql"; then
    echo ""
else
    echo ""
    echo "❌ Ceval LOAD_GLOBAL integration test failed. Cannot continue."
    exit 1
fi

# 52. LOAD_FAST / STORE_FAST Opcode Test (CPython 3.11: f_fastlocals)
echo "=== Phase 52: Ceval LOAD_FAST / STORE_FAST Opcode ==="
if run_test "supabase/tests/52_ceval_opcode_load_fast_store_fast.sql"; then
    echo ""
else
    echo ""
    echo "❌ LOAD_FAST / STORE_FAST opcode test failed. Cannot continue."
    exit 1
fi

# 53. LOAD_FAST / STORE_FAST Integration (bytecode x=1; return x, a+b, frame isolation)
echo "=== Phase 53: Ceval LOAD_FAST / STORE_FAST Integration ==="
if run_test "supabase/tests/53_ceval_integration_load_fast_store_fast.sql"; then
    echo ""
else
    echo ""
    echo "❌ LOAD_FAST / STORE_FAST integration test failed. Cannot continue."
    exit 1
fi

# 54. NOP(9), JUMP_BACKWARD(140), DELETE_FAST(126) Opcode (CPython 3.11)
echo "=== Phase 54: Ceval NOP / JUMP_BACKWARD / DELETE_FAST Opcode ==="
if run_test "supabase/tests/54_ceval_opcode_nop_jump_backward_delete_fast.sql"; then
    echo ""
else
    echo ""
    echo "❌ NOP / JUMP_BACKWARD / DELETE_FAST opcode test failed. Cannot continue."
    exit 1
fi

# 55. POP_JUMP_BACKWARD_IF_FALSE(175), POP_JUMP_BACKWARD_IF_TRUE(176) Opcode (CPython 3.11)
echo "=== Phase 55: Ceval POP_JUMP_BACKWARD Opcode ==="
if run_test "supabase/tests/55_ceval_opcode_pop_jump_backward.sql"; then
    echo ""
else
    echo ""
    echo "❌ POP_JUMP_BACKWARD opcode test failed. Cannot continue."
    exit 1
fi

# 56. DELETE_GLOBAL(98) Opcode (CPython 3.11: del globals[name], NameError if missing)
echo "=== Phase 56: Ceval DELETE_GLOBAL Opcode ==="
if run_test "supabase/tests/56_ceval_opcode_delete_global.sql"; then
    echo ""
else
    echo ""
    echo "❌ DELETE_GLOBAL opcode test failed. Cannot continue."
    exit 1
fi

# 57. COPY(120) Opcode (CPython 3.11: copy stack[-depth] to top)
echo "=== Phase 57: Ceval COPY Opcode ==="
if run_test "supabase/tests/57_ceval_opcode_copy.sql"; then
    echo ""
else
    echo ""
    echo "❌ COPY opcode test failed. Cannot continue."
    exit 1
fi

# 58. POP_JUMP_BACKWARD_IF_NONE(173) / POP_JUMP_BACKWARD_IF_NOT_NONE(174) Opcode (CPython 3.11)
echo "=== Phase 58: Ceval POP_JUMP_BACKWARD IF_NONE/IF_NOT_NONE Opcode ==="
if run_test "supabase/tests/58_ceval_opcode_pop_jump_backward_if_none.sql"; then
    echo ""
else
    echo ""
    echo "❌ POP_JUMP_BACKWARD IF_NONE/IF_NOT_NONE opcode test failed. Cannot continue."
    exit 1
fi

# 59. UNARY_NOT(12) Opcode (CPython 3.11: not x → True/False)
echo "=== Phase 59: Ceval UNARY_NOT Opcode ==="
if run_test "supabase/tests/59_ceval_opcode_unary_not.sql"; then
    echo ""
else
    echo ""
    echo "❌ UNARY_NOT opcode test failed. Cannot continue."
    exit 1
fi

# 60. IS_OP(117) Opcode (CPython 3.11: is / is not, identity comparison)
echo "=== Phase 60: Ceval IS_OP Opcode ==="
if run_test "supabase/tests/60_ceval_opcode_is_op.sql"; then
    echo ""
else
    echo ""
    echo "❌ IS_OP opcode test failed. Cannot continue."
    exit 1
fi

# 61. POP_JUMP_FORWARD_IF_NONE(128) / POP_JUMP_FORWARD_IF_NOT_NONE(129) Opcode (CPython 3.11)
echo "=== Phase 61: Ceval POP_JUMP_FORWARD IF_NONE/IF_NOT_NONE Opcode ==="
if run_test "supabase/tests/61_ceval_opcode_pop_jump_forward_if_none.sql"; then
    echo ""
else
    echo ""
    echo "❌ POP_JUMP_FORWARD IF_NONE/IF_NOT_NONE opcode test failed. Cannot continue."
    exit 1
fi

# 62. LIST_TO_TUPLE(82) Opcode (CPython 3.11: list → tuple)
echo "=== Phase 62: Ceval LIST_TO_TUPLE Opcode ==="
if run_test "supabase/tests/62_ceval_opcode_list_to_tuple.sql"; then
    echo ""
else
    echo ""
    echo "❌ LIST_TO_TUPLE opcode test failed. Cannot continue."
    exit 1
fi

# 63. JUMP_IF_FALSE_OR_POP(111) / JUMP_IF_TRUE_OR_POP(112) Opcode (CPython 3.11)
echo "=== Phase 63: Ceval JUMP_IF_FALSE_OR_POP / JUMP_IF_TRUE_OR_POP Opcode ==="
if run_test "supabase/tests/63_ceval_opcode_jump_if_false_or_pop.sql"; then
    echo ""
else
    echo ""
    echo "❌ JUMP_IF_FALSE_OR_POP/JUMP_IF_TRUE_OR_POP opcode test failed. Cannot continue."
    exit 1
fi

# 64. UNPACK_SEQUENCE(92) Opcode (CPython 3.11: unpack tuple/list to stack)
echo "=== Phase 64: Ceval UNPACK_SEQUENCE Opcode ==="
if run_test "supabase/tests/64_ceval_opcode_unpack_sequence.sql"; then
    echo ""
else
    echo ""
    echo "❌ UNPACK_SEQUENCE opcode test failed. Cannot continue."
    exit 1
fi

# 65. CONTAINS_OP(118) Opcode (CPython 3.11: in / not in)
echo "=== Phase 65: Ceval CONTAINS_OP Opcode ==="
if run_test "supabase/tests/65_ceval_opcode_contains_op.sql"; then
    echo ""
else
    echo ""
    echo "❌ CONTAINS_OP opcode test failed. Cannot continue."
    exit 1
fi

# 66. BUILD_MAP(105) Opcode (CPython 3.11: build dict from stack)
echo "=== Phase 66: Ceval BUILD_MAP Opcode ==="
if run_test "supabase/tests/66_ceval_opcode_build_map.sql"; then
    echo ""
else
    echo ""
    echo "❌ BUILD_MAP opcode test failed. Cannot continue."
    exit 1
fi

# 67. BINARY_SUBSCR(25) Opcode (CPython 3.11: obj[key] — tuple, list, dict)
echo "=== Phase 67: Ceval BINARY_SUBSCR Opcode ==="
if run_test "supabase/tests/67_ceval_opcode_binary_subscr.sql"; then
    echo ""
else
    echo ""
    echo "❌ BINARY_SUBSCR opcode test failed. Cannot continue."
    exit 1
fi

# 68. STORE_SUBSCR(60) Opcode (CPython 3.11: obj[key]=value — list, dict; tuple→TypeError)
echo "=== Phase 68: Ceval STORE_SUBSCR Opcode ==="
if run_test "supabase/tests/68_ceval_opcode_store_subscr.sql"; then
    echo ""
else
    echo ""
    echo "❌ STORE_SUBSCR opcode test failed. Cannot continue."
    exit 1
fi

# 69. DELETE_SUBSCR(61) Opcode (CPython 3.11: del obj[key] — list, dict; tuple→TypeError)
echo "=== Phase 69: Ceval DELETE_SUBSCR Opcode ==="
if run_test "supabase/tests/69_ceval_opcode_delete_subscr.sql"; then
    echo ""
else
    echo ""
    echo "❌ DELETE_SUBSCR opcode test failed. Cannot continue."
    exit 1
fi

# 70. BUILD_SLICE(133) Opcode (CPython 3.11: slice(start, stop [, step]))
echo "=== Phase 70: Ceval BUILD_SLICE Opcode ==="
if run_test "supabase/tests/70_ceval_opcode_build_slice.sql"; then
    echo ""
else
    echo ""
    echo "❌ BUILD_SLICE opcode test failed. Cannot continue."
    exit 1
fi

# 71. MAKE_FUNCTION(132) Opcode + py_call_function (user-defined function def + call)
echo "=== Phase 71: Ceval MAKE_FUNCTION Opcode ==="
if run_test "supabase/tests/71_ceval_opcode_make_function.sql"; then
    echo ""
else
    echo ""
    echo "❌ MAKE_FUNCTION opcode test failed. Cannot continue."
    exit 1
fi

# 72. UNARY_NEGATIVE(11) Opcode (CPython 3.11: -x via nb_negative)
echo "=== Phase 72: Ceval UNARY_NEGATIVE Opcode ==="
if run_test "supabase/tests/72_ceval_opcode_unary_negative.sql"; then
    echo ""
else
    echo ""
    echo "❌ UNARY_NEGATIVE opcode test failed. Cannot continue."
    exit 1
fi

echo "=== Phase 73: Ceval UNARY_POSITIVE Opcode ==="
if run_test "supabase/tests/73_ceval_opcode_unary_positive.sql"; then
    echo ""
else
    echo ""
    echo "❌ UNARY_POSITIVE opcode test failed. Cannot continue."
    exit 1
fi

echo "=== Phase 74: Ceval LOAD_METHOD Opcode ==="
if run_test "supabase/tests/74_ceval_opcode_load_method.sql"; then
    echo ""
else
    echo ""
    echo "❌ LOAD_METHOD opcode test failed. Cannot continue."
    exit 1
fi

# 75. GET_ITER(68) + FOR_ITER(93) Opcode (CPython 3.11: iteration protocol)
echo "=== Phase 75: Ceval GET_ITER / FOR_ITER Opcode ==="
if run_test "supabase/tests/75_ceval_opcode_get_iter_for_iter.sql"; then
    echo ""
else
    echo ""
    echo "❌ GET_ITER / FOR_ITER opcode test failed. Cannot continue."
    exit 1
fi

# 76. Closure Opcodes (MAKE_CELL, LOAD_CLOSURE, LOAD_DEREF, STORE_DEREF, COPY_FREE_VARS)
echo "=== Phase 76: Ceval Closure Opcodes ==="
if run_test "supabase/tests/76_ceval_opcode_closures.sql"; then
    echo ""
else
    echo ""
    echo "❌ Closure opcode test failed. Cannot continue."
    exit 1
fi

# 77. print() Builtin + py_object_str()
echo "=== Phase 77: print() Builtin ==="
if run_test "supabase/tests/77_builtin_print.sql"; then
    echo ""
else
    echo ""
    echo "❌ print builtin test failed. Cannot continue."
    exit 1
fi

# 78. range() Builtin + Range Iterator
echo "=== Phase 78: range() Builtin ==="
if run_test "supabase/tests/78_builtin_range.sql"; then
    echo ""
else
    echo ""
    echo "❌ range builtin test failed. Cannot continue."
    exit 1
fi

# 79. Class Construction (LOAD_BUILD_CLASS + __build_class__)
echo "=== Phase 79: Class Construction ==="
if run_test "supabase/tests/79_class_construction.sql"; then
    echo ""
else
    echo ""
    echo "❌ Class construction test failed. Cannot continue."
    exit 1
fi

# 80. Instance Creation (py_type_tp_call, __init__, Dog("Rex").name)
echo "=== Phase 80: Instance Creation ==="
if run_test "supabase/tests/80_instance_creation.sql"; then
    echo ""
else
    echo ""
    echo "❌ Instance creation test failed. Cannot continue."
    exit 1
fi

# 81. Type Constructors (int/str/float/bool/list/tuple/dict)
echo "=== Phase 81: Type Constructors ==="
if run_test "supabase/tests/81_type_constructors.sql"; then
    echo ""
else
    echo ""
    echo "❌ Type constructors test failed. Cannot continue."
    exit 1
fi

# 82. Common Builtins (isinstance, hasattr, getattr, setattr, id)
echo "=== Phase 82: Common Builtins ==="
if run_test "supabase/tests/82_common_builtins.sql"; then
    echo ""
else
    echo ""
    echo "❌ Common builtins test failed. Cannot continue."
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
echo "  ✅ 33: Exception Table Parsing (co_exceptiontable)"
echo "  ✅ 34: Try/Except Integration (exception table → handler → return)"
echo "  ✅ 35: tp_call kwargs rejection (len()/abs() take no keyword arguments)"
echo "  ✅ 36: CALL_FUNCTION_KW Integration (keyword args from bytecode)"
echo "  ✅ 37: METH_KEYWORDS Integration (first_kwarg accepts kwargs)"
echo "  ✅ 38: EXTENDED_ARG Integration (opcode 144 extended operand)"
echo "  ✅ 39: float Slots Integration (nb_add/subtract/multiply, tp_hash, tp_richcompare)"
echo "  ✅ 40: bytes Slots Integration (sq_length, sq_concat, sq_repeat, tp_richcompare)"
echo "  ✅ 41: BUILD_TUPLE / BUILD_LIST Bytecode Integration"
echo "  ✅ 42: LOAD_ATTR Bytecode Integration (tp_dict lookup, AttributeError)"
echo "  ✅ 43: LOAD_ATTR Phase 2 (instance __dict__, type+bases, AttributeError)"
echo "  ✅ 44: STORE_ATTR Bytecode Integration (obj.x = value; non-instance → AttributeError)"
echo "  ✅ 45: Bound Method Integration (getattr(inst,\"f\")→bound method; getattr(Type,\"f\")→func)"
echo "  ✅ 46: Integrated Scenarios (LOAD_ATTR, STORE_ATTR, Bound Method, Type.attr combined)"
echo "  ✅ 47: STORE_ATTR Class (C.x = v) — type object setattr, LOAD_ATTR(C, \"x\") → v"
echo "  ✅ 48: DELETE_ATTR Bytecode Integration (del obj.x / del C.x)"
echo "  ✅ 49: BINARY_OP(122) Bytecode Integration (NB_ADD/NB_SUBTRACT/NB_MULTIPLY, unsupported→TypeError)"
echo "  ✅ 50: Ceval LOAD_GLOBAL Opcode (CPython 3.11 opcode 116: globals+builtins only)"
echo "  ✅ 51: Ceval LOAD_GLOBAL Integration (bytecode + len(\"hello\") + ignore locals)"
echo "  ✅ 52: LOAD_FAST / STORE_FAST Opcode (f_fastlocals, referenced before assignment)"
echo "  ✅ 53: LOAD_FAST / STORE_FAST Integration (x=1; return x, a+b, frame isolation)"
echo "  ✅ 54: NOP(9) / JUMP_BACKWARD(140) / DELETE_FAST(126) Opcode (CPython 3.11)"
echo "  ✅ 55: POP_JUMP_BACKWARD_IF_FALSE(175) / POP_JUMP_BACKWARD_IF_TRUE(176) Opcode (CPython 3.11)"
echo "  ✅ 56: DELETE_GLOBAL(98) Opcode (CPython 3.11: del globals[name], NameError if missing)"
echo "  ✅ 57: COPY(120) Opcode (CPython 3.11: copy stack[-depth] to top)"
echo "  ✅ 58: POP_JUMP_BACKWARD_IF_NONE(173) / POP_JUMP_BACKWARD_IF_NOT_NONE(174) Opcode (CPython 3.11)"
echo "  ✅ 59: UNARY_NOT(12) Opcode (CPython 3.11: not x → True/False)"
echo "  ✅ 60: IS_OP(117) Opcode (CPython 3.11: is / is not, identity comparison)"
echo "  ✅ 61: POP_JUMP_FORWARD_IF_NONE(128) / POP_JUMP_FORWARD_IF_NOT_NONE(129) Opcode (CPython 3.11)"
echo "  ✅ 62: LIST_TO_TUPLE(82) Opcode (CPython 3.11: list → tuple)"
echo "  ✅ 63: JUMP_IF_FALSE_OR_POP(111) / JUMP_IF_TRUE_OR_POP(112) Opcode (CPython 3.11)"
echo "  ✅ 64: UNPACK_SEQUENCE(92) Opcode (CPython 3.11: unpack tuple/list to stack)"
echo "  ✅ 65: CONTAINS_OP(118) Opcode (CPython 3.11: in / not in)"
echo "  ✅ 66: BUILD_MAP(105) Opcode (CPython 3.11: build dict from stack)"
echo "  ✅ 67: BINARY_SUBSCR(25) Opcode (CPython 3.11: obj[key] — tuple, list, dict)"
echo "  ✅ 68: STORE_SUBSCR(60) Opcode (CPython 3.11: obj[key]=value — list, dict)"
echo "  ✅ 69: DELETE_SUBSCR(61) Opcode (CPython 3.11: del obj[key] — list, dict)"
echo "  ✅ 70: BUILD_SLICE(133) Opcode (CPython 3.11: slice(start, stop [, step]))"
echo "  ✅ 71: MAKE_FUNCTION(132) Opcode (CPython 3.11: def statement + user function call)"
echo "  ✅ 72: UNARY_NEGATIVE(11) Opcode (CPython 3.11: -x via nb_negative)"
echo "  ✅ 73: UNARY_POSITIVE(10) Opcode (CPython 3.11: +x via nb_positive)"
echo "  ✅ 74: LOAD_METHOD(160) Opcode (CPython 3.11: method/slot, 1 or 2 values)"
echo "  ✅ 75: GET_ITER(68) + FOR_ITER(93) Opcode (CPython 3.11: iteration protocol)"
echo "  ✅ 76: Closure Opcodes (MAKE_CELL, LOAD_CLOSURE, LOAD_DEREF, STORE_DEREF, COPY_FREE_VARS)"
echo "  ✅ 77: print() Builtin + py_object_str (str/repr/print via RAISE NOTICE)"
echo "  ✅ 78: range() Builtin (range(5), range(1,10,2), range(0) via for loop)"
echo "  ✅ 79: Class Construction (LOAD_BUILD_CLASS + __build_class__ + class Foo: x=42)"
echo "  ✅ 80: Instance Creation (py_type_tp_call, __init__, Dog(\"Rex\").name)"
echo "  ✅ 81: Type Constructors (int/str/float/bool/list/tuple/dict)"
echo "  ✅ 82: Common Builtins (isinstance, hasattr, getattr, setattr, id)"
echo ""
echo "Total: 82 test suites passed ✨"
echo ""
echo "Note: Additional tests can be added to supabase/tests/ directory"
echo ""
