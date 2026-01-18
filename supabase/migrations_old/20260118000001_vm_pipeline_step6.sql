-- Migration: VM Implementation Step 6 (Control Flow & loops)
-- Created at: 2026-01-18 00:00:01

-------------------------------------------------------
-- Helper: Truth Testing
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_is_true(p_obj_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    ID_TRUE_OBJ  UUID := '00000000-0000-4000-b000-000000000002';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000003';
    ID_NONE_OBJ  UUID := '00000000-0000-4000-b000-000000000001';
    
    v_long_val BIGINT;
BEGIN
    -- 1. Check Singletons
    IF p_obj_id = ID_TRUE_OBJ THEN RETURN TRUE; END IF;
    IF p_obj_id = ID_FALSE_OBJ THEN RETURN FALSE; END IF;
    IF p_obj_id = ID_NONE_OBJ THEN RETURN FALSE; END IF;
    
    -- 2. Check Int (0 is False)
    SELECT long_value INTO v_long_val FROM public.py_long_object WHERE ob_base = p_obj_id;
    IF v_long_val IS NOT NULL THEN
        RETURN v_long_val <> 0;
    END IF;
    
    -- Default: True (Like Python objects)
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- VM Run Frame (Interpreter with Control Flow)
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
    
    v_pc INTEGER := 1;  -- Program Counter (1-based Line Index)
    v_max_pc INTEGER;
    
    -- Temps
    v_tos UUID;
    v_tos1 UUID;
    v_res UUID;
    v_name TEXT;
    v_bound_method UUID;
    v_bool_res BOOLEAN;
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
        
        -- Skip empty lines/comments
        IF length(trim(v_line)) > 0 AND substring(trim(v_line) from 1 for 1) <> '#' THEN
            -- Parse Opcode and Argument
            v_parts := regexp_split_to_array(trim(v_line), '\s+');
            v_opcode := v_parts[1];
            
            IF array_length(v_parts, 1) > 1 THEN
                v_oparg := v_parts[2];
                BEGIN -- Try parse int
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
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    v_res := public.vm_dict_get_item(p_locals_id, v_name);
                    IF v_res IS NULL THEN 
                        RAISE EXCEPTION 'UnboundLocalError: local variable "%" referenced before assignment (Line %)', v_name, v_pc; 
                    END IF;
                    v_stack := array_append(v_stack, v_res);

                -- STORE_FAST <name_idx>
                WHEN 'STORE_FAST' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int);
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    PERFORM public.vm_dict_set_item(p_locals_id, v_name, v_tos);

                -- BINARY_ADD
                WHEN 'BINARY_ADD' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    v_bound_method := public.vm_getattr(v_tos1, '__add__');
                    IF v_bound_method IS NULL THEN RAISE EXCEPTION 'AttributeError: __add__ not found'; END IF;
                    v_res := public.vm_call(v_bound_method, ARRAY[v_tos]);
                    v_stack := array_append(v_stack, v_res);

                -- COMPARE_OP <op_idx>
                WHEN 'COMPARE_OP' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1]; -- Right
                    v_tos1 := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1]; -- Left
                    
                    v_res := public.vm_compare(v_tos1, v_tos, v_oparg_int);
                    v_stack := array_append(v_stack, v_res);

                -- POP_JUMP_IF_FALSE <target_line>
                WHEN 'POP_JUMP_IF_FALSE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    if NOT public.vm_is_true(v_tos) THEN
                        v_pc := v_oparg_int; -- Jump!
                        CONTINUE; -- Skip standard increment
                    END IF;

                -- POP_JUMP_IF_TRUE <target_line>
                WHEN 'POP_JUMP_IF_TRUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    if public.vm_is_true(v_tos) THEN
                        v_pc := v_oparg_int; -- Jump!
                        CONTINUE; -- Skip standard increment
                    END IF;

                -- JUMP_FORWARD <delta> (Relative Jump)
                WHEN 'JUMP_FORWARD' THEN
                    v_pc := v_pc + v_oparg_int;
                    CONTINUE; -- Already added, assume target is relative to NEXT instruction usually, but here simplicity: relative to CURRENT.
                    -- Note: In real Python, it's relative to next. Let's adjust:
                    -- v_pc := v_pc + v_oparg_int + 1; -- But wait, we increment at bottom.
                    -- Let's stick to simple: JUMP_FORWARD 2 means skip 2 lines.
                    -- So target is v_pc + v_oparg_int. 
                    -- Since we increment at bottom, we should set v_pc = target - 1?
                    -- No, let's just CONTINUE to skip increment if we set exact line.
                    -- Let's define: JUMP_FORWARD N => PC = PC + N.

                -- JUMP_ABSOLUTE <target_line>
                WHEN 'JUMP_ABSOLUTE' THEN
                    v_pc := v_oparg_int;
                    CONTINUE;

                -- RETURN_VALUE
                WHEN 'RETURN_VALUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    RETURN v_tos;

                ELSE
                    -- Ignore unknown
                    NULL;
            END CASE;
            
        END IF;
        
        -- Increment PC
        v_pc := v_pc + 1;
    END LOOP;
    
    RETURN public.vm_get_none();
END;
$$ LANGUAGE plpgsql;
