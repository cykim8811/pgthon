-- Migration: VM Implementation Step 4 (Interpreter Loop)
-- Created at: 2026-01-17 00:00:04

DO $$
BEGIN
    -- No schema changes
END $$;

-------------------------------------------------------
-- Helper: Dictionary Operations (Set Item)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_dict_set_item(p_dict_id UUID, p_key_str TEXT, p_value_id UUID)
RETURNS VOID AS $$
DECLARE
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    v_key_obj UUID;
    v_key_base UUID;
BEGIN
    -- 1. Check if key exists (Skip for simple locals initialization MVP)
    -- Just insert directly for NOW (Assume clean locals dict)
    
    -- Create String Object for Key
    v_key_base := gen_random_uuid();
    v_key_obj := gen_random_uuid();
    
    INSERT INTO public.py_object (id, ob_type) VALUES (v_key_base, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (id, ob_base, str_value) 
    VALUES (v_key_obj, v_key_base, p_key_str);
    
    -- Insert Entry
    INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value)
    VALUES (gen_random_uuid(), p_dict_id, v_key_base, p_value_id);
    
    -- Update Usage
    UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = p_dict_id;
END;
$$ LANGUAGE plpgsql;

-- Helper: Dictionary Get Item (by string key)
CREATE OR REPLACE FUNCTION public.vm_dict_get_item(p_dict_id UUID, p_key_str TEXT)
RETURNS UUID AS $$
DECLARE
    v_val_id UUID;
BEGIN
    SELECT e.me_value INTO v_val_id
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = p_dict_id AND u.str_value = p_key_str
    LIMIT 1;
    
    RETURN v_val_id;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- VM Run Frame (Interpreter)
-------------------------------------------------------
DROP FUNCTION IF EXISTS public.vm_run_frame(UUID, UUID, UUID);

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
    
    -- 3. Instruction Loop
    FOREACH v_line IN ARRAY v_lines LOOP
        IF length(trim(v_line)) > 0 THEN
            -- Parse Opcode and Argument (Access by whitespace)
            v_parts := regexp_split_to_array(trim(v_line), '\s+');
            v_opcode := v_parts[1];
            
            IF array_length(v_parts, 1) > 1 THEN
                v_oparg := v_parts[2];
                BEGIN
                    v_oparg_int := v_oparg::INTEGER;
                EXCEPTION WHEN OTHERS THEN
                    v_oparg_int := 0;
                END;
            END IF;
            
            -- EXECUTE OPCODE
            CASE v_opcode
                -- LOAD_CONST <idx>
                WHEN 'LOAD_CONST' THEN
                    v_res := public.vm_tuple_getitem(v_consts_id, v_oparg_int);
                    v_stack := array_append(v_stack, v_res);
                    
                -- LOAD_FAST <name_idx>
                WHEN 'LOAD_FAST' THEN
                    -- Get variable name from co_varnames tuple
                    -- Note: In real bytecode, oparg is index. We need to look up name, then dict.
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int);
                    -- Get Name String from Object (Assuming v_res is String Object)
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    
                    -- Lookup in Locals
                    v_res := public.vm_dict_get_item(p_locals_id, v_name);
                    IF v_res IS NULL THEN 
                        RAISE EXCEPTION 'UnboundLocalError: local variable "%" referenced before assignment', v_name; 
                    END IF;
                    v_stack := array_append(v_stack, v_res);

                -- STORE_FAST <name_idx>
                WHEN 'STORE_FAST' THEN
                    -- Pop Value
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    -- Get Name
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    
                    -- Store
                    PERFORM public.vm_dict_set_item(p_locals_id, v_name, v_tos);

                -- BINARY_ADD
                WHEN 'BINARY_ADD' THEN
                    -- Pop Right (TOS)
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1]; -- Pop
                    
                    -- Pop Left (TOS1)
                    v_tos1 := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1]; -- Pop
                    
                    -- Perform Add: vm_call(getattr(L, '__add__'), [R])
                    -- Optimization: Direct native dispatch if we assume int?
                    -- Let's stick to protocol: getattr
                    v_bound_method := public.vm_getattr(v_tos1, '__add__');
                    IF v_bound_method IS NULL THEN RAISE EXCEPTION 'AttributeError: __add__ not found'; END IF;
                    
                    v_res := public.vm_call(v_bound_method, ARRAY[v_tos]);
                    
                    -- Push Result
                    v_stack := array_append(v_stack, v_res);

                -- RETURN_VALUE
                WHEN 'RETURN_VALUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    RETURN v_tos;

                ELSE
                    -- Ignore unknown or labels for now (MVP)
                    NULL;
            END CASE;
            
        END IF;
    END LOOP;
    
    RETURN public.vm_get_none();
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- Update vm_call to handle ID_FNC_TYPE (Bytecode)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_call(callable_id UUID, args UUID[])
RETURNS UUID AS $$
DECLARE
    v_type_id UUID;
    v_native_name TEXT;
    
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    ID_JS_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000013';
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    
    -- Bound Method
    v_im_func UUID;
    v_im_self UUID;
    v_new_args UUID[];
    
    -- Bytecode
    v_code_id UUID;
    v_locals_id UUID;
    v_base_locals UUID;
    v_varnames_id UUID;
    v_arg_name_uuid UUID;
    v_arg_name_str TEXT;
    i INTEGER;
    v_arg_count INTEGER;
