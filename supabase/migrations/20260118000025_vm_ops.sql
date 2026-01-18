-- Migration: VM Ops (Step 8-Lite)
-- Basic Arithmetic Ops Helpers
-- Created at: 2026-01-18 00:00:25

-------------------------------------------------------
-- Helper: vm_add
-- Implements a + b
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_add(p_left UUID, p_right UUID)
RETURNS UUID AS $$
DECLARE
    v_l_type UUID;
    v_r_type UUID;
    v_l_val BIGINT;
    v_r_val BIGINT;
    v_res BIGINT;
    
    v_l_str TEXT;
    v_r_str TEXT;
    
    v_base UUID;
    v_id UUID;
    
    -- Type IDs
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
BEGIN
    v_l_type := public.vm_get_type(p_left);
    v_r_type := public.vm_get_type(p_right);
    
    -- 1. Integer Addition
    IF v_l_type = ID_INT_TYPE AND v_r_type = ID_INT_TYPE THEN
        SELECT long_value INTO v_l_val FROM public.py_long_object WHERE ob_base = p_left;
        SELECT long_value INTO v_r_val FROM public.py_long_object WHERE ob_base = p_right;
        
        v_res := v_l_val + v_r_val;
        
        -- Create Result Object
        v_base := gen_random_uuid();
        v_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (v_base, ID_INT_TYPE);
        INSERT INTO public.py_long_object (id, ob_base, long_value) VALUES (v_id, v_base, v_res);
        
        RETURN v_base;
    END IF;
    
    -- 2. String Concatenation
    IF v_l_type = ID_STR_TYPE AND v_r_type = ID_STR_TYPE THEN
        SELECT str_value INTO v_l_str FROM public.py_unicode_object WHERE ob_base = p_left;
        SELECT str_value INTO v_r_str FROM public.py_unicode_object WHERE ob_base = p_right;
        
        -- Create Result Object
        v_base := gen_random_uuid();
        v_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (v_base, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (v_id, v_base, v_l_str || v_r_str);
        
        RETURN v_base;
    END IF;
    
    -- 3. Fallback to __add__ (TODO)
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for +';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
