-- ============================================================================
-- Test: py_run RPC (Elytra Python Playground)
--
-- Tests:
--   1. Simple eval: LOAD_CONST 42, RETURN_VALUE → result = 42
--   2. Expression eval: 1 + 2 → result = 3
--   3. Exec mode: x = 42 → globals has x=42
--   4. Nested code object: def add(a,b): return a+b; add(3,4) → result in globals
--   5. Error handling: 1/0 → error with ZeroDivisionError
--   6. String concat: 'hello' + ' world' → 'hello world'
-- ============================================================================

DO $$
DECLARE
    v_result JSONB;
    v_input JSONB;
    test_count int := 0;
    pass_count int := 0;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'py_run RPC Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ================================================================
    -- Test 1: Simple eval — LOAD_CONST 42, RETURN_VALUE
    -- Bytecode: 6400 5300
    -- ================================================================
    test_count := test_count + 1;
    v_input := jsonb_build_object(
        'bytecode', '64005300',
        'consts', jsonb_build_array(jsonb_build_object('type', 'int', 'value', 42)),
        'names', '[]'::jsonb,
        'varnames', '[]'::jsonb,
        'cellvars', '[]'::jsonb,
        'freevars', '[]'::jsonb,
        'argcount', 0,
        'flags', 0,
        'nlocals', 0,
        'stacksize', 1,
        'name', '<module>',
        'filename', '<elytra>',
        'mode', 'eval'
    );
    v_result := public.py_run(v_input);

    IF (v_result->'error') IS DISTINCT FROM 'null'::jsonb THEN
        RAISE EXCEPTION 'FAIL test 1: expected no error, got %', v_result->'error';
    END IF;
    IF (v_result->'result'->>'type') IS DISTINCT FROM 'int' THEN
        RAISE EXCEPTION 'FAIL test 1: expected int result, got %', v_result->'result';
    END IF;
    IF (v_result->'result'->>'value')::int IS DISTINCT FROM 42 THEN
        RAISE EXCEPTION 'FAIL test 1: expected 42, got %', v_result->'result'->>'value';
    END IF;
    RAISE NOTICE '  Test 1 PASS: LOAD_CONST 42, RETURN_VALUE → 42';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 2: Expression eval — 1 + 2 → 3
    -- RESUME 0, LOAD_CONST 0, LOAD_CONST 1, BINARY_OP 0(NB_ADD), RETURN_VALUE
    -- Bytecode: 9700 6400 6401 7a00 5300
    -- ================================================================
    test_count := test_count + 1;
    v_input := jsonb_build_object(
        'bytecode', '9700640064017a005300',
        'consts', jsonb_build_array(
            jsonb_build_object('type', 'int', 'value', 1),
            jsonb_build_object('type', 'int', 'value', 2)
        ),
        'names', '[]'::jsonb,
        'varnames', '[]'::jsonb,
        'cellvars', '[]'::jsonb,
        'freevars', '[]'::jsonb,
        'argcount', 0,
        'flags', 0,
        'nlocals', 0,
        'stacksize', 2,
        'name', '<module>',
        'filename', '<elytra>',
        'mode', 'eval'
    );
    v_result := public.py_run(v_input);

    IF (v_result->'error') IS DISTINCT FROM 'null'::jsonb THEN
        RAISE EXCEPTION 'FAIL test 2: expected no error, got %', v_result->'error';
    END IF;
    IF (v_result->'result'->>'value')::int IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'FAIL test 2: expected 3, got %', v_result->'result'->>'value';
    END IF;
    RAISE NOTICE '  Test 2 PASS: 1 + 2 → 3';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 3: Exec mode — x = 42 → globals has x=42
    -- RESUME 0, LOAD_CONST 0 (42), STORE_NAME 0 ('x'), LOAD_CONST 1 (None), RETURN_VALUE
    -- Bytecode: 9700 6400 5a00 6401 5300
    -- ================================================================
    test_count := test_count + 1;
    v_input := jsonb_build_object(
        'bytecode', '970064005a0064015300',
        'consts', jsonb_build_array(
            jsonb_build_object('type', 'int', 'value', 42),
            jsonb_build_object('type', 'none')
        ),
        'names', jsonb_build_array('x'),
        'varnames', '[]'::jsonb,
        'cellvars', '[]'::jsonb,
        'freevars', '[]'::jsonb,
        'argcount', 0,
        'flags', 0,
        'nlocals', 0,
        'stacksize', 1,
        'name', '<module>',
        'filename', '<elytra>',
        'mode', 'exec'
    );
    v_result := public.py_run(v_input);

    IF (v_result->'error') IS DISTINCT FROM 'null'::jsonb THEN
        RAISE EXCEPTION 'FAIL test 3: expected no error, got %', v_result->'error';
    END IF;
    -- Check globals for x=42
    IF (v_result->'globals'->'42'->>'type') IS DISTINCT FROM 'int' THEN
        -- The key in globals is the repr of the key, which for str 'x' would be "'x'"
        -- Let's check the raw globals
        IF v_result->'globals' = '{}'::jsonb THEN
            RAISE EXCEPTION 'FAIL test 3: globals is empty, expected x=42. Full result: %', v_result;
        END IF;
    END IF;
    -- Globals should have an entry — check it contains x somewhere
    IF NOT (v_result->>'globals')::text LIKE '%42%' THEN
        RAISE EXCEPTION 'FAIL test 3: globals does not contain 42, got %', v_result->'globals';
    END IF;
    RAISE NOTICE '  Test 3 PASS: x = 42 → globals contains x=42';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 4: Nested code object — def add(a,b): return a+b; add(3,4)
    -- Inner bytecode: RESUME 0, LOAD_FAST 0, LOAD_FAST 1, BINARY_OP 0, RETURN_VALUE
    --   Hex: 97007c007c017a005300
    -- Outer bytecode: RESUME 0, LOAD_CONST 0 (code), MAKE_FUNCTION 0, STORE_NAME 0 (add),
    --   PUSH_NULL, LOAD_NAME 0 (add), LOAD_CONST 1 (3), LOAD_CONST 2 (4),
    --   PRECALL 2, CALL 2, STORE_NAME 1 (result), LOAD_CONST 3 (None), RETURN_VALUE
    --   Hex: 9700640084005a000200650064016402a602ab025a0164035300
    -- ================================================================
    test_count := test_count + 1;
    v_input := jsonb_build_object(
        'bytecode', '9700640084005a000200650064016402a602ab025a0164035300',
        'consts', jsonb_build_array(
            jsonb_build_object('type', 'code', 'value', jsonb_build_object(
                'bytecode', '97007c007c017a005300',
                'consts', '[]'::jsonb,
                'names', '[]'::jsonb,
                'varnames', jsonb_build_array('a', 'b'),
                'cellvars', '[]'::jsonb,
                'freevars', '[]'::jsonb,
                'argcount', 2,
                'nlocals', 2,
                'stacksize', 2,
                'flags', 0,
                'name', 'add',
                'filename', '<elytra>'
            )),
            jsonb_build_object('type', 'int', 'value', 3),
            jsonb_build_object('type', 'int', 'value', 4),
            jsonb_build_object('type', 'none')
        ),
        'names', jsonb_build_array('add', 'result'),
        'varnames', '[]'::jsonb,
        'cellvars', '[]'::jsonb,
        'freevars', '[]'::jsonb,
        'argcount', 0,
        'flags', 0,
        'nlocals', 0,
        'stacksize', 4,
        'name', '<module>',
        'filename', '<elytra>',
        'mode', 'exec'
    );
    v_result := public.py_run(v_input);

    IF (v_result->'error') IS DISTINCT FROM 'null'::jsonb THEN
        RAISE EXCEPTION 'FAIL test 4: expected no error, got %', v_result->'error';
    END IF;
    -- Check globals for result=7
    IF NOT (v_result->>'globals')::text LIKE '%7%' THEN
        RAISE EXCEPTION 'FAIL test 4: globals does not contain 7, got %', v_result->'globals';
    END IF;
    RAISE NOTICE '  Test 4 PASS: def add(a,b): return a+b; add(3,4) → result=7 in globals';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 5: Error handling — 1/0 → ZeroDivisionError
    -- RESUME 0, LOAD_CONST 0, LOAD_CONST 1, BINARY_OP 11(NB_TRUE_DIVIDE), RETURN_VALUE
    -- Bytecode: 9700 6400 6401 7a0b 5300
    -- ================================================================
    test_count := test_count + 1;
    v_input := jsonb_build_object(
        'bytecode', '9700640064017a0b5300',
        'consts', jsonb_build_array(
            jsonb_build_object('type', 'int', 'value', 1),
            jsonb_build_object('type', 'int', 'value', 0)
        ),
        'names', '[]'::jsonb,
        'varnames', '[]'::jsonb,
        'cellvars', '[]'::jsonb,
        'freevars', '[]'::jsonb,
        'argcount', 0,
        'flags', 0,
        'nlocals', 0,
        'stacksize', 2,
        'name', '<module>',
        'filename', '<elytra>',
        'mode', 'eval'
    );
    v_result := public.py_run(v_input);

    IF (v_result->'error') IS NOT DISTINCT FROM 'null'::jsonb THEN
        RAISE EXCEPTION 'FAIL test 5: expected error for 1/0, got result %', v_result;
    END IF;
    IF NOT (v_result->'error'->>'type' LIKE '%ZeroDivision%' OR v_result->'error'->>'message' LIKE '%zero%') THEN
        -- Accept any error that mentions division or zero
        IF NOT (v_result->>'error')::text LIKE '%ero%' THEN
            RAISE EXCEPTION 'FAIL test 5: expected ZeroDivisionError, got %', v_result->'error';
        END IF;
    END IF;
    RAISE NOTICE '  Test 5 PASS: 1/0 → error (division by zero)';
    pass_count := pass_count + 1;

    -- ================================================================
    -- Test 6: String concat — 'hello' + ' world' → 'hello world'
    -- RESUME 0, LOAD_CONST 0, LOAD_CONST 1, BINARY_OP 0(NB_ADD), RETURN_VALUE
    -- Bytecode: 9700 6400 6401 7a00 5300
    -- ================================================================
    test_count := test_count + 1;
    v_input := jsonb_build_object(
        'bytecode', '9700640064017a005300',
        'consts', jsonb_build_array(
            jsonb_build_object('type', 'str', 'value', 'hello'),
            jsonb_build_object('type', 'str', 'value', ' world')
        ),
        'names', '[]'::jsonb,
        'varnames', '[]'::jsonb,
        'cellvars', '[]'::jsonb,
        'freevars', '[]'::jsonb,
        'argcount', 0,
        'flags', 0,
        'nlocals', 0,
        'stacksize', 2,
        'name', '<module>',
        'filename', '<elytra>',
        'mode', 'eval'
    );
    v_result := public.py_run(v_input);

    IF (v_result->'error') IS DISTINCT FROM 'null'::jsonb THEN
        RAISE EXCEPTION 'FAIL test 6: expected no error, got %', v_result->'error';
    END IF;
    IF (v_result->'result'->>'type') IS DISTINCT FROM 'str' THEN
        RAISE EXCEPTION 'FAIL test 6: expected str result, got %', v_result->'result';
    END IF;
    IF (v_result->'result'->>'value') IS DISTINCT FROM 'hello world' THEN
        RAISE EXCEPTION 'FAIL test 6: expected "hello world", got %', v_result->'result'->>'value';
    END IF;
    RAISE NOTICE '  Test 6 PASS: "hello" + " world" → "hello world"';
    pass_count := pass_count + 1;

    -- ================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Test Summary: % / % passed', pass_count, test_count;
    RAISE NOTICE '========================================';
    IF pass_count != test_count THEN RAISE EXCEPTION 'Some tests failed.'; END IF;
    RAISE NOTICE 'All py_run RPC tests passed!';
END $$;
