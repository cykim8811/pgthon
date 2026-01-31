-- ============================================================================
-- Exception table parsing (CPython 3.11 co_exceptiontable)
-- 20260114240900_exception_table_parsing.sql
--
-- Design: docs/EXCEPTION_HANDLING_DESIGN.md, CPython InternalDocs/exception_handling.md
-- Format: start, size, target, depth, push-lasti. Encoded as 6-bit varint per byte
-- (bit 6 = extend, bit 7 = start-of-entry on first byte). Offsets in code units (2 bytes).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- py_parse_exception_table: decode co_exceptiontable bytea -> (start, end, target, depth, lasti)
-- Returns one row per exception table entry. end = start + size.
-- NULL or empty bytea -> no rows.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_parse_exception_table(p_table bytea)
RETURNS TABLE(
  start_offset integer,
  end_offset integer,
  target_offset integer,
  depth integer,
  lasti boolean
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  pos integer := 0;
  len integer;
  b integer;
  v bigint;
  shift integer;
  entry_start integer;
  entry_size integer;
  entry_target integer;
  entry_dl integer;
BEGIN
  IF p_table IS NULL OR length(p_table) = 0 THEN
    RETURN;
  END IF;
  len := length(p_table);

  WHILE pos < len LOOP
    -- Read start: first byte of entry has MSB set, 7 bits of value (no extend for this field).
    IF pos >= len THEN RETURN; END IF;
    b := get_byte(p_table, pos);
    pos := pos + 1;
    entry_start := (b & 127)::integer;

    -- Read size
    v := 0;
    LOOP
      IF pos >= len THEN
        RETURN;
      END IF;
      b := get_byte(p_table, pos);
      pos := pos + 1;
      v := (v << 6) | (b & 63);
      EXIT WHEN (b & 64) = 0;
    END LOOP;
    entry_size := v::integer;

    -- Read target
    v := 0;
    LOOP
      IF pos >= len THEN
        RETURN;
      END IF;
      b := get_byte(p_table, pos);
      pos := pos + 1;
      v := (v << 6) | (b & 63);
      EXIT WHEN (b & 64) = 0;
    END LOOP;
    entry_target := v::integer;

    -- Read depth and lasti combined: (depth << 1) | lasti
    v := 0;
    LOOP
      IF pos >= len THEN
        RETURN;
      END IF;
      b := get_byte(p_table, pos);
      pos := pos + 1;
      v := (v << 6) | (b & 63);
      EXIT WHEN (b & 64) = 0;
    END LOOP;
    entry_dl := v::integer;

    start_offset := entry_start;
    end_offset := entry_start + entry_size;
    target_offset := entry_target;
    depth := entry_dl >> 1;
    lasti := (entry_dl & 1) <> 0;
    RETURN NEXT;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.py_parse_exception_table(bytea) IS
  'Parse CPython 3.11 co_exceptiontable bytea into (start, end, target, depth, lasti). Offsets in code units.';

-- ----------------------------------------------------------------------------
-- py_get_exception_handler: find handler for instruction offset
-- Returns (target_offset, depth, lasti) if start <= offset < end, else no row.
-- Binary search not required for small tables; linear scan.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.py_get_exception_handler(p_table bytea, p_offset integer)
RETURNS TABLE(target_offset integer, depth integer, lasti boolean)
LANGUAGE sql
STABLE
AS $$
  SELECT e.target_offset, e.depth, e.lasti
  FROM public.py_parse_exception_table(p_table) e
  WHERE e.start_offset <= p_offset AND p_offset < e.end_offset
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.py_get_exception_handler(bytea, integer) IS
  'Find exception handler for instruction offset. Returns at most one row (target, depth, lasti).';
