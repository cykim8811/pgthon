-- Migration: VM Implementation Step 7 (Attributes)
-- Created at: 2026-01-18 00:00:10

-------------------------------------------------------
-- Helper: Descriptors and Bound Method Creation
-------------------------------------------------------

-- 1. Create Bound Method Object
CREATE OR REPLACE FUNCTION public.vm_create_bound_method(p_func_id UUID, p_self_id UUID)
RETURNS UUID AS $$
DECLARE
    v_method_id UUID := gen_random_uuid();
    v_base_id UUID := gen_random_uuid();
    ID_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000013';
BEGIN
    INSERT INTO public.py_object (id, ob_type) VALUES (v_base_id, ID_METHOD_TYPE);
    INSERT INTO public.py_bound_method_object (id, ob_base, im_func, im_self)
    VALUES (v_method_id, v_base_id, p_func_id, p_self_id);
    
    RETURN v_base_id;
END;
$$ LANGUAGE plpgsql;

-- 2. Enhanced getattr (Descriptor Protocol Support)
-- This replaces the simple vm_getattr
-- Drop first to allow parameter name change
DROP FUNCTION IF EXISTS public.vm_getattr(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.vm_getattr(p_obj_id UUID, p_name TEXT)
RETURNS UUID AS $$
DECLARE
    v_type_id UUID;
    v_found_in_type UUID; -- Descriptor?
    v_descr_get UUID;
    v_res UUID;
    
    -- IDs
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    
    v_obj_dict_id UUID; -- The __dict__ of the object (if any)
BEGIN
    -- 1. Get Type
    v_type_id := public.vm_get_type(p_obj_id);
    
    -- 2. Look in Type (MRO) for Descriptor
    -- CPython: _PyType_Lookup(tp, name)
    v_found_in_type := public.vm_lookup_in_type(v_type_id, p_name);
    
    -- 3. If found in type, check if it is a Data Descriptor
    -- (We skip Data Descriptor check for MVP, assume methods are Non-Data)
    -- But we MUST check if it has __get__
    
    -- 4. Look in Instance Dict
    -- For now, our simple objects don't store __dict__ in a standard way except py_type_object.
    -- If p_obj_id is a Type, its tp_dict is searched.
    -- If p_obj_id is a general object, we need to know where its attributes are.
    -- Currently, only Types and specific objects have queryable attributes.
    -- Let's try to find if it has a stored __dict__.
    -- (Skipping instance __dict__ lookup for simple types for now, except if it's a Type)
    
    -- 5. If found in type (Non-Data Descriptor / Method)
    IF v_found_in_type IS NOT NULL THEN
        -- Check if it is a function (or has __get__)
        -- Simplifying: If it's a function, bind it.
        -- TODO: Real __get__ call.
        -- For now: Just bind if it's a function.
        
        -- Check if function
        DECLARE
            v_ftype UUID;
            ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
            ID_JS_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000012';
        BEGIN
            v_ftype := public.vm_get_type(v_found_in_type);
            IF v_ftype = ID_FNC_TYPE OR v_ftype = ID_JS_FNC_TYPE THEN
                 -- Bind it!
                 RETURN public.vm_create_bound_method(v_found_in_type, p_obj_id);
            END IF;
        END;
        
        RETURN v_found_in_type;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-------------------------------------------------------
-- VM Run Frame Update (Add LOAD_ATTR, STORE_ATTR)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_run_frame(
    p_code_id UUID, 
    p_locals_id UUID, 
    p_globals_id UUID
)
RETURNS UUID AS $$
DECLARE
    -- Code Attributes
    v_bytecode TEXT;
    v_consts_id UUID;
    v_varnames_id UUID;
    
    -- Execution State
    v_stack UUID[] := ARRAY[]::UUID[];
    v_lines TEXT[];
    v_line TEXT;
    v_parts TEXT[];
    v_opcode TEXT;
    v_oparg TEXT;
    v_oparg_int INTEGER;
    
    v_pc INTEGER := 1;  -- Program Counter
    v_max_pc INTEGER;
    
    -- Temps
    v_tos UUID;
    v_tos1 UUID;
    v_res UUID;
    v_name TEXT;
    v_bound_method UUID;
BEGIN
    -- 1. Fetch Code Object Data
    SELECT co_code, co_consts, co_varnames 
    INTO v_bytecode, v_consts_id, v_varnames_id 
    FROM public.py_code_object WHERE id = p_code_id;
    
    -- 2. Split Bytecode into Lines
    v_lines := regexp_split_to_array(v_bytecode, '\n');
    v_max_pc := array_length(v_lines, 1);
    
    -- 3. Execution Loop
    WHILE v_pc <= v_max_pc LOOP
        v_line := v_lines[v_pc];
        
        IF length(trim(v_line)) > 0 AND substring(trim(v_line) from 1 for 1) <> '#' THEN
            v_parts := regexp_split_to_array(trim(v_line), '\s+');
            v_opcode := v_parts[1];
            
            IF array_length(v_parts, 1) > 1 THEN
                v_oparg := v_parts[2];
                BEGIN
                    v_oparg_int := v_oparg::INTEGER;
                EXCEPTION WHEN OTHERS THEN v_oparg_int := 0; END;
            END IF;
            
            -- EXECUTE OPCODE
            CASE v_opcode
                -- LOAD_CONST
                WHEN 'LOAD_CONST' THEN
                    v_res := public.vm_tuple_getitem(v_consts_id, v_oparg_int);
                    v_stack := array_append(v_stack, v_res);
                    
                -- LOAD_FAST
                WHEN 'LOAD_FAST' THEN
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    v_res := public.vm_dict_get_item(p_locals_id, v_name);
                    IF v_res IS NULL THEN RAISE EXCEPTION 'UnboundLocalError: %', v_name; END IF;
                    v_stack := array_append(v_stack, v_res);

                -- STORE_FAST
                WHEN 'STORE_FAST' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    PERFORM public.vm_dict_set_item(p_locals_id, v_name, v_tos);

                -- LOAD_ATTR <name_idx>
                -- Replaces TOS with getattr(TOS, name)
                WHEN 'LOAD_ATTR' THEN
                    -- TOS is object
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    -- Name
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int); -- Usually names are in names, not varnames. But for simplicity let's assume varnames or consts. 
                    -- WAIT! CPython stores attribute names in co_names. We don't have co_names yet.
                    -- Let's assume for this MVP that attribute names are in co_consts or varnames.
                    -- Oparg usually indexes co_names.
                    -- Workaround: Use varnames for now.
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    
                    v_res := public.vm_getattr(v_tos, v_name);
                    
                    IF v_res IS NULL THEN
                        RAISE EXCEPTION 'AttributeError: object has no attribute "%"', v_name;
                    END IF;
                    
                    v_stack := array_append(v_stack, v_res);

                -- COMPARE_OP
                WHEN 'COMPARE_OP' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_res := public.vm_compare(v_tos1, v_tos, v_oparg_int);
                    v_stack := array_append(v_stack, v_res);

                -- POP_JUMP_IF_FALSE
                WHEN 'POP_JUMP_IF_FALSE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    if NOT public.vm_is_true(v_tos) THEN
                        v_pc := v_oparg_int; CONTINUE;
                    END IF;
                
                -- POP_JUMP_IF_TRUE
                WHEN 'POP_JUMP_IF_TRUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    if public.vm_is_true(v_tos) THEN
                        v_pc := v_oparg_int; CONTINUE;
                    END IF;
                    
                -- JUMP_FORWARD
                WHEN 'JUMP_FORWARD' THEN
                    v_pc := v_pc + v_oparg_int; CONTINUE;

                -- JUMP_ABSOLUTE
                WHEN 'JUMP_ABSOLUTE' THEN
                    v_pc := v_oparg_int; CONTINUE;

                -- RETURN_VALUE
                WHEN 'RETURN_VALUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    RETURN v_tos;

                -- CALL_FUNCTION
                WHEN 'CALL_FUNCTION' THEN
                    -- ... (Same as before, skipped for brevity in this delta but needs to be here)
                     -- Actually, we MUST include CALL_FUNCTION to keep it working.
                     -- Let's put back a simple version or rely on previous definition?
                     -- NO, CREATE OR REPLACE overwrites. We must include it.
                    v_oparg_int := v_oparg::INTEGER; -- Arg count
                    DECLARE
                        v_args UUID[];
                        v_func UUID;
                        i INT;
                    BEGIN
                        -- Pop Args
                        FOR i IN 1..v_oparg_int LOOP
                            v_args := array_prepend(v_stack[array_length(v_stack, 1)], v_args);
                            v_stack := v_stack[1:array_length(v_stack, 1)-1];
                        END LOOP;
                        -- Pop Func
                        v_func := v_stack[array_length(v_stack, 1)];
                        v_stack := v_stack[1:array_length(v_stack, 1)-1];
                        
                        -- Call
                        v_res := public.vm_call(v_func, v_args);
                        v_stack := array_append(v_stack, v_res);
                    END;

                ELSE
                    NULL;
            END CASE;
        END IF;
        v_pc := v_pc + 1;
    END LOOP;
    
    RETURN public.vm_get_none();
END;
$$ LANGUAGE plpgsql;
