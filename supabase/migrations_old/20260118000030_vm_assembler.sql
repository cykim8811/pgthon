-- Migration: VM Assembler (Step 9)
-- Created at: 2026-01-18 00:00:30

-------------------------------------------------------
-- Helper: Parse and Create Consts
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_assembler_get_or_create_const(p_val_str TEXT)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_base UUID;
    v_int_val BIGINT;
    
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
BEGIN
    -- Try integer
    BEGIN
        v_int_val := p_val_str::BIGINT;
        
        -- Check if exists (Optional optimization, skip for now)
        v_base := gen_random_uuid();
        v_id := gen_random_uuid();
        
        INSERT INTO public.py_object (id, ob_type) VALUES (v_base, ID_INT_TYPE);
        INSERT INTO public.py_long_object (id, ob_base, long_value) VALUES (v_id, v_base, v_int_val);
        
        RETURN v_base;
    EXCEPTION WHEN OTHERS THEN
        -- String
        v_base := gen_random_uuid();
        v_id := gen_random_uuid();
        
        INSERT INTO public.py_object (id, ob_type) VALUES (v_base, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (v_id, v_base, p_val_str);
        
        RETURN v_base;
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-------------------------------------------------------
-- Assembler Function
-- Input: Assembly Text (e.g. "LOAD_CONST 10\nRETURN_VALUE")
-- Output: Code Object ID
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_assemble(p_source TEXT, p_name TEXT DEFAULT '<module>')
RETURNS UUID AS $$
DECLARE
    v_lines TEXT[];
    v_line TEXT;
    v_parts TEXT[];
    v_opcode TEXT;
    v_arg TEXT;
    
    v_consts UUID[] := ARRAY[]::UUID[];
    v_varnames UUID[] := ARRAY[]::UUID[]; -- We'll store strings here
    v_names UUID[] := ARRAY[]::UUID[];    -- Attributes/Global names
    
    v_new_bytecode TEXT := '';
    v_idx INTEGER;
    
    v_code_id UUID := gen_random_uuid();
    v_consts_tuple_id UUID;
    v_varnames_tuple_id UUID;
    
    v_obj_id UUID;
    
    v_line_idx INTEGER := 0;
    
    -- IDs
    ID_TUP_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
BEGIN
    v_lines := regexp_split_to_array(p_source, '\n');
    
    FOREACH v_line IN ARRAY v_lines LOOP
        v_line := trim(v_line);
        IF length(v_line) > 0 AND substring(v_line from 1 for 1) <> '#' THEN
            v_parts := regexp_split_to_array(v_line, '\s+');
            v_opcode := v_parts[1];
            
            -- If opcode has argument
            IF array_length(v_parts, 1) > 1 THEN
                v_arg := v_parts[2];
                
                -- Handle Opcode Argument Types
                IF v_opcode = 'LOAD_CONST' THEN
                    -- Create Const Object
                    v_obj_id := public.vm_assembler_get_or_create_const(v_arg);
                    v_consts := array_append(v_consts, v_obj_id);
                    v_idx := array_length(v_consts, 1) - 1; -- 0-based index
                    
                    v_new_bytecode := v_new_bytecode || v_opcode || ' ' || v_idx || E'\n';
                    
                ELSIF v_opcode = 'LOAD_FAST' OR v_opcode = 'STORE_FAST' THEN
                    -- Varname (String)
                    -- Check if already in varnames
                    v_idx := -1;
                    IF array_length(v_varnames, 1) IS NOT NULL THEN
                        FOR i IN 1..array_length(v_varnames, 1) LOOP
                             -- Inefficient lookup but okay for MVP
                             -- Actually we store UUIDs in varnames array.
                             -- We need the string value.
                             -- Let's just create new string object for each for now (duplicate strings allowed in pool)
                             -- Or better: reusing strings is hard without map.
                             -- Just append.
                             NULL;
                        END LOOP;
                    END IF;
                    
                    v_obj_id := public.vm_assembler_get_or_create_const(v_arg); -- Create string object
                    v_varnames := array_append(v_varnames, v_obj_id);
                    v_idx := array_length(v_varnames, 1) - 1;
                    
                    v_new_bytecode := v_new_bytecode || v_opcode || ' ' || v_idx || E'\n';
                    
                ELSIF v_opcode = 'LOAD_ATTR' OR v_opcode = 'STORE_ATTR' THEN
                     -- Attribute Name (use varnames tuple for storage in our VM implementation for now, or names)
                     -- Our VM uses varnames for attrs currently (see Step 7).
                     v_obj_id := public.vm_assembler_get_or_create_const(v_arg);
                     v_varnames := array_append(v_varnames, v_obj_id); -- Using varnames pool
                     v_idx := array_length(v_varnames, 1) - 1;
                     
                     v_new_bytecode := v_new_bytecode || v_opcode || ' ' || v_idx || E'\n';

                ELSE
                    -- Integer Argument (Jumps, Compare Ops, etc.)
                    v_new_bytecode := v_new_bytecode || v_opcode || ' ' || v_arg || E'\n';
                END IF;
            ELSE
                -- No Arg (RETURN_VALUE, POP_TOP, etc.)
                 v_new_bytecode := v_new_bytecode || v_opcode || E'\n';
            END IF;
        END IF;
    END LOOP;
    
    -- Create Tuple Objects for consts/varnames
    v_consts_tuple_id := gen_random_uuid();
    v_varnames_tuple_id := gen_random_uuid();
    
    DECLARE
        base_c UUID := gen_random_uuid();
        base_v UUID := gen_random_uuid();
    BEGIN
        -- Consts Tuple
        INSERT INTO public.py_object (id, ob_type) VALUES (base_c, ID_TUP_TYPE);
        INSERT INTO public.py_tuple_object (id, ob_base, ob_item) VALUES (v_consts_tuple_id, base_c, v_consts);
        
        -- Varnames Tuple
        INSERT INTO public.py_object (id, ob_type) VALUES (base_v, ID_TUP_TYPE);
        INSERT INTO public.py_tuple_object (id, ob_base, ob_item) VALUES (v_varnames_tuple_id, base_v, v_varnames);
        
        -- Create Code Object
        INSERT INTO public.py_object (id, ob_type) VALUES (v_code_id, NULL);
        INSERT INTO public.py_code_object (id, ob_base, co_name, co_code, co_consts, co_varnames)
        VALUES (v_code_id, v_code_id, p_name, v_new_bytecode, base_c, base_v);
    END;
    
    RETURN v_code_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
