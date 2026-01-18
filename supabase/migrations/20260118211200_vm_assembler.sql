-- =====================================================
-- Migration: VM Assembler
-- Description: Assemble text bytecode into executable code objects
-- =====================================================

-------------------------------------------------------
-- Helper: Create or get constant object
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_assembler_get_or_create_const(p_val_str text)
RETURNS uuid AS $$
DECLARE
    v_id uuid;
    v_base uuid;
    v_int_val bigint;
    
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
BEGIN
    -- Try to parse as integer
    BEGIN
        v_int_val := p_val_str::bigint;
        RETURN public.vm_create_int(v_int_val);
    EXCEPTION WHEN OTHERS THEN
        -- If not integer, treat as string
        RETURN public.vm_create_str(p_val_str);
    END;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- Main Assembler Function
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_assemble(p_source text, p_name text DEFAULT '<module>')
RETURNS uuid AS $$
DECLARE
    v_lines text[];
    v_line text;
    v_parts text[];
    v_opcode text;
    v_arg text;
    
    v_consts uuid[] := ARRAY[]::uuid[];
    v_varnames uuid[] := ARRAY[]::uuid[];
    v_names uuid[] := ARRAY[]::uuid[];
    
    v_new_bytecode text := '';
    v_idx integer;
    
    v_code_id uuid := gen_random_uuid();
    v_consts_tuple_id uuid;
    v_varnames_tuple_id uuid;
    
    v_obj_id uuid;
    
    -- Type IDs
    ID_TUP_TYPE uuid := '00000000-0000-4000-a000-000000000007';
    ID_CODE_TYPE uuid := '00000000-0000-4000-a000-000000000011';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    
    base_c uuid := gen_random_uuid();
    base_v uuid := gen_random_uuid();
BEGIN
    v_lines := regexp_split_to_array(p_source, '\n');
    
    -----------------------------------------------------------------
    -- FIRST PASS: Parse and build constant/varname pools
    -----------------------------------------------------------------
    FOREACH v_line IN ARRAY v_lines LOOP
        v_line := trim(v_line);
        
        -- Skip empty lines and comments
        IF length(v_line) > 0 AND substring(v_line from 1 for 1) <> '#' THEN
            v_parts := regexp_split_to_array(v_line, '\s+');
            v_opcode := v_parts[1];
            
            -- If opcode has argument
            IF array_length(v_parts, 1) > 1 THEN
                v_arg := v_parts[2];
                
                -------------------------------------------------
                -- LOAD_CONST: Add to consts pool
                -------------------------------------------------
                IF v_opcode = 'LOAD_CONST' THEN
                    v_obj_id := public.vm_assembler_get_or_create_const(v_arg);
                    v_consts := array_append(v_consts, v_obj_id);
                    v_idx := array_length(v_consts, 1) - 1; -- 0-based index
                    
                    v_new_bytecode := v_new_bytecode || v_opcode || ' ' || v_idx || E'\n';
                    
                -------------------------------------------------
                -- LOAD_FAST / STORE_FAST: Add to varnames pool
                -------------------------------------------------
                ELSIF v_opcode IN ('LOAD_FAST', 'STORE_FAST') THEN
                    -- Create string object for variable name
                    v_obj_id := public.vm_create_str(v_arg);
                    v_varnames := array_append(v_varnames, v_obj_id);
                    v_idx := array_length(v_varnames, 1) - 1;
                    
                    v_new_bytecode := v_new_bytecode || v_opcode || ' ' || v_idx || E'\n';
                    
                -------------------------------------------------
                -- LOAD_ATTR / STORE_ATTR: Add to varnames pool (or names)
                -------------------------------------------------
                ELSIF v_opcode IN ('LOAD_ATTR', 'STORE_ATTR') THEN
                    v_obj_id := public.vm_create_str(v_arg);
                    v_varnames := array_append(v_varnames, v_obj_id); -- Using varnames for simplicity
                    v_idx := array_length(v_varnames, 1) - 1;
                    
                    v_new_bytecode := v_new_bytecode || v_opcode || ' ' || v_idx || E'\n';

                -------------------------------------------------
                -- Other opcodes with integer arguments (jumps, etc.)
                -------------------------------------------------
                ELSE
                    v_new_bytecode := v_new_bytecode || v_opcode || ' ' || v_arg || E'\n';
                END IF;
            ELSE
                -- No argument opcodes (RETURN_VALUE, POP_TOP, etc.)
                v_new_bytecode := v_new_bytecode || v_opcode || E'\n';
            END IF;
        END IF;
    END LOOP;
    
    -----------------------------------------------------------------
    -- Create Tuple Objects for consts and varnames
    -----------------------------------------------------------------
    
    -- Consts Tuple
    INSERT INTO public.py_object (id, ob_type) VALUES (base_c, ID_TUP_TYPE);
    v_consts_tuple_id := gen_random_uuid();
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item) 
    VALUES (v_consts_tuple_id, base_c, v_consts);
    
    -- Varnames Tuple
    INSERT INTO public.py_object (id, ob_type) VALUES (base_v, ID_TUP_TYPE);
    v_varnames_tuple_id := gen_random_uuid();
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item) 
    VALUES (v_varnames_tuple_id, base_v, v_varnames);
    
    -----------------------------------------------------------------
    -- Create Code Object
    -----------------------------------------------------------------
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

