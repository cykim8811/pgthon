-- ============================================================================
-- F-String Opcodes (CPython 3.11)
-- FORMAT_VALUE(155), BUILD_STRING(157)
-- ============================================================================

-- FORMAT_VALUE(flags): Format a value for f-string interpolation.
-- flags bit layout:
--   bits 0-1 (flags & 0x03): conversion — 0=none, 1=str(), 2=repr(), 3=ascii()
--   bit 2 (flags & 0x04): has format spec on stack (popped first)
-- Implementation: pop optional format spec, pop value, apply conversion, push result str.
CREATE OR REPLACE FUNCTION public.py_opcode_FORMAT_VALUE(frame_id UUID, flags INTEGER)
RETURNS VOID AS $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    conversion int;
    has_fmt_spec boolean;
    fmt_spec_id uuid;
    value_id uuid;
    result_id uuid;
    v_type_id uuid;
BEGIN
    conversion := flags & 3;        -- bits 0-1
    has_fmt_spec := (flags & 4) != 0; -- bit 2

    -- If format spec is on the stack, pop it (and discard — not implemented)
    IF has_fmt_spec THEN
        fmt_spec_id := public.py_stack_pop(frame_id);
    END IF;

    -- Pop the value to format
    value_id := public.py_stack_pop(frame_id);

    -- Apply conversion
    CASE conversion
        WHEN 0 THEN
            -- FVC_NONE: if already str, use as-is; otherwise call str()
            SELECT ob_type INTO v_type_id FROM public.py_object WHERE id = value_id;
            IF v_type_id = ID_STR_TYPE THEN
                result_id := value_id;
            ELSE
                result_id := public.py_object_str(value_id);
            END IF;
        WHEN 1 THEN
            -- FVC_STR: always call str()
            result_id := public.py_object_str(value_id);
        WHEN 2 THEN
            -- FVC_REPR: call repr()
            result_id := public.py_object_repr(value_id);
        WHEN 3 THEN
            -- FVC_ASCII: call ascii() — fallback to repr() (ascii not yet implemented)
            result_id := public.py_object_repr(value_id);
        ELSE
            RAISE EXCEPTION 'FORMAT_VALUE: unknown conversion %', conversion;
    END CASE;

    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;

-- BUILD_STRING(count): Pop count string objects, concatenate them, push the result.
-- Used to assemble f-strings from literal parts and formatted values.
CREATE OR REPLACE FUNCTION public.py_opcode_BUILD_STRING(frame_id UUID, count INTEGER)
RETURNS VOID AS $$
DECLARE
    parts uuid[] := '{}';
    i integer;
    elem_id uuid;
    elem_text text;
    result_text text := '';
    result_id uuid;
BEGIN
    IF count < 0 THEN
        RAISE EXCEPTION 'BUILD_STRING: count must be non-negative, got %', count;
    END IF;

    -- Pop count items in reverse order (first popped = last in string)
    FOR i IN 1..count LOOP
        elem_id := public.py_stack_pop(frame_id);
        parts := array_prepend(elem_id, parts);
    END LOOP;

    -- Concatenate all string values
    FOR i IN 1..COALESCE(array_length(parts, 1), 0) LOOP
        SELECT str_value INTO elem_text FROM public.py_unicode_object WHERE ob_base = parts[i];
        result_text := result_text || COALESCE(elem_text, '');
    END LOOP;

    -- Create new str object from concatenated text
    result_id := public.py_str_from_text(result_text);
    PERFORM public.py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
