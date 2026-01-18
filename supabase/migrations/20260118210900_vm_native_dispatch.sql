-- =====================================================
-- Migration: VM Native Dispatch & Operations
-- Description: Native function implementations and arithmetic operations
-- =====================================================

-------------------------------------------------------
-- 1. vm_add: Addition operation (int + int, str + str)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_add(p_left uuid, p_right uuid)
RETURNS uuid AS $$
DECLARE
    v_l_type uuid;
    v_r_type uuid;
    v_l_val bigint;
    v_r_val bigint;
    v_res bigint;
    
    v_l_str text;
    v_r_str text;
    
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
BEGIN
    v_l_type := public.vm_get_type(p_left);
    v_r_type := public.vm_get_type(p_right);
    
    -- 1. Integer Addition
    IF v_l_type = ID_INT_TYPE AND v_r_type = ID_INT_TYPE THEN
        v_l_val := public.vm_get_int_value(p_left);
        v_r_val := public.vm_get_int_value(p_right);
        v_res := v_l_val + v_r_val;
        
        RETURN public.vm_create_int(v_res);
    END IF;
    
    -- 2. String Concatenation
    IF v_l_type = ID_STR_TYPE AND v_r_type = ID_STR_TYPE THEN
        SELECT str_value INTO v_l_str FROM public.py_unicode_object WHERE ob_base = p_left;
        SELECT str_value INTO v_r_str FROM public.py_unicode_object WHERE ob_base = p_right;
        
        RETURN public.vm_create_str(v_l_str || v_r_str);
    END IF;
    
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for +';
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 2. vm_native_dispatch: Dispatcher for native functions
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_native_dispatch(fn_name text, args uuid[])
RETURNS uuid AS $$
DECLARE
    v_self_id uuid;
    v_arg1 uuid;
    
    -- For arithmetic operations
    v_i1 bigint;
    v_i2 bigint;
    v_res bigint;
BEGIN
    -- Switch-case for native functions/methods
    CASE fn_name
        -----------------------------------------------------------------
        -- LIST METHODS
        -----------------------------------------------------------------
        WHEN 'append' THEN
            IF array_length(args, 1) < 2 THEN
                RAISE EXCEPTION 'TypeError: append() takes exactly one argument';
            END IF;
            
            v_self_id := args[1]; -- self
            v_arg1 := args[2];    -- item
            
            -- Update list storage (using tuple_object for storage)
            UPDATE public.py_list_object
            SET ob_item = array_append(ob_item, v_arg1)
            WHERE ob_base = v_self_id;
            
            RETURN public.vm_get_none();
            
        -----------------------------------------------------------------
        -- INT METHODS (Magic Methods)
        -----------------------------------------------------------------
        WHEN '__add__' THEN
            RETURN public.vm_add(args[1], args[2]);
            
        WHEN '__sub__' THEN
            v_i1 := public.vm_get_int_value(args[1]);
            v_i2 := public.vm_get_int_value(args[2]);
            RETURN public.vm_create_int(v_i1 - v_i2);
            
        WHEN '__mul__' THEN
            v_i1 := public.vm_get_int_value(args[1]);
            v_i2 := public.vm_get_int_value(args[2]);
            RETURN public.vm_create_int(v_i1 * v_i2);
            
        WHEN '__floordiv__' THEN
            v_i1 := public.vm_get_int_value(args[1]);
            v_i2 := public.vm_get_int_value(args[2]);
            IF v_i2 = 0 THEN RAISE EXCEPTION 'ZeroDivisionError: integer division or modulo by zero'; END IF;
            RETURN public.vm_create_int(v_i1 / v_i2);
            
        WHEN '__mod__' THEN
            v_i1 := public.vm_get_int_value(args[1]);
            v_i2 := public.vm_get_int_value(args[2]);
            IF v_i2 = 0 THEN RAISE EXCEPTION 'ZeroDivisionError: integer division or modulo by zero'; END IF;
            RETURN public.vm_create_int(v_i1 % v_i2);
            
        -----------------------------------------------------------------
        -- STR METHODS
        -----------------------------------------------------------------
        WHEN 'upper', 'lower', 'strip' THEN
            -- These would need actual implementations
            -- For now, return None as placeholder
            RETURN public.vm_get_none();
            
        -----------------------------------------------------------------
        -- FALLBACK
        -----------------------------------------------------------------
        ELSE
            -- Try dynamic dispatch: attempt to call public.vm_native_<fn_name>
            -- This allows for extensible native functions
            DECLARE
                v_sql text;
                v_res uuid;
            BEGIN
                v_sql := format('SELECT public.vm_native_%I($1)', fn_name);
                EXECUTE v_sql INTO v_res USING args;
                RETURN v_res;
            EXCEPTION WHEN OTHERS THEN
                RAISE EXCEPTION 'NotImplementedError: Native function "%" is not implemented yet', fn_name;
            END;
    END CASE;
END;
$$ LANGUAGE plpgsql;
