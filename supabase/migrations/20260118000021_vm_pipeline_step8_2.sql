-- Migration: VM Implementation Step 8-2 (Iterator Opcodes)
-- Created at: 2026-01-18 00:00:21

-------------------------------------------------------
-- VM Run Frame Update (Add GET_ITER, FOR_ITER)
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
                BEGIN v_oparg_int := v_oparg::INTEGER; EXCEPTION WHEN OTHERS THEN v_oparg_int := 0; END;
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

                -- LOAD_ATTR
                WHEN 'LOAD_ATTR' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_res := public.vm_tuple_getitem(v_varnames_id, v_oparg_int); 
                    SELECT str_value INTO v_name FROM public.py_unicode_object WHERE ob_base = v_res;
                    v_res := public.vm_getattr(v_tos, v_name);
                    IF v_res IS NULL THEN RAISE EXCEPTION 'AttributeError: object has no attribute "%"', v_name; END IF;
                    v_stack := array_append(v_stack, v_res);

                -- GET_ITER (TOS -> iter(TOS))
                WHEN 'GET_ITER' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    
                    -- Call __iter__
                    v_bound_method := public.vm_getattr(v_tos, '__iter__');
                    IF v_bound_method IS NULL THEN RAISE EXCEPTION 'TypeError: Object is not iterable'; END IF;
                    v_res := public.vm_call(v_bound_method, ARRAY[]::UUID[]);
                    
                    v_stack := array_append(v_stack, v_res);

                -- FOR_ITER <delta> (TOS is iterator. Call next. If NULL, Pop iter and Jump. Else Push value.)
                WHEN 'FOR_ITER' THEN
                    v_tos := v_stack[array_length(v_stack, 1)]; -- Iterator (Peek, don't pop yet in loop)
                    
                    -- Call __next__
                    -- Optimization: Direct native call if internal iterator?
                    -- For now, generic: __next__()
                    v_bound_method := public.vm_getattr(v_tos, '__next__');
                    v_res := public.vm_call(v_bound_method, ARRAY[]::UUID[]);
                    
                    IF v_res IS NULL THEN
                        -- StopIteration
                        -- Pop Iterator
                        v_stack := v_stack[1:array_length(v_stack, 1)-1];
                        -- Jump Forward
                        v_pc := v_pc + v_oparg_int; 
                        CONTINUE;
                    ELSE
                        -- Push Value
                        v_stack := array_append(v_stack, v_res);
                    END IF;

                -- COMPARE_OP
                WHEN 'COMPARE_OP' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_tos1 := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    v_res := public.vm_compare(v_tos1, v_tos, v_oparg_int);
                    v_stack := array_append(v_stack, v_res);

                -- JUMPS
                WHEN 'POP_JUMP_IF_FALSE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    if NOT public.vm_is_true(v_tos) THEN v_pc := v_oparg_int; CONTINUE; END IF;
                WHEN 'POP_JUMP_IF_TRUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    v_stack := v_stack[1:array_length(v_stack, 1)-1];
                    if public.vm_is_true(v_tos) THEN v_pc := v_oparg_int; CONTINUE; END IF;
                WHEN 'JUMP_FORWARD' THEN
                    v_pc := v_pc + v_oparg_int; CONTINUE;
                WHEN 'JUMP_ABSOLUTE' THEN
                    v_pc := v_oparg_int; CONTINUE;

                -- RETURN_VALUE
                WHEN 'RETURN_VALUE' THEN
                    v_tos := v_stack[array_length(v_stack, 1)];
                    RETURN v_tos;

                -- CALL_FUNCTION
                WHEN 'CALL_FUNCTION' THEN
                    v_oparg_int := v_oparg::INTEGER;
                    DECLARE v_args UUID[]; v_func UUID; i INT; BEGIN
                        FOR i IN 1..v_oparg_int LOOP
                            v_args := array_prepend(v_stack[array_length(v_stack, 1)], v_args);
                            v_stack := v_stack[1:array_length(v_stack, 1)-1];
                        END LOOP;
                        v_func := v_stack[array_length(v_stack, 1)];
                        v_stack := v_stack[1:array_length(v_stack, 1)-1];
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
