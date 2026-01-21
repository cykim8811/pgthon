-- =====================================================
-- Migration: Upgrade VM Interpreter
-- Description: 
--   1. Update vm_run_frame to use vm_add, vm_sub, etc. (Single Source of Truth)
--   2. Implement LOAD_GLOBAL, STORE_GLOBAL, LOAD_NAME, STORE_NAME properly.
--   3. Ensure proper error handling and strict Python semantics.
-- =====================================================

CREATE OR REPLACE FUNCTION public.vm_run_frame(
    p_code_id uuid, 
    p_locals_id uuid, 
    p_globals_id uuid,
    p_frame_id uuid DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
    -- Code attributes
    v_bytecode text;
    v_consts_id uuid;
    v_varnames_id uuid;
    v_names_id uuid; -- For LOAD_NAME, LOAD_GLOBAL
    
    -- Execution state
    v_stack uuid[] := ARRAY[]::uuid[];
    v_lines text[];
    v_line text;
    v_parts text[];
    v_opcode text;
    v_oparg text;
    v_oparg_int integer;
    
    v_pc integer := 1;  -- Program counter (1-based line index)
    v_max_pc integer;
    
    -- Temporary variables
    v_tos uuid;
    v_tos1 uuid;
    v_res uuid;
    v_name text;
    v_func uuid;
    v_args uuid[];
    i integer;
    
    -- IDs for lookups
    v_builtins_id uuid;
    ID_DICT_BUILTINS uuid := '00000000-0000-4000-a000-000000000006'; -- Assuming fixed, or get from somewhere
    -- Wait, builtins dict ID is NOT fixed in older migrations (randomly gen). 
    -- We should look it up or pass it. 
    -- vm_create_frame takes builtins. We can probably get it from frame?
    -- For now, let's assume p_globals_id['__builtins__'] holds the module or dict.
    -- Or just query the well-known builtins if possible.
    -- Better: Access p_frame_id -> f_builtins if available.
    
    v_frame_info jsonb;
    v_builtins_dict uuid;
    
BEGIN
    -- 0. Get Frame Info for Builtins (if frame exists)
    IF p_frame_id IS NOT NULL THEN
        SELECT f_builtins INTO v_builtins_dict 
        FROM public.py_frame_object 
        WHERE ob_base = p_frame_id;
    END IF;
    
    -- If no frame or builtins not found, fallback to ... lookup?
    -- In this simple VM, we usually just want the builtins DICT.
    -- Let's query the global singleton builtins dict assuming a fixed ID or lookup.
    -- Actually, in '05_builtins_dict.sql', we used ID_DICT_BUILTINS as '0000...0007' ? No.
    -- Let's look up by name from somewhere? 
    -- Workaround: We will implement LOAD_GLOBAL to look in globals, then fallback to builtins.
    -- If v_builtins_dict is NULL, we might fail LEGB lookup.

    -- 1. Fetch code object data
    SELECT co_code, co_consts, co_varnames, co_names
    INTO v_bytecode, v_consts_id, v_varnames_id, v_names_id
    FROM public.py_code_object WHERE ob_base = p_code_id;
    
    -- 2. Split bytecode into lines
    v_lines := regexp_split_to_array(v_bytecode, '\n');
    v_max_pc := array_length(v_lines, 1);
    
    -----------------------------------------------------------------
    -- 3. MAIN EXECUTION LOOP
    -----------------------------------------------------------------
    WHILE v_pc <= v_max_pc LOOP
        v_line := v_lines[v_pc];
        
        -- Update frame state
        IF p_frame_id IS NOT NULL THEN
            PERFORM public.vm_update_frame(p_frame_id, v_pc, v_pc);
        END IF;
        
        -- Skip empty lines and comments
        IF length(trim(v_line)) > 0 AND substring(trim(v_line) from 1 for 1) <> '#' THEN
            -- Parse opcode and argument
            v_parts := regexp_split_to_array(trim(v_line), '\s+');
            v_opcode := v_parts[1];
            
            IF array_length(v_parts, 1) > 1 THEN
                v_oparg := v_parts[2];
                BEGIN
                    v_oparg_int := v_oparg::integer;
                EXCEPTION WHEN OTHERS THEN v_oparg_int := 0; END;
            ELSE
                v_oparg_int := 0;
            END IF;
            
            ---------------------------------------------------------
            -- EXECUTE OPCODE
            ---------------------------------------------------------
            CASE v_opcode
                
                -- LOAD_CONST <idx>
                WHEN 'LOAD_CONST' THEN
                    v_res := public.vm_tuple_getitem(v_consts_id, v_oparg_int);
                    v_stack := array_append(v_stack, v_res);
                    
                -- LOAD_FAST <name_idx> (Local)
                WHEN 'LOAD_FAST' THEN
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    v_res := public.vm_dict_get_item(p_locals_id, v_name);
                    
                    IF v_res IS NULL THEN 
                         RAISE EXCEPTION 'UnboundLocalError: local variable "%" referenced before assignment', v_name; 
                    END IF;
                    v_stack := array_append(v_stack, v_res);

                -- STORE_FAST <name_idx>
                WHEN 'STORE_FAST' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    PERFORM public.vm_dict_set_item(p_locals_id, v_name, v_tos);

                -- LOAD_GLOBAL <name_idx> (Global -> Builtin)
                WHEN 'LOAD_GLOBAL' THEN
                    -- Get Name from co_names (not Varnames!)
                    v_res := public.vm_tuple_getitem(v_names_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    
                    RAISE DEBUG 'LOAD_GLOBAL index=%, name="%", globals_id=%', v_oparg_int, v_name, p_globals_id;

                    -- 1. Look in Globals
                    v_res := NULL;
                    IF p_globals_id IS NOT NULL THEN
                        v_res := public.vm_dict_get_item(p_globals_id, v_name);
                    END IF;
                    
                    -- 2. Look in Builtins if not found
                    IF v_res IS NULL AND v_builtins_dict IS NOT NULL THEN
                        v_res := public.vm_dict_get_item(v_builtins_dict, v_name);
                    END IF;
                    
                    IF v_res IS NULL THEN
                        RAISE EXCEPTION 'NameError: name "%" is not defined', v_name;
                    END IF;
                    
                    v_stack := array_append(v_stack, v_res);

                -- STORE_GLOBAL <name_idx>
                WHEN 'STORE_GLOBAL' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_tuple_getitem(v_names_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    
                    IF p_globals_id IS NOT NULL THEN
                        PERFORM public.vm_dict_set_item(p_globals_id, v_name, v_tos);
                    ELSE
                         RAISE EXCEPTION 'SystemError: Attempted STORE_GLOBAL but no globals dict found';
                    END IF;

                -- LOAD_NAME <name_idx> (Locals -> Globals -> Builtins)
                WHEN 'LOAD_NAME' THEN
                     v_res := public.vm_tuple_getitem(v_names_id, v_oparg_int);
                     SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                     
                     -- 1. Locals
                     v_res := public.vm_dict_get_item(p_locals_id, v_name);
                     
                     -- 2. Globals
                     IF v_res IS NULL AND p_globals_id IS NOT NULL THEN
                         v_res := public.vm_dict_get_item(p_globals_id, v_name);
                     END IF;
                     
                     -- 3. Builtins
                     IF v_res IS NULL AND v_builtins_dict IS NOT NULL THEN
                         v_res := public.vm_dict_get_item(v_builtins_dict, v_name);
                     END IF;
                     
                     IF v_res IS NULL THEN
                        RAISE EXCEPTION 'NameError: name "%" is not defined', v_name;
                     END IF;
                     v_stack := array_append(v_stack, v_res);

                -- LOAD_ATTR <name_idx>
                WHEN 'LOAD_ATTR' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    -- Get attribute name from co_names
                    v_res := public.vm_tuple_getitem(v_names_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    
                    v_res := public.vm_getattr(v_tos, v_name);
                    
                    IF v_res IS NULL THEN
                        RAISE EXCEPTION 'AttributeError: object has no attribute "%"', v_name;
                    END IF;
                    v_stack := array_append(v_stack, v_res);

                -- BINARY_ADD: Delegate to vm_add
                WHEN 'BINARY_ADD' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];  -- right
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)]; -- left
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_add(v_tos1, v_tos);
                    v_stack := array_append(v_stack, v_res);

                -- BINARY_SUBTRACT: Delegate to vm_sub
                WHEN 'BINARY_SUBTRACT' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_sub(v_tos1, v_tos);
                    v_stack := array_append(v_stack, v_res);
                    
                -- BINARY_MULTIPLY: Delegate to vm_mul
                WHEN 'BINARY_MULTIPLY' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_mul(v_tos1, v_tos);
                    v_stack := array_append(v_stack, v_res);
                    
                -- BINARY_TRUE_DIVIDE: Delegate to vm_div (assuming it exists)
                WHEN 'BINARY_TRUE_DIVIDE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_div(v_tos1, v_tos);
                    v_stack := array_append(v_stack, v_res);
                    
                -- BINARY_FLOOR_DIVIDE: Delegate to vm_floordiv
                WHEN 'BINARY_FLOOR_DIVIDE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_floordiv(v_tos1, v_tos);
                    v_stack := array_append(v_stack, v_res);

                -- BINARY_MODULO: Delegate to vm_mod
                WHEN 'BINARY_MODULO' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_mod(v_tos1, v_tos);
                    v_stack := array_append(v_stack, v_res);

                 -- BINARY_POWER: Delegate to vm_pow
                WHEN 'BINARY_POWER' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_pow(v_tos1, v_tos);
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
                    IF NOT public.vm_is_true(v_tos) THEN
                        v_pc := v_oparg_int;
                        CONTINUE;
                    END IF;

                -- POP_JUMP_IF_TRUE
                WHEN 'POP_JUMP_IF_TRUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    IF public.vm_is_true(v_tos) THEN
                        v_pc := v_oparg_int;
                        CONTINUE;
                    END IF;

                -- JUMP_FORWARD
                WHEN 'JUMP_FORWARD' THEN
                    v_pc := v_pc + v_oparg_int;
                    CONTINUE;

                -- JUMP_ABSOLUTE
                WHEN 'JUMP_ABSOLUTE' THEN
                    v_pc := v_oparg_int;
                    CONTINUE;

                -- CALL_FUNCTION
                WHEN 'CALL_FUNCTION' THEN
                    v_args := ARRAY[]::uuid[];
                    FOR i IN 1..v_oparg_int LOOP
                        v_args := array_prepend(v_stack[array_length(v_stack, 1)], v_args);
                        v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    END LOOP;
                    v_func := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_call(v_func, v_args, p_frame_id);
                    v_stack := array_append(v_stack, v_res);

                -- RETURN_VALUE
                WHEN 'RETURN_VALUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    RETURN v_tos;

                -- POP_TOP
                WHEN 'POP_TOP' THEN
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];

                ELSE
                    NULL;
            END CASE;
        END IF;
        
        v_pc := v_pc + 1;
    END LOOP;
    
    RETURN public.vm_get_none();
END;
$$ LANGUAGE plpgsql;
