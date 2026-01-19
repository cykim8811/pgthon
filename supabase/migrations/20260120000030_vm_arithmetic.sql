-- =====================================================
-- Migration: Advanced Arithmetic Operations
-- Description: Override vm_add to support custom object methods (__add__, __radd__)
-- =====================================================

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
    v_call_res uuid;
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
        RAISE NOTICE 'Debug: __add__ lookup result: %', v_method;
        
        IF v_method IS NOT NULL THEN
            -- vm_call handles bound method 'self' insertion
            return public.vm_call(v_method, ARRAY[p_right]);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Debug: __add__ execution failed: %', SQLERRM;
        -- If lookup or call fails, ignore and try next strategy
        -- In a real VM, we should check for NotImplemented return value
        NULL;
    END;

    -----------------------------------------------------------------
    -- 3. SLOW PATH: Reflected Method Dispatch (__radd__)
    -----------------------------------------------------------------
    -- Try p_right.__radd__(p_left)
    -- Only if types are different or explicit override logic (simplified here)
    BEGIN
        v_method := public.vm_getattr(p_right, '__radd__');
        IF v_method IS NOT NULL THEN
            -- p_right is self, p_left is argument
            return public.vm_call(v_method, ARRAY[p_left]);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    -----------------------------------------------------------------
    -- 4. FAILURE
    -----------------------------------------------------------------
    -- TODO: Raise proper TypeError object when Exception system is fully integrated
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for +';
END;
$$ LANGUAGE plpgsql;
