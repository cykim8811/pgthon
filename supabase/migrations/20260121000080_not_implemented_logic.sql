-- =====================================================
-- Migration: NotImplemented Logic and Reverse Ops Support
-- Description: 
--   1. Define NotImplemented singleton.
--   2. Update vm_add/sub/mul to handle NotImplemented retries.
--   3. Update native implementation to return NotImplemented instead of raising error.
-- =====================================================

-------------------------------------------------------
-- 1. NotImplemented Singleton Helpers
-------------------------------------------------------
-- We define a fixed ID for NotImplemented.
-- Let's use ...a000-000000000000 for None (usually), 
-- let's use ...a000-00000000000F (15) for NotImplemented.

CREATE OR REPLACE FUNCTION public.vm_get_not_implemented()
RETURNS uuid AS $$
DECLARE
    -- Ensuring we have a singleton. 
    -- For now, we can create it on demand or assume it exists if we bootstrapped it.
    -- Let's trust it exists or create simple one.
    -- Actually, to avoid complexity, let's just pick a UUID and insert it if missing.
    ID_NOT_IMPLEMENTED uuid := '00000000-0000-4000-a000-00000000000f';
    ID_OBJ_TYPE uuid := '00000000-0000-4000-a000-000000000001'; -- Generic Object Type
BEGIN
    -- Optimistic check: if we assume bootstrapping is done properly, just return ID.
    -- But to be safe in this function:
    INSERT INTO public.py_object (id, ob_type) 
    VALUES (ID_NOT_IMPLEMENTED, ID_OBJ_TYPE)
    ON CONFLICT (id) DO NOTHING;
    
    RETURN ID_NOT_IMPLEMENTED;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 2. Update Native Implementations (Add/Sub/Mul/etc)
-------------------------------------------------------

-- 2.1 int.__add__
CREATE OR REPLACE FUNCTION public.vm_impl_int_add(args uuid[])
RETURNS uuid AS $$
DECLARE
    v_l_val bigint;
    v_r_val bigint;
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    v_r_type uuid;
BEGIN
    v_r_type := public.vm_get_type(args[2]);
    
    IF v_r_type = ID_INT_TYPE THEN
        v_l_val := public.vm_get_int_value(args[1]);
        v_r_val := public.vm_get_int_value(args[2]);
        RETURN public.vm_create_int(v_l_val + v_r_val);
    END IF;
    
    -- Return NotImplemented for unknown types
    RETURN public.vm_get_not_implemented();
END;
$$ LANGUAGE plpgsql;

-- 2.2 int.__sub__
CREATE OR REPLACE FUNCTION public.vm_impl_int_sub(args uuid[])
RETURNS uuid AS $$
DECLARE
    v_i1 bigint;
    v_i2 bigint;
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    v_r_type uuid;
BEGIN
    v_r_type := public.vm_get_type(args[2]);
    
    IF v_r_type = ID_INT_TYPE THEN
        v_i1 := public.vm_get_int_value(args[1]);
        v_i2 := public.vm_get_int_value(args[2]);
        RETURN public.vm_create_int(v_i1 - v_i2);
    END IF;

    RETURN public.vm_get_not_implemented();
END;
$$ LANGUAGE plpgsql;

-- 2.3 int.__mul__
CREATE OR REPLACE FUNCTION public.vm_impl_int_mul(args uuid[])
RETURNS uuid AS $$
DECLARE
    v_i1 bigint;
    v_i2 bigint;
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    v_r_type uuid;
BEGIN
    v_r_type := public.vm_get_type(args[2]);
    
    IF v_r_type = ID_INT_TYPE THEN
        v_i1 := public.vm_get_int_value(args[1]);
        v_i2 := public.vm_get_int_value(args[2]);
        RETURN public.vm_create_int(v_i1 * v_i2);
    END IF;

    RETURN public.vm_get_not_implemented();
END;
$$ LANGUAGE plpgsql;

-- 2.4 int.__floordiv__
CREATE OR REPLACE FUNCTION public.vm_impl_int_floordiv(args uuid[])
RETURNS uuid AS $$
DECLARE
    v_i1 bigint;
    v_i2 bigint;
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    v_r_type uuid;
BEGIN
    v_r_type := public.vm_get_type(args[2]);
    
    IF v_r_type = ID_INT_TYPE THEN
        v_i1 := public.vm_get_int_value(args[1]);
        v_i2 := public.vm_get_int_value(args[2]);
        IF v_i2 = 0 THEN RAISE EXCEPTION 'ZeroDivisionError: integer division or modulo by zero'; END IF;
        RETURN public.vm_create_int(v_i1 / v_i2);
    END IF;

    RETURN public.vm_get_not_implemented();
END;
$$ LANGUAGE plpgsql;

-- 2.5 int.__mod__
CREATE OR REPLACE FUNCTION public.vm_impl_int_mod(args uuid[])
RETURNS uuid AS $$
DECLARE
    v_i1 bigint;
    v_i2 bigint;
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    v_r_type uuid;
BEGIN
    v_r_type := public.vm_get_type(args[2]);
    
    IF v_r_type = ID_INT_TYPE THEN
        v_i1 := public.vm_get_int_value(args[1]);
        v_i2 := public.vm_get_int_value(args[2]);
        IF v_i2 = 0 THEN RAISE EXCEPTION 'ZeroDivisionError: integer division or modulo by zero'; END IF;
        RETURN public.vm_create_int(v_i1 % v_i2);
    END IF;

    RETURN public.vm_get_not_implemented();
