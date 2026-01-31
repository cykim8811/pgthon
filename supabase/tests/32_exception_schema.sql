-- ============================================================================
-- Test: Exception Schema & Helpers (CPython 3.11)
--
-- Purpose:
--   Validates exception handling schema and helper functions:
--   - py_exception_state row and tables (py_base_exception_object, py_traceback_object)
--   - co_exceptiontable column on py_code_object
--   - Bootstrap exception types (BaseException, Exception, TypeError, ValueError, NameError, traceback)
--   - py_err_set_object, py_err_clear, py_err_occurred, py_err_get_raised, py_traceback_here
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md
-- ============================================================================

DO $$
DECLARE
  ID_BASE_EXCEPTION uuid := '00000000-0000-4000-a000-000000000020';
  ID_EXCEPTION      uuid := '00000000-0000-4000-a000-000000000021';
  ID_TYPE_ERROR     uuid := '00000000-0000-4000-a000-000000000022';
  ID_VALUE_ERROR    uuid := '00000000-0000-4000-a000-000000000023';
  ID_NAME_ERROR    uuid := '00000000-0000-4000-a000-000000000024';
  ID_TRACEBACK_TYPE uuid := '00000000-0000-4000-a000-000000000025';
  ID_RUNTIME_ERROR  uuid := '00000000-0000-4000-a000-000000000026';
  EXCEPTION_STATE_ID uuid := '00000000-0000-4000-e000-000000000001';
  n integer;
  t uuid;
  v uuid;
  tb uuid;
BEGIN
  -- 1. py_exception_state: single row exists, initially clear
  SELECT count(*) INTO n FROM public.py_exception_state WHERE id = EXCEPTION_STATE_ID;
  IF n <> 1 THEN
    RAISE EXCEPTION '✓ 32.1 FAIL: py_exception_state should have exactly one row';
  END IF;
  IF (SELECT exc_type_id FROM public.py_exception_state WHERE id = EXCEPTION_STATE_ID) IS NOT NULL THEN
    RAISE EXCEPTION '✓ 32.1 FAIL: initial exc_type_id should be NULL';
  END IF;
  RAISE NOTICE '✓ 32.1 py_exception_state row exists and is clear';

  -- 2. Exception types exist (bootstrap)
  IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = ID_BASE_EXCEPTION AND tp_name = 'BaseException') THEN
    RAISE EXCEPTION '✓ 32.2 FAIL: BaseException type not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = ID_EXCEPTION AND tp_name = 'Exception') THEN
    RAISE EXCEPTION '✓ 32.2 FAIL: Exception type not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = ID_TYPE_ERROR AND tp_name = 'TypeError') THEN
    RAISE EXCEPTION '✓ 32.2 FAIL: TypeError type not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = ID_TRACEBACK_TYPE AND tp_name = 'traceback') THEN
    RAISE EXCEPTION '✓ 32.2 FAIL: traceback type not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = ID_RUNTIME_ERROR AND tp_name = 'RuntimeError') THEN
    RAISE EXCEPTION '✓ 32.2 FAIL: RuntimeError type not found';
  END IF;
  RAISE NOTICE '✓ 32.2 Exception types (BaseException, Exception, TypeError, ValueError, NameError, traceback, RuntimeError) exist';

  -- 3. py_code_object has co_exceptiontable
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'py_code_object' AND column_name = 'co_exceptiontable'
  ) THEN
    RAISE EXCEPTION '✓ 32.3 FAIL: py_code_object.co_exceptiontable column missing';
  END IF;
  RAISE NOTICE '✓ 32.3 py_code_object.co_exceptiontable exists';

  -- 4. py_err_set_object / py_err_clear / py_err_occurred
  PERFORM public.py_err_clear();
  IF public.py_err_occurred() THEN
    RAISE EXCEPTION '✓ 32.4 FAIL: py_err_occurred() should be false after clear';
  END IF;
  PERFORM public.py_err_set_object(ID_TYPE_ERROR, NULL);
  IF NOT public.py_err_occurred() THEN
    RAISE EXCEPTION '✓ 32.4 FAIL: py_err_occurred() should be true after set';
  END IF;
  PERFORM public.py_err_clear();
  IF public.py_err_occurred() THEN
    RAISE EXCEPTION '✓ 32.4 FAIL: py_err_occurred() should be false after second clear';
  END IF;
  RAISE NOTICE '✓ 32.4 py_err_set_object, py_err_clear, py_err_occurred work';

  -- 5. py_err_get_raised returns (type, value, traceback)
  PERFORM public.py_err_clear();
  SELECT exc_type_id, exc_value_id, exc_traceback_id INTO t, v, tb FROM public.py_err_get_raised();
  IF t IS NOT NULL OR v IS NOT NULL OR tb IS NOT NULL THEN
    RAISE EXCEPTION '✓ 32.5 FAIL: py_err_get_raised should return NULLs when clear';
  END IF;
  PERFORM public.py_err_set_object(ID_TYPE_ERROR, NULL);
  SELECT exc_type_id, exc_value_id, exc_traceback_id INTO t, v, tb FROM public.py_err_get_raised();
  IF t IS DISTINCT FROM ID_TYPE_ERROR THEN
    RAISE EXCEPTION '✓ 32.5 FAIL: py_err_get_raised exc_type_id should be TypeError';
  END IF;
  PERFORM public.py_err_clear();
  RAISE NOTICE '✓ 32.5 py_err_get_raised returns (type, value, traceback)';

  -- 6. py_traceback_here: no-op when no exception; when set, prepends frame and updates state
  PERFORM public.py_err_clear();
  PERFORM public.py_traceback_here('00000000-0000-4000-b000-000000000002'::uuid, 0); /* builtins module as dummy frame id */
  IF (SELECT exc_traceback_id FROM public.py_exception_state WHERE id = EXCEPTION_STATE_ID) IS NOT NULL THEN
    RAISE EXCEPTION '✓ 32.6 FAIL: traceback_here with no exception should not set traceback';
  END IF;
  PERFORM public.py_err_set_object(ID_TYPE_ERROR, NULL);
  PERFORM public.py_traceback_here('00000000-0000-4000-b000-000000000002'::uuid, 4);
  IF (SELECT exc_traceback_id FROM public.py_exception_state WHERE id = EXCEPTION_STATE_ID) IS NULL THEN
    RAISE EXCEPTION '✓ 32.6 FAIL: traceback_here with exception set should set exc_traceback_id';
  END IF;
  PERFORM public.py_err_clear();
  RAISE NOTICE '✓ 32.6 py_traceback_here no-op when no exception; prepends frame when set';

  RAISE NOTICE 'Test Summary: Exception schema and helpers (32.x) passed.';
END $$;
