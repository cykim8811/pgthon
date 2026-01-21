-- =====================================================
-- Migration: Assembler Newline Normalization
-- Description: Make vm_assemble resilient to sources that
--              contain literal "\\n" sequences (common when
--              passing SQL string literals) by normalizing
--              them into real newlines before parsing.
-- =====================================================

CREATE OR REPLACE FUNCTION public.vm_assemble(p_source text, p_name text DEFAULT '<module>')
RETURNS uuid AS $$
DECLARE
    v_lines text[];
    v_line text;
    v_parts text[];
    v_opcode text;
    v_arg text;

    -- Temporary text pools for deduplication
    v_consts_txt text[] := ARRAY[]::text[];
    v_varnames_txt text[] := ARRAY[]::text[];

    -- Final UUID pools
    v_consts uuid[] := ARRAY[]::uuid[];
    v_varnames uuid[] := ARRAY[]::uuid[];

    v_new_bytecode text := '';
    v_idx integer;

    v_code_id uuid := gen_random_uuid();
    v_consts_tuple_id uuid;
    v_varnames_tuple_id uuid;

    v_obj_id uuid;
    v_item text;

    -- Type IDs
    ID_TUP_TYPE uuid := '00000000-0000-4000-a000-000000000007';
    ID_CODE_TYPE uuid := '00000000-0000-4000-a000-000000000011';

    base_c uuid := gen_random_uuid();
    base_v uuid := gen_random_uuid();

    -- Normalized source
    v_source text;
BEGIN
    -- Normalize Windows newlines and literal "\n" sequences
    v_source := replace(p_source, E'\r\n', E'\n');
    v_source := replace(v_source, E'\\n', E'\n');

    v_lines := regexp_split_to_array(v_source, E'\n');

    FOREACH v_line IN ARRAY v_lines LOOP
        v_line := trim(v_line);
        -- Skip empty lines and comments
        IF length(v_line) > 0 AND substring(v_line from 1 for 1) <> '#' THEN
            v_parts := regexp_split_to_array(v_line, '\s+');
            v_opcode := v_parts[1];

            IF array_length(v_parts, 1) > 1 THEN
                v_arg := v_parts[2];
                v_idx := NULL;

                -- LOAD_CONST: Handle deduplication
                IF v_opcode = 'LOAD_CONST' THEN
                    v_idx := array_position(v_consts_txt, v_arg);
                    IF v_idx IS NULL THEN
                        v_consts_txt := array_append(v_consts_txt, v_arg);
                        v_idx := array_length(v_consts_txt, 1);
                    END IF;
                    -- Convert 1-based array index to 0-based opcode argument
                    v_new_bytecode := v_new_bytecode || v_opcode || ' ' || (v_idx - 1) || E'\n';

                -- LOAD_FAST, STORE_FAST: Handle deduplication
                ELSIF v_opcode IN ('LOAD_FAST', 'STORE_FAST') THEN
                    v_idx := array_position(v_varnames_txt, v_arg);
                    IF v_idx IS NULL THEN
                        v_varnames_txt := array_append(v_varnames_txt, v_arg);
                        v_idx := array_length(v_varnames_txt, 1);
                    END IF;
                    v_new_bytecode := v_new_bytecode || v_opcode || ' ' || (v_idx - 1) || E'\n';

                -- LOAD_ATTR, STORE_ATTR: Use varnames pool for simplicity
                ELSIF v_opcode IN ('LOAD_ATTR', 'STORE_ATTR') THEN
                    v_idx := array_position(v_varnames_txt, v_arg);
                    IF v_idx IS NULL THEN
                        v_varnames_txt := array_append(v_varnames_txt, v_arg);
                        v_idx := array_length(v_varnames_txt, 1);
                    END IF;
                    v_new_bytecode := v_new_bytecode || v_opcode || ' ' || (v_idx - 1) || E'\n';

                ELSE
                    -- Jumps or other opcodes with direct integer args
                    v_new_bytecode := v_new_bytecode || v_opcode || ' ' || v_arg || E'\n';
                END IF;
            ELSE
                -- No argument opcodes
                v_new_bytecode := v_new_bytecode || v_opcode || E'\n';
            END IF;
        END IF;
    END LOOP;

    -- Convert text pools to UUID pools
    -- 1. Constants
    IF array_length(v_consts_txt, 1) > 0 THEN
        FOREACH v_item IN ARRAY v_consts_txt LOOP
            v_obj_id := public.vm_assembler_get_or_create_const(v_item);
            v_consts := array_append(v_consts, v_obj_id);
        END LOOP;
    END IF;

    -- 2. Variable Names
    IF array_length(v_varnames_txt, 1) > 0 THEN
        FOREACH v_item IN ARRAY v_varnames_txt LOOP
            v_obj_id := public.vm_create_str(v_item);
            v_varnames := array_append(v_varnames, v_obj_id);
        END LOOP;
    END IF;

    -- Create Tuple Objects
    INSERT INTO public.py_object (id, ob_type) VALUES (base_c, ID_TUP_TYPE);
    v_consts_tuple_id := gen_random_uuid();
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item) VALUES (v_consts_tuple_id, base_c, v_consts);

    INSERT INTO public.py_object (id, ob_type) VALUES (base_v, ID_TUP_TYPE);
    v_varnames_tuple_id := gen_random_uuid();
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item) VALUES (v_varnames_tuple_id, base_v, v_varnames);

    -- Create Code Object with Base ID
    INSERT INTO public.py_object (id, ob_type) VALUES (v_code_id, ID_CODE_TYPE);
    INSERT INTO public.py_code_object (
        id, ob_base, co_name, co_code, co_consts, co_varnames, co_argcount
    )
    VALUES (
        gen_random_uuid(), v_code_id, p_name, v_new_bytecode,
        base_c, base_v, 0
    );

    RETURN v_code_id;
END;
$$ LANGUAGE plpgsql;