END;
$$ LANGUAGE plpgsql;


-------------------------------------------------------
-- 3. Update vm_add (Dispatcher)
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
    v_l_str text;
    v_r_str text;
    
    v_method uuid;
    v_res uuid;
    v_not_implemented uuid := public.vm_get_not_implemented();
BEGIN
    v_l_type := public.vm_get_type(p_left);
    v_r_type := public.vm_get_type(p_right);
    
    -- 1. FAST PATH (Built-in Optimization)
    IF v_l_type = ID_INT_TYPE AND v_r_type = ID_INT_TYPE THEN
        v_l_val := public.vm_get_int_value(p_left);
        v_r_val := public.vm_get_int_value(p_right);
        RETURN public.vm_create_int(v_l_val + v_r_val);
    END IF;
    
    IF v_l_type = ID_STR_TYPE AND v_r_type = ID_STR_TYPE THEN
        v_l_str := public.vm_get_str_value(p_left);
        v_r_str := public.vm_get_str_value(p_right);
        RETURN public.vm_create_str(v_l_str || v_r_str);
    END IF;
    
    -- 2. Try p_left.__add__(p_right)
    BEGIN
        v_method := public.vm_getattr(p_left, '__add__');
        IF v_method IS NOT NULL THEN
            v_res := public.vm_call(v_method, ARRAY[p_right]);
            
            -- If Result is NOT NotImplemented, return it
            IF v_res IS DISTINCT FROM v_not_implemented THEN
                RETURN v_res;
            END IF;
            -- If NotImplemented, Fallthrough to step 3
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL; -- Ignore lookup errors
    END;

    -- 3. Try p_right.__radd__(p_left) (Reflected Op)
    -- Only if types are different or (same type but different logic? strictly if types diff)
    -- Python rule: if right is subtype of left, try right.__radd__ first. (Ignored for VM simplicity now)
    
    BEGIN
        v_method := public.vm_getattr(p_right, '__radd__');
        IF v_method IS NOT NULL THEN
            v_res := public.vm_call(v_method, ARRAY[p_left]);
            
            IF v_res IS DISTINCT FROM v_not_implemented THEN
                RETURN v_res;
            END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    -- 4. FAILURE
    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for +';
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 4. Update vm_sub (Dispatcher)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_sub(p_left uuid, p_right uuid)
RETURNS uuid AS $$
DECLARE
    -- Type IDs
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    v_l_type uuid;
    v_r_type uuid;
    v_l_val bigint;
    v_r_val bigint;
    
    v_method uuid;
    v_res uuid;
    v_not_implemented uuid := public.vm_get_not_implemented();
BEGIN
    v_l_type := public.vm_get_type(p_left);
    v_r_type := public.vm_get_type(p_right);
    
    -- 1. FAST PATH
    IF v_l_type = ID_INT_TYPE AND v_r_type = ID_INT_TYPE THEN
        v_l_val := public.vm_get_int_value(p_left);
        v_r_val := public.vm_get_int_value(p_right);
        RETURN public.vm_create_int(v_l_val - v_r_val);
    END IF;

    -- 2. Try __sub__
    BEGIN
        v_method := public.vm_getattr(p_left, '__sub__');
        IF v_method IS NOT NULL THEN
            v_res := public.vm_call(v_method, ARRAY[p_right]);
            IF v_res IS DISTINCT FROM v_not_implemented THEN RETURN v_res; END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- 3. Try __rsub__
    BEGIN
        v_method := public.vm_getattr(p_right, '__rsub__');
        IF v_method IS NOT NULL THEN
            v_res := public.vm_call(v_method, ARRAY[p_left]);
            IF v_res IS DISTINCT FROM v_not_implemented THEN RETURN v_res; END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for -';
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 5. Update vm_mul (Dispatcher)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_mul(p_left uuid, p_right uuid)
RETURNS uuid AS $$
DECLARE
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    v_l_type uuid;
    v_r_type uuid;
    v_l_val bigint;
    v_r_val bigint;
    v_method uuid;
    v_res uuid;
    v_not_implemented uuid := public.vm_get_not_implemented();
BEGIN
    v_l_type := public.vm_get_type(p_left);
    v_r_type := public.vm_get_type(p_right);
    
    -- 1. FAST PATH
    IF v_l_type = ID_INT_TYPE AND v_r_type = ID_INT_TYPE THEN
        v_l_val := public.vm_get_int_value(p_left);
        v_r_val := public.vm_get_int_value(p_right);
        RETURN public.vm_create_int(v_l_val * v_r_val);
    END IF;

    -- 2. Try __mul__
    BEGIN
        v_method := public.vm_getattr(p_left, '__mul__');
        IF v_method IS NOT NULL THEN
            v_res := public.vm_call(v_method, ARRAY[p_right]);
            IF v_res IS DISTINCT FROM v_not_implemented THEN RETURN v_res; END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- 3. Try __rmul__
    BEGIN
        v_method := public.vm_getattr(p_right, '__rmul__');
        IF v_method IS NOT NULL THEN
            v_res := public.vm_call(v_method, ARRAY[p_left]);
            IF v_res IS DISTINCT FROM v_not_implemented THEN RETURN v_res; END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    RAISE EXCEPTION 'TypeError: unsupported operand type(s) for *';
END;
$$ LANGUAGE plpgsql;
