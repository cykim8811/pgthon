-- =====================================================
-- Migration: VM Improvements (__call__, __sub__, BINARY_SUBTRACT)
-- Description: Implement __call__ support in vm_call, add vm_sub, and update vm_run_frame
-- =====================================================

-------------------------------------------------------
-- 0. vm_create_function: Helper for function creation
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_create_function(
    p_id uuid, -- Base ID
    p_func_id uuid, -- Table ID
    p_code_id uuid, -- Table ID
    p_name text
)
RETURNS void AS $$
DECLARE
    ID_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000008';
BEGIN
    INSERT INTO public.py_object (id, ob_type) VALUES (p_id, ID_FNC_TYPE);
    INSERT INTO public.py_function_object (id, ob_base, func_name, func_code, func_globals)
    VALUES (p_func_id, p_id, p_name, p_code_id, NULL);
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 1. vm_sub: Subtraction with method dispatch
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_sub(p_left uuid, p_right uuid)
RETURNS uuid AS $$
DECLARE
    -- Type IDs for Fast Path
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    
    v_l_type uuid;
    v_r_type uuid;
    v_l_val bigint;
    v_r_val bigint;
    
    -- For Method Dispatch
    v_method uuid;
    v_call_res uuid;
BEGIN
    v_l_type := public.vm_get_type(p_left);
    v_r_type := public.vm_get_type(p_right);
    
    -----------------------------------------------------------------
    -- 1. FAST PATH: Integer Subtraction
    -----------------------------------------------------------------
    IF v_l_type = ID_INT_TYPE AND v_r_type = ID_INT_TYPE THEN
        v_l_val := public.vm_get_int_value(p_left);
        v_r_val := public.vm_get_int_value(p_right);
        RETURN public.vm_create_int(v_l_val - v_r_val);
    END IF;
    
    -----------------------------------------------------------------
    -- 2. SLOW PATH: Method Dispatch (__sub__)
    -----------------------------------------------------------------
    -- Try p_left.__sub__(p_right)
    BEGIN
        v_method := public.vm_getattr(p_left, '__sub__');
        IF v_method IS NOT NULL THEN
            return public.vm_call(v_method, ARRAY[p_right]);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    -----------------------------------------------------------------
    -- 3. SLOW PATH: Reflected Method Dispatch (__rsub__)
    -----------------------------------------------------------------
    -- Try p_right.__rsub__(p_left)
    BEGIN
        v_method := public.vm_getattr(p_right, '__rsub__');
        IF v_method IS NOT NULL THEN
            return public.vm_call(v_method, ARRAY[p_left]);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    -----------------------------------------------------------------
    -- 4. FAILURE
    -----------------------------------------------------------------
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for -';
END;
$$ LANGUAGE plpgsql;


