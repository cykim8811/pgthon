-- =====================================================
-- Migration: Activate Dynamic Dispatch (Fix Ambiguity)
-- Description: 
--   Fix "Ambiguous column reference" error by renaming parameter.
-- =====================================================

-- Drop old function first to change parameter name cleanly (optional but safer)
DROP FUNCTION IF EXISTS public.vm_native_dispatch(text, uuid[]);

CREATE OR REPLACE FUNCTION public.vm_native_dispatch(p_fn_name text, args uuid[])
RETURNS uuid AS $$
DECLARE
    v_impl_name text;
    v_res uuid;
    v_sql text;
BEGIN
    -- 1. Look up implementation name from table using explicit parameter
    SELECT fn_impl_name INTO v_impl_name 
    FROM public.py_builtin_function_object 
    WHERE fn_name = p_fn_name 
    AND fn_impl_name IS NOT NULL
    LIMIT 1;
    
    -- 2. If implementation found, execute it
    IF v_impl_name IS NOT NULL THEN
        v_sql := format('SELECT public.%I($1)', v_impl_name);
        EXECUTE v_sql INTO v_res USING args;
        RETURN v_res;
    END IF;

    -- 3. Fallback / Error
    RAISE EXCEPTION 'NotImplementedError: Native function "%" implementation not found', p_fn_name;
END;
$$ LANGUAGE plpgsql;
