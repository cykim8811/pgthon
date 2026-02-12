-- ============================================================================
-- Test: Exception Table Parsing (CPython 3.11 co_exceptiontable)
--
-- Purpose:
--   Validates py_parse_exception_table and py_get_exception_handler.
--   Uses the example from CPython InternalDocs/exception_handling.md:
--   start=20, size=8, target=100, depth=3, lasti=False
--   Encoded: 148, 8, 65, 36, 6 (5 bytes)
-- ============================================================================

DO $$
DECLARE
  -- Example from InternalDocs: start=20, size=8, target=100, depth=3, lasti=False
  -- Encoded: 148 (MSB+20), 8 (size), 65 (extend+1), 36 (100 = (1<<6)+36), 6 (depth<<1+lasti)
  tab bytea;  -- 148, 8, 65, 36, 6 (0x94, 0x08, 0x41, 0x24, 0x06)
  r record;
  n integer := 0;
BEGIN
  tab := decode('9408412406', 'hex');  -- 148, 8, 65, 36, 6

  -- 33.1 Parse returns one row
  FOR r IN SELECT * FROM public.py_parse_exception_table(tab) LOOP
    n := n + 1;
    IF r.start_offset <> 20 OR r.end_offset <> 28 OR r.target_offset <> 100 OR r.depth <> 3 OR r.lasti <> FALSE THEN
      RAISE EXCEPTION '✓ 33.1 FAIL: parsed (%, %, %, %, %) expected (20, 28, 100, 3, false)',
        r.start_offset, r.end_offset, r.target_offset, r.depth, r.lasti;
    END IF;
  END LOOP;
  IF n <> 1 THEN
    RAISE EXCEPTION '✓ 33.1 FAIL: expected 1 row, got %', n;
  END IF;
  RAISE NOTICE '✓ 33.1 py_parse_exception_table decodes example entry';

  -- 33.2 get_exception_handler: offset in [20,28) returns (100, 3, false)
  SELECT target_offset, depth, lasti INTO r FROM public.py_get_exception_handler(tab, 20);
  IF r.target_offset <> 100 OR r.depth <> 3 OR r.lasti <> FALSE THEN
    RAISE EXCEPTION '✓ 33.2 FAIL: handler(20) expected (100, 3, false) got (%, %, %)', r.target_offset, r.depth, r.lasti;
  END IF;
  SELECT target_offset, depth, lasti INTO r FROM public.py_get_exception_handler(tab, 27);
  IF r.target_offset <> 100 OR r.depth <> 3 OR r.lasti <> FALSE THEN
    RAISE EXCEPTION '✓ 33.2 FAIL: handler(27) expected (100, 3, false)';
  END IF;

  -- 33.3 offset outside [20,28) returns no row
  SELECT target_offset INTO r FROM public.py_get_exception_handler(tab, 19);
  IF FOUND THEN
    RAISE EXCEPTION '✓ 33.3 FAIL: handler(19) should return no row';
  END IF;
  SELECT target_offset INTO r FROM public.py_get_exception_handler(tab, 28);
  IF FOUND THEN
    RAISE EXCEPTION '✓ 33.3 FAIL: handler(28) should return no row';
  END IF;
  RAISE NOTICE '✓ 33.2–33.3 py_get_exception_handler lookup correct';

  -- 33.4 NULL/empty table returns no rows
  n := 0;
  FOR r IN SELECT * FROM public.py_parse_exception_table(NULL) LOOP
    n := n + 1;
  END LOOP;
  IF n <> 0 THEN
    RAISE EXCEPTION '✓ 33.4 FAIL: parse(NULL) should return 0 rows';
  END IF;
  n := 0;
  FOR r IN SELECT * FROM public.py_parse_exception_table(''::bytea) LOOP
    n := n + 1;
  END LOOP;
  IF n <> 0 THEN
    RAISE EXCEPTION '✓ 33.4 FAIL: parse(empty) should return 0 rows';
  END IF;
  RAISE NOTICE '✓ 33.4 NULL/empty table returns no rows';

  RAISE NOTICE 'Test Summary: Exception table parsing (33.x) passed.';
END $$;
