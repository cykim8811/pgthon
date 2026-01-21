-- =====================================================
-- Migration: Fix Infinite Recursion in Native Implementations
-- Description: 
--   Native implementations must perform ACTUAL operations, 
--   not call back into the polymorphic dispatcher (vm_add).
-- =====================================================

-- 1. int.__add__(self, other)
CREATE OR REPLACE FUNCTION public.vm_impl_int_add(args uuid[])
RETURNS uuid AS $$
DECLARE
    v_l_val bigint;
    v_r_val bigint;
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    v_r_type uuid;
BEGIN
    -- Check type of 'other' (args[2])
    v_r_type := public.vm_get_type(args[2]);
    
    -- Int + Int
    IF v_r_type = ID_INT_TYPE THEN
        v_l_val := public.vm_get_int_value(args[1]);
        v_r_val := public.vm_get_int_value(args[2]);
        RETURN public.vm_create_int(v_l_val + v_r_val);
    END IF;
    
    -- Int + Unknown -> Return NotImplemented (or raise TypeError for now)
    -- Ideally return NotImplemented singleton so vm_add can try __radd__.
    -- usage: RETURN public.vm_get_not_implemented();
    
    -- For now, consistent with previous behavior: Raise TypeError if strict, or fallback.
    -- But vm_add handles fallback. 
    -- If native impl fails, it means this type doesn't support the other operand.
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for +';
END;
$$ LANGUAGE plpgsql;

-- 2. int.__mul__(self, other) - Just to be safe, though this was calling vm_create_int(a*b).
-- Let's double check vm_impl_int_mul from previous step.
-- It was: RETURN public.vm_create_int(v_i1 * v_i2); -- This is SAFE. O(1).

-- Double check vm_impl_int_sub.
-- It was: RETURN public.vm_create_int(v_i1 - v_i2); -- This is SAFE.

-- So only __add__ was dangerous because it delegated back to vm_add.
