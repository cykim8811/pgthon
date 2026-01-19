-- =====================================================
-- Migration: Error Handling & Traceback Integration
-- Description: Update vm_run_frame to attach tracebacks on error
-- =====================================================

CREATE OR REPLACE FUNCTION public.vm_run_frame(
    p_code_id uuid, 
    p_locals_id uuid, 
    p_globals_id uuid,
    p_frame_id uuid DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
    -- ... (Copying existing variables) ...
    v_code_obj record;
    v_code text;
    v_lines text[];
    v_line text;
    v_parts text[];
    v_opcode text;
    v_oparg text;
    v_oparg_int integer;
    
    -- Stack and storage
    v_stack uuid[] := ARRAY[]::uuid[];
    v_val_stack uuid;
    
    -- Execution State
    v_pc integer := 1;
    v_max_pc integer;
    
    -- Temp variables
    v_tos uuid;
    v_tos1 uuid;
    v_res uuid;
    v_name text;
    
    -- Constants for logic
    ID_NONE_OBJ uuid := '00000000-0000-4000-b000-000000000001';
    
    -- Debugging
    v_debug boolean := false;
BEGIN
    -- 1. Fetch Code Object
    SELECT * INTO v_code_obj FROM public.py_code_object WHERE ob_base = p_code_id;
    v_code := v_code_obj.co_code;
    
    -- 2. Parse Bytecode (Naive Line-by-Line for prototype)
    v_lines := regexp_split_to_array(v_code, '\n');
    v_max_pc := array_length(v_lines, 1);
    
    -- 3. Execution Loop
    <<exec_loop>>
    WHILE v_pc <= v_max_pc LOOP
        v_line := v_lines[v_pc];
        
        -- Update frame state (for introspection)
        IF p_frame_id IS NOT NULL THEN
            PERFORM public.vm_update_frame(p_frame_id, v_pc, v_pc);
        END IF;
        
        -- Skip empty lines and comments
        IF length(trim(v_line)) > 0 AND substring(trim(v_line) from 1 for 1) <> '#' THEN
            -- Parse Opcode/Arg
            v_parts := regexp_split_to_array(trim(v_line), '\s+');
            v_opcode := v_parts[1];
            
            IF array_length(v_parts, 1) > 1 THEN
                v_oparg := v_parts[2];
                v_oparg_int := v_oparg::integer; -- Assuming valid int for now
            END IF;
            
            -- Dispatch
            CASE v_opcode
                -- POP_TOP
                WHEN 'POP_TOP' THEN
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];

                -- LOAD_CONST <const_idx>
                WHEN 'LOAD_CONST' THEN
                    v_res := public.vm_tuple_getitem(v_code_obj.co_consts, v_oparg_int);
                    v_stack := array_append(v_stack, v_res);
                
                -- LOAD_FAST <var_idx>
                WHEN 'LOAD_FAST' THEN
                    v_name := public.vm_get_str_value(
                        public.vm_tuple_getitem(v_code_obj.co_varnames, v_oparg_int)
                    );
                    v_res := public.vm_dict_get_item(p_locals_id, v_name);
                    IF v_res IS NULL THEN
                        RAISE EXCEPTION 'UnboundLocalError: local variable "%" referenced before assignment', v_name;
                    END IF;
                    v_stack := array_append(v_stack, v_res);
                    
                -- STORE_FAST <var_idx>
                WHEN 'STORE_FAST' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_name := public.vm_get_str_value(
                        public.vm_tuple_getitem(v_code_obj.co_varnames, v_oparg_int)
                    );
                    PERFORM public.vm_dict_set_item(p_locals_id, v_name, v_tos);

                -- BINARY_ADD
                WHEN 'BINARY_ADD' THEN
                    v_tos := v_stack[array_length(v_stack, 1)]; -- right
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)]; -- left
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    -- Use polymorphic vm_add
                    v_res := public.vm_add(v_tos1, v_tos);
                    v_stack := array_append(v_stack, v_res);

                -- RETURN_VALUE
                WHEN 'RETURN_VALUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    RETURN v_tos;

                -- COMPARE_OP <op_idx>
                WHEN 'COMPARE_OP' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];  -- right
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)]; -- left
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_compare(v_tos1, v_tos, v_oparg_int);
                    v_stack := array_append(v_stack, v_res);

                -- POP_JUMP_IF_FALSE <target_line>
                WHEN 'POP_JUMP_IF_FALSE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    IF NOT public.vm_is_true(v_tos) THEN
                        v_pc := v_oparg_int;
                        CONTINUE; -- Skip increment at end of loop
                    END IF;

                -- POP_JUMP_IF_TRUE <target_line>
                WHEN 'POP_JUMP_IF_TRUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    IF public.vm_is_true(v_tos) THEN
                        v_pc := v_oparg_int;
                        CONTINUE;
                    END IF;

                -- CALL_FUNCTION <argc>
                WHEN 'CALL_FUNCTION' THEN
                    DECLARE
                        v_argc integer := v_oparg_int;
                        v_args uuid[];
                        v_func uuid;
                    BEGIN
                        -- Pop args
                        IF v_argc > 0 THEN
                            v_args := v_stack[array_length(v_stack, 1) - v_argc + 1 : array_length(v_stack, 1)];
                            v_stack := v_stack[1 : array_length(v_stack, 1) - v_argc];
                        ELSE
                            v_args := ARRAY[]::uuid[];
                        END IF;
                        
                        -- Pop function
                        v_func := v_stack[array_length(v_stack, 1)];
                        v_stack := v_stack[1 : array_length(v_stack, 1) - 1];
                        
                        -- Call (Passing current frame for traceback chain)
                        v_res := public.vm_call(v_func, v_args, p_frame_id);
                        v_stack := array_append(v_stack, v_res);
                    END;

                ELSE
                    RAISE EXCEPTION 'Unknown Opcode: %', v_opcode;
            END CASE;
        END IF;
        
        v_pc := v_pc + 1;
    END LOOP;
    
    RETURN ID_NONE_OBJ;

EXCEPTION WHEN OTHERS THEN
    -- ERROR HANDLING & TRACEBACK GENERATION
    
    -- 1. If error already has a traceback (bubbling up), just re-raise
    IF SQLERRM LIKE '%Traceback (most recent call last):%' THEN
        RAISE;
    END IF;

    -- 2. If we have frame info, generate traceback
    IF p_frame_id IS NOT NULL THEN
        DECLARE
            v_tb text;
            v_final_msg text;
        BEGIN
            -- Ensure current frame state is saved for accurate traceback
            PERFORM public.vm_update_frame(p_frame_id, v_pc, v_pc);
            
            v_tb := public.vm_format_traceback(p_frame_id);
            v_final_msg := format(E'%s\n%s', v_tb, SQLERRM);
            
            RAISE EXCEPTION '%', v_final_msg;
        END;
    ELSE
        -- No frame context (e.g., bare execution), re-raise
        RAISE;
    END IF;
END;
$$ LANGUAGE plpgsql;
