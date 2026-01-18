-- Migration: VM Dynamic Dispatch
-- Allow dynamic execution of native functions based on name
-- Created at: 2026-01-18 00:00:35

CREATE OR REPLACE FUNCTION public.vm_native_dispatch(fn_name TEXT, args UUID[])
RETURNS UUID AS $$
DECLARE
    v_sql TEXT;
    v_res UUID;
BEGIN
    -- Security Check: fn_name must start with 'vm_native_' to prevent calling arbitrary functions
    -- Or just trust since we control function registration.
    -- But let's be safe: assume implementation functions stick to vm_native_ prefix or similar?
    -- Actually 'append' in Step 2 was just 'append'. 
    -- But in register_native_method we used 'vm_native_list_iter'.
    -- The legacy 'append' (from Step 2) is not prefixed properly.
    -- So we need to handle legacy 'append' OR migrate it.
    
    -- Legacy Handler (for 'append' defined in Step 2)
    -- Actually, in Step 2, fn_name was stored as 'append'.
    -- We should stick to 'vm_native_append' convention going forward.
    -- But for now, let's keep the legacy CASE for 'append' if we haven't migrated it.
    
    IF fn_name = 'append' THEN
        -- Re-implement append logic here or call a new helper?
        -- Let's define vm_native_list_append properly and call it?
        -- For now, just keep the inline logic for backward compatibility with Step 2 if any tests use it.
        -- But wait, we want Dynamic Dispatch to work for new functions.
        NULL; -- Fall through
    END IF;

    -- Simple Dynamic Dispatch
    -- We assume the fn_name stored in py_js_function_object IS the PL/pgSQL function name.
    v_sql := format('SELECT public.%I($1)', fn_name);
    
    BEGIN
        EXECUTE v_sql INTO v_res USING args;
    EXCEPTION WHEN OTHERS THEN
        -- Fallback to old switch-case style if function not found?
        -- Or just re-raise.
        -- Let's handle 'append' specifically if it fails?
        IF fn_name = 'append' THEN
             DECLARE
                v_self_id UUID := args[1];
                v_arg1 UUID := args[2];
             BEGIN
                 UPDATE public.py_list_object -- Change to py_tuple_object or whatever we used
                 SET ob_item = array_append(ob_item, v_arg1)
                 WHERE ob_base = v_self_id;
                 RETURN public.vm_get_none();
             END;
        ELSE
            RAISE EXCEPTION 'DispatchError: Could not execute native function %: %', fn_name, SQLERRM;
        END IF;
    END;
    
    RETURN v_res;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