BEGIN
    -- 1. Get Type
    v_type_id := public.vm_get_type(callable_id);
    
    -- 2. Bound Method
    IF v_type_id = ID_METHOD_TYPE THEN
        SELECT im_func, im_self INTO v_im_func, v_im_self 
        FROM public.py_bound_method_object WHERE ob_base = callable_id;
        v_new_args := array_prepend(v_im_self, args);
        RETURN public.vm_call(v_im_func, v_new_args);
    END IF;
    
    -- 3. Native Function
    IF v_type_id = ID_JS_FNC_TYPE THEN
        SELECT fn_name INTO v_native_name FROM public.py_js_function_object WHERE ob_base = callable_id;
        RETURN public.vm_native_dispatch(v_native_name, args);
    END IF;
    
    -- 4. Python Bytecode Function
    IF v_type_id = ID_FNC_TYPE THEN
        -- Get Code Object
        SELECT func_code INTO v_code_id FROM public.py_function_object WHERE ob_base = callable_id;
        
        -- Create Locals Dict
        v_base_locals := gen_random_uuid();
        v_locals_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (v_base_locals, ID_DCT_TYPE);
        INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (v_locals_id, v_base_locals, 0);
        
        -- Determine Arguments and bind to locals using co_varnames
        SELECT c.co_varnames, c.co_argcount INTO v_varnames_id, v_arg_count
        FROM public.py_code_object c
        WHERE c.id = v_code_id; -- Note: using id not ob_base because code reference is direct usually?
        -- Wait, py_function_object func_code references py_code_object(id). Correct.
        
        -- Bind Arguments
        -- We have args[] and co_varnames tuple.
        -- Loop i from 0 to array_length(args)
        IF array_length(args, 1) > 0 THEN
            FOR i IN 1..array_length(args, 1) LOOP
                -- Get Argument Name from Tuple (Index i-1)
                v_arg_name_uuid := public.vm_tuple_getitem(v_varnames_id, i - 1);
                SELECT str_value INTO v_arg_name_str FROM public.py_unicode_object WHERE ob_base = v_arg_name_uuid;
                
                -- Set to Locals
                PERFORM public.vm_dict_set_item(v_locals_id, v_arg_name_str, args[i]);
            END LOOP;
        END IF;

        -- Run Frame
        -- Globals passed as NULL for now (or function's globals)
        RETURN public.vm_run_frame(v_code_id, v_locals_id, NULL);
    END IF;
    
    RAISE EXCEPTION 'TypeError: Object % is not callable', callable_id;
END;
$$ LANGUAGE plpgsql;
