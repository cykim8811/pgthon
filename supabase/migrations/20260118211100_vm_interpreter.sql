-- =====================================================
-- Migration: VM Bytecode Interpreter
-- Description: Core bytecode execution engine (vm_run_frame)
-- =====================================================

-------------------------------------------------------
-- vm_run_frame: Execute Python bytecode
-------------------------------------------------------
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
    v_bound_method uuid;
    v_func uuid;
    v_args uuid[];
    i integer;
BEGIN
    -- 1. Fetch code object data
    SELECT co_code, co_consts, co_varnames 
    INTO v_bytecode, v_consts_id, v_varnames_id 
    FROM public.py_code_object WHERE ob_base = p_code_id;
    
    -- 2. Split bytecode into lines
    v_lines := regexp_split_to_array(v_bytecode, '\n');
    v_max_pc := array_length(v_lines, 1);
    
    -----------------------------------------------------------------
    -- 3. MAIN EXECUTION LOOP
    -----------------------------------------------------------------
    WHILE v_pc <= v_max_pc LOOP
        v_line := v_lines[v_pc];
        
        -- Update frame state (for introspection)
        IF p_frame_id IS NOT NULL THEN
            PERFORM public.vm_update_frame(p_frame_id, v_pc, v_pc);
        END IF;
        
        -- Skip empty lines and comments
        IF length(trim(v_line)) > 0 AND substring(trim(v_line) from 1 for 1) <> '#' THEN
            -- Parse opcode and argument
            v_parts := regexp_split_to_array(trim(v_line), '\s+');
            v_opcode := v_parts[1];
            
            -- Extract argument if present
            IF array_length(v_parts, 1) > 1 THEN
                v_oparg := v_parts[2];
                BEGIN
                    v_oparg_int := v_oparg::integer;
                EXCEPTION WHEN OTHERS THEN
                    v_oparg_int := 0;
                END;
            ELSE
                v_oparg_int := 0;
            END IF;
            
            ---------------------------------------------------------
            -- EXECUTE OPCODE
            ---------------------------------------------------------
            CASE v_opcode
                
                -- LOAD_CONST <idx>: Push constant onto stack
                WHEN 'LOAD_CONST' THEN
                    v_res := public.vm_tuple_getitem(v_consts_id, v_oparg_int);
                    v_stack := array_append(v_stack, v_res);
                    
                -- LOAD_FAST <name_idx>: Push local variable onto stack
                WHEN 'LOAD_FAST' THEN
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    v_res := public.vm_dict_get_item(p_locals_id, v_name);
                    
                    IF v_res IS NULL THEN 
                        RAISE EXCEPTION 'UnboundLocalError: local variable "%" referenced before assignment (Line %)', v_name, v_pc; 
                    END IF;
                    
                    v_stack := array_append(v_stack, v_res);

                -- STORE_FAST <name_idx>: Pop stack and store in local variable
                WHEN 'STORE_FAST' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    
                    PERFORM public.vm_dict_set_item(p_locals_id, v_name, v_tos);

                -- LOAD_ATTR <name_idx>: Get attribute from TOS object
                WHEN 'LOAD_ATTR' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    -- Get attribute name
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    
                    -- Get attribute (may return bound method)
                    v_res := public.vm_getattr(v_tos, v_name);
                    
                    IF v_res IS NULL THEN
                        RAISE EXCEPTION 'AttributeError: object has no attribute "%"', v_name;
                    END IF;
                    
                    v_stack := array_append(v_stack, v_res);

                -- BINARY_ADD: Pop two values, add them, push result
                WHEN 'BINARY_ADD' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];  -- right
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)]; -- left
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    -- Get __add__ method and call it
                    v_bound_method := public.vm_getattr(v_tos1, '__add__');
                    IF v_bound_method IS NULL THEN 
                        RAISE EXCEPTION 'AttributeError: __add__ not found'; 
                    END IF;
                    
                    v_res := public.vm_call(v_bound_method, ARRAY[v_tos], p_frame_id);
                    v_stack := array_append(v_stack, v_res);

                -- COMPARE_OP <op_idx>: Compare TOS and TOS1
                WHEN 'COMPARE_OP' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];  -- right
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)]; -- left
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_compare(v_tos1, v_tos, v_oparg_int);
                    v_stack := array_append(v_stack, v_res);

                -- POP_JUMP_IF_FALSE <target_line>: Jump if TOS is false
                WHEN 'POP_JUMP_IF_FALSE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    IF NOT public.vm_is_true(v_tos) THEN
                        v_pc := v_oparg_int;
                        CONTINUE; -- Skip increment at end of loop
                    END IF;

                -- POP_JUMP_IF_TRUE <target_line>: Jump if TOS is true
                WHEN 'POP_JUMP_IF_TRUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    IF public.vm_is_true(v_tos) THEN
                        v_pc := v_oparg_int;
                        CONTINUE;
                    END IF;

                -- JUMP_FORWARD <delta>: Relative jump forward
                WHEN 'JUMP_FORWARD' THEN
                    v_pc := v_pc + v_oparg_int;
                    CONTINUE;

                -- JUMP_ABSOLUTE <target_line>: Absolute jump
                WHEN 'JUMP_ABSOLUTE' THEN
                    v_pc := v_oparg_int;
                    CONTINUE;

                -- CALL_FUNCTION <argc>: Call function with N arguments
                WHEN 'CALL_FUNCTION' THEN
                    v_args := ARRAY[]::uuid[];
                    
                    -- Pop arguments (in reverse order)
                    FOR i IN 1..v_oparg_int LOOP
                        v_args := array_prepend(v_stack[array_length(v_stack, 1)], v_args);
                        v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    END LOOP;
                    
                    -- Pop function
                    v_func := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    -- Call and push result
                    v_res := public.vm_call(v_func, v_args, p_frame_id);
                    v_stack := array_append(v_stack, v_res);

                -- RETURN_VALUE: Return TOS
                WHEN 'RETURN_VALUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    RETURN v_tos;

                -- POP_TOP: Remove TOS
                WHEN 'POP_TOP' THEN
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];

                -- Unknown opcodes are ignored
                ELSE
                    NULL;
            END CASE;
            
        END IF;
        
        -- Increment program counter
        v_pc := v_pc + 1;
    END LOOP;
    
    -- If we exit loop without explicit RETURN_VALUE, return None
    RETURN public.vm_get_none();
END;
$$ LANGUAGE plpgsql;
