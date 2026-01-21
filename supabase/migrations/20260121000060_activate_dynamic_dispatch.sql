-- =====================================================
-- Migration: Activate Dynamic Dispatch
-- Description: 
--   Replace hardcoded vm_native_dispatch with table-driven logic.
-- =====================================================

CREATE OR REPLACE FUNCTION public.vm_native_dispatch(fn_name text, args uuid[])
RETURNS uuid AS $$
DECLARE
    v_impl_name text;
    v_res uuid;
    v_sql text;
    
    -- We need to know WHICH function object we are calling to find the implementation.
    -- However, the current signature `vm_native_dispatch(fn_name, args)` implies 
    -- we only know the name. This is a design flaw in the OLD dispatcher.
    -- Ideally we should pass the function object ID itself.
    
    -- But wait, standard native functions (like built-in methods) are bound methods.
    -- When called, we usually have access to the Callable Object ID.
    -- vm_call calls `vm_native_dispatch`.
    -- Let's check vm_call signature:
    --    RETURN public.vm_native_dispatch(v_native_name, args);
    
    -- The caller (vm_call) KNOWS the callable_id (Base ID).
    -- But it currently extracts `v_native_name` and passes ONLY that.
    
    -- To support true dynamic dispatch, we must Lookup by Name OR modify vm_call to pass ID.
    -- Lookup by Name is ambiguous (list.pop vs dict.pop).
    -- But for now, since we only have `py_js_function_object`, checking `fn_name` is "okay" IF names are unique 
    -- OR if we assume all implementations with same name share semantic.
    
    -- BUT, we populated `fn_impl_name` in the table.
    -- So we can query: SELECT fn_impl_name FROM py_js_function_object WHERE fn_name = p_name LIMIT 1.
    -- This mimics the old behavior (name-based lookup) but uses the DB table instead of CASE.
    
BEGIN
    -- 1. Look up implementation name from table
    SELECT fn_impl_name INTO v_impl_name 
    FROM public.py_js_function_object 
    WHERE fn_name = fn_name 
    AND fn_impl_name IS NOT NULL
    LIMIT 1;
    
    -- 2. If implementation found, execute it
    IF v_impl_name IS NOT NULL THEN
        -- Dynamic Execution: SELECT public.func(args)
        -- We pass the UUID array 'args' as a single parameter ($1)
        v_sql := format('SELECT public.%I($1)', v_impl_name);
        EXECUTE v_sql INTO v_res USING args;
        RETURN v_res;
    END IF;

    -- 3. Fallback / Error
    -- If no implementation found, or it's a "dummy" function
    RAISE EXCEPTION 'NotImplementedError: Native function "%" implementation not found', fn_name;
END;
$$ LANGUAGE plpgsql;