-------------------------------------------------------
-- 2. vm_call: Updated to support __call__ on instances
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_call(
    callable_id uuid, 
    args uuid[],
    p_caller_frame_id uuid DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
    v_type_id uuid;
    v_native_name text;
    
    ID_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000008';
    ID_JS_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000012';
    ID_METHOD_TYPE uuid := '00000000-0000-4000-a000-000000000013';
    ID_DCT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
    
    -- Bound Method variables
    v_im_func uuid;
    v_im_self uuid;
    v_new_args uuid[];
    
    -- Bytecode function variables
    v_code_id uuid;
    v_code_base_id uuid; -- Base ID
    v_locals_id uuid;
    v_base_locals uuid;
    v_varnames_id uuid;
    v_arg_name_uuid uuid;
    v_arg_name_str text;
    i integer;
    v_arg_count integer;
    v_frame_id uuid;  -- Frame object
    v_result uuid;
    
    -- Instance Call
    v_call_method uuid;
BEGIN
    -- 1. Get Type of Callable
    v_type_id := public.vm_get_type(callable_id);
    
    -----------------------------------------------------------------
    -- 2. BOUND METHOD: Unwrap and prepend self to args
    -----------------------------------------------------------------
    IF v_type_id = ID_METHOD_TYPE THEN
        SELECT im_func, im_self INTO v_im_func, v_im_self 
        FROM public.py_bound_method_object 
        WHERE ob_base = callable_id;
        
        v_new_args := array_prepend(v_im_self, args);
        RETURN public.vm_call(v_im_func, v_new_args, p_caller_frame_id);
    END IF;
    
    -----------------------------------------------------------------
    -- 3. NATIVE FUNCTION: Dispatch to native implementation
    -----------------------------------------------------------------
    IF v_type_id = ID_JS_FNC_TYPE THEN
        SELECT fn_name INTO v_native_name 
        FROM public.py_js_function_object 
        WHERE ob_base = callable_id;
        
        RETURN public.vm_native_dispatch(v_native_name, args);
    END IF;
    
    -----------------------------------------------------------------
    -- 4. PYTHON BYTECODE FUNCTION: Create locals and run frame
    -----------------------------------------------------------------
    IF v_type_id = ID_FNC_TYPE THEN
        -- Get code object (Table ID)
        SELECT func_code INTO v_code_id 
        FROM public.py_function_object 
        WHERE ob_base = callable_id;
        
        -- Get Code Base ID for Frame Creation
        SELECT ob_base INTO v_code_base_id
        FROM public.py_code_object
        WHERE id = v_code_id;
        
        -- Create locals dictionary
        v_base_locals := gen_random_uuid();
        v_locals_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (v_base_locals, ID_DCT_TYPE);
        INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (v_locals_id, v_base_locals, 0);
        
        -- Get varnames for argument binding
        SELECT c.co_varnames, c.co_argcount INTO v_varnames_id, v_arg_count
        FROM public.py_code_object c
        WHERE c.id = v_code_id;
        
        -- Bind arguments to locals
        IF array_length(args, 1) > 0 THEN
            FOR i IN 1..array_length(args, 1) LOOP
                -- Get argument name from varnames tuple (0-indexed)
                v_arg_name_uuid := public.vm_tuple_getitem(v_varnames_id, i - 1);
                SELECT str_value INTO v_arg_name_str 
                FROM public.py_unicode_object 
                WHERE ob_base = v_arg_name_uuid;
                
                -- Set in locals
                PERFORM public.vm_dict_set_item(v_locals_id, v_arg_name_str, args[i]);
            END LOOP;
        END IF;

        -- Create Frame Object
        v_frame_id := public.vm_create_frame(
            v_code_base_id,
            v_base_locals, -- Use Base ID
            NULL,  -- globals
            NULL,  -- builtins
            p_caller_frame_id
        );
        
        -- Set current frame context
        PERFORM public.vm_set_current_frame(v_frame_id);
        
        -- Run frame with code Base ID and locals Base ID
        v_result := public.vm_run_frame(v_code_base_id, v_base_locals, NULL, v_frame_id);
        
        -- Restore previous frame
        IF p_caller_frame_id IS NOT NULL THEN
            PERFORM public.vm_set_current_frame(p_caller_frame_id);
        END IF;
        
        RETURN v_result;
    END IF;
    
    -----------------------------------------------------------------
    -- 5. INSTANCE CALL (__call__)
    -----------------------------------------------------------------
    -- Try to find __call__ method
    BEGIN
        v_call_method := public.vm_getattr(callable_id, '__call__');
        IF v_call_method IS NOT NULL THEN
            -- Dispatch to __call__ method (which is a bound method)
            RETURN public.vm_call(v_call_method, args, p_caller_frame_id);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        -- getattr failed, ignore
        NULL;
    END;
    
    RAISE EXCEPTION 'TypeError: Object % is not callable', callable_id;
END;
$$ LANGUAGE plpgsql;


-------------------------------------------------------
-- 3. vm_run_frame: Updated with BINARY_SUBTRACT
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_run_frame(
    p_code_id uuid, -- Base ID
    p_locals_id uuid, 
    p_globals_id uuid,
    p_frame_id uuid DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
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
BEGIN
    -- 1. Fetch Code Object
    SELECT * INTO v_code_obj FROM public.py_code_object WHERE ob_base = p_code_id;
    v_code := v_code_obj.co_code;
    
    -- 2. Parse Bytecode
    v_lines := regexp_split_to_array(v_code, '\n');
    v_max_pc := array_length(v_lines, 1);
    
    -- 3. Execution Loop
    <<exec_loop>>
    WHILE v_pc <= v_max_pc LOOP
        v_line := v_lines[v_pc];
        
        -- Update frame state
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
                v_oparg_int := v_oparg::integer;
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
                    
                    v_res := public.vm_add(v_tos1, v_tos);
                    v_stack := array_append(v_stack, v_res);
                    
                -- BINARY_SUBTRACT
                WHEN 'BINARY_SUBTRACT' THEN
                    v_tos := v_stack[array_length(v_stack, 1)]; -- right
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)]; -- left
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_res := public.vm_sub(v_tos1, v_tos);
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
                        CONTINUE;
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
                        
                        -- Call
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
    -- Traceback Handling
    IF SQLERRM LIKE '%Traceback (most recent call last):%' THEN
        RAISE;
    END IF;

    IF p_frame_id IS NOT NULL THEN
        DECLARE
            v_tb text;
            v_final_msg text;
        BEGIN
            PERFORM public.vm_update_frame(p_frame_id, v_pc, v_pc);
            v_tb := public.vm_format_traceback(p_frame_id);
            v_final_msg := format(E'%s\n%s', v_tb, SQLERRM);
            RAISE EXCEPTION '%', v_final_msg;
        END;
    ELSE
        RAISE;
    END IF;
END;
$$ LANGUAGE plpgsql;
