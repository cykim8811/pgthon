-- Migration: VM Implementation Step 5 (Comparisons)
-- Created at: 2026-01-18 00:00:00

-------------------------------------------------------
-- Helper: Comparison Logic
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_compare(p_left UUID, p_right UUID, p_op_idx INTEGER)
RETURNS UUID AS $$
DECLARE
    ID_TRUE_OBJ  UUID := '00000000-0000-4000-b000-000000000002';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000003';
    
    v_l_type UUID;
    v_r_type UUID;
    v_l_val BIGINT;
    v_r_val BIGINT;
    v_result BOOLEAN;
BEGIN
    -- Get Types is expensive if we do it every time, but necessary for correct dispatch.
    -- Optimization: Check Int/Bool first as they share py_long_object structure.
    
    -- Try fetching integer values directly (Optimistic)
    SELECT long_value INTO v_l_val FROM public.py_long_object WHERE ob_base = p_left;
    SELECT long_value INTO v_r_val FROM public.py_long_object WHERE ob_base = p_right;
    
    IF v_l_val IS NOT NULL AND v_r_val IS NOT NULL THEN
        -- Both are Integers (or Bools)
        CASE p_op_idx
            WHEN 0 THEN v_result := (v_l_val < v_r_val);  -- <
            WHEN 1 THEN v_result := (v_l_val <= v_r_val); -- <=
            WHEN 2 THEN v_result := (v_l_val = v_r_val);  -- ==
            WHEN 3 THEN v_result := (v_l_val <> v_r_val); -- !=
            WHEN 4 THEN v_result := (v_l_val > v_r_val);  -- >
            WHEN 5 THEN v_result := (v_l_val >= v_r_val); -- >=
            ELSE v_result := FALSE;
        END CASE;
        
        IF v_result THEN RETURN ID_TRUE_OBJ; ELSE RETURN ID_FALSE_OBJ; END IF;
    END IF;
    
    -- Fallback for other types (Strings, etc.)
    -- TODO: Implement generic __lt__, __eq__ dispatch
    -- For now, default to equality check on IDs for objects
    IF p_op_idx = 2 THEN -- == 
        IF p_left = p_right THEN RETURN ID_TRUE_OBJ; ELSE RETURN ID_FALSE_OBJ; END IF;
    ELSIF p_op_idx = 3 THEN -- !=
        IF p_left <> p_right THEN RETURN ID_TRUE_OBJ; ELSE RETURN ID_FALSE_OBJ; END IF;
    END IF;
    
    -- If comparison not supported
    RAISE EXCEPTION 'TypeError: Comparison not supported between objects yet (Only Ints supported)';
END;
$$ LANGUAGE plpgsql;
