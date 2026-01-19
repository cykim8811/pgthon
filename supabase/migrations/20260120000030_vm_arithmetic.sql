-- =====================================================
-- Migration: Advanced Arithmetic Operations
-- Description: vm_create_function helper and vm_add with custom object methods
-- =====================================================

-------------------------------------------------------
-- Helper: vm_create_function
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_create_function(
    p_id uuid,        -- Base ID
    p_func_id uuid,   -- Table ID  
    p_code_id uuid,   -- Code object Table ID
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
-- vm_add: Addition with method dispatch
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_add(p_left uuid, p_right uuid)
RETURNS uuid AS $$
DECLARE
    -- Type IDs for Fast Path
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    
    v_l_type uuid;
    v_r_type uuid;
    v_l_val bigint;
    v_r_val bigint;
    v_res bigint;
    v_l_str text;
    v_r_str text;
    
    -- For Method Dispatch
    v_method uuid;
BEGIN
    v_l_type := public.vm_get_type(p_left);
    v_r_type := public.vm_get_type(p_right);
    
    -----------------------------------------------------------------
    -- 1. FAST PATH: Built-in Types Optimizations
    -----------------------------------------------------------------
    
    -- Integer Addition
    IF v_l_type = ID_INT_TYPE AND v_r_type = ID_INT_TYPE THEN
        v_l_val := public.vm_get_int_value(p_left);
        v_r_val := public.vm_get_int_value(p_right);
        RETURN public.vm_create_int(v_l_val + v_r_val);
    END IF;
    
    -- String Concatenation
    IF v_l_type = ID_STR_TYPE AND v_r_type = ID_STR_TYPE THEN
        v_l_str := public.vm_get_str_value(p_left);
        v_r_str := public.vm_get_str_value(p_right);
        RETURN public.vm_create_str(v_l_str || v_r_str);
    END IF;
    
    -----------------------------------------------------------------
    -- 2. SLOW PATH: Method Dispatch (__add__)
    -----------------------------------------------------------------
    -- Try p_left.__add__(p_right)
    BEGIN
        v_method := public.vm_getattr(p_left, '__add__');
        IF v_method IS NOT NULL THEN
            return public.vm_call(v_method, ARRAY[p_right]);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    -----------------------------------------------------------------
    -- 3. SLOW PATH: Reflected Method Dispatch (__radd__)
    -----------------------------------------------------------------
    -- Try p_right.__radd__(p_left)
    BEGIN
        v_method := public.vm_getattr(p_right, '__radd__');
        IF v_method IS NOT NULL THEN
            return public.vm_call(v_method, ARRAY[p_left]);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    -----------------------------------------------------------------
    -- 4. FAILURE
    -----------------------------------------------------------------
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for +';
END;
$$ LANGUAGE plpgsql;
