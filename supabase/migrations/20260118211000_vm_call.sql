-- =====================================================
-- Migration: VM Call Mechanism
-- Description: Function call dispatch for bound methods, native functions, and bytecode functions
-- =====================================================

-------------------------------------------------------
-- vm_call: Main call dispatcher
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_call(callable_id uuid, args uuid[])
RETURNS uuid AS $$
DECLARE
    v_type_id uuid;
    v_native_name text;
    
    ID_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000008';
    ID_JS_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000012';
    ID_METHOD_TYPE uuid := '00000000-0000-4000-a000-000000000013';
    ID_DCT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
    
    -- Bound Method variables
    v_im_func uuid;
    v_im_self uuid;
    v_new_args uuid[];
    
    -- Bytecode function variables
    v_code_id uuid;
    v_locals_id uuid;
    v_base_locals uuid;
    v_varnames_id uuid;
    v_arg_name_uuid uuid;
    v_arg_name_str text;
    i integer;
    v_arg_count integer;
BEGIN
    -- 1. Get Type of Callable
    v_type_id := public.vm_get_type(callable_id);
    
    -----------------------------------------------------------------
    -- 2. BOUND METHOD: Unwrap and prepend self to args
    -----------------------------------------------------------------
    IF v_type_id = ID_METHOD_TYPE THEN
        SELECT im_func, im_self INTO v_im_func, v_im_self 
        FROM public.py_bound_method_object 
        WHERE ob_base = callable_id;
        
        -- Prepend self to arguments
        v_new_args := array_prepend(v_im_self, args);
        
        -- Recursive call with unwrapped function
        RETURN public.vm_call(v_im_func, v_new_args);
    END IF;
    
    -----------------------------------------------------------------
    -- 3. NATIVE FUNCTION: Dispatch to native implementation
    -----------------------------------------------------------------
    IF v_type_id = ID_JS_FNC_TYPE THEN
        SELECT fn_name INTO v_native_name 
        FROM public.py_js_function_object 
        WHERE ob_base = callable_id;
        
        RETURN public.vm_native_dispatch(v_native_name, args);
    END IF;
    
    -----------------------------------------------------------------
    -- 4. PYTHON BYTECODE FUNCTION: Create locals and run frame
    -----------------------------------------------------------------
    IF v_type_id = ID_FNC_TYPE THEN
        -- Get code object
        SELECT func_code INTO v_code_id 
        FROM public.py_function_object 
        WHERE ob_base = callable_id;
        
        -- Create locals dictionary
        v_base_locals := gen_random_uuid();
        v_locals_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (v_base_locals, ID_DCT_TYPE);
        INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (v_locals_id, v_base_locals, 0);
        
        -- Get varnames for argument binding
        SELECT c.co_varnames, c.co_argcount INTO v_varnames_id, v_arg_count
        FROM public.py_code_object c
        WHERE c.id = v_code_id;
        
        -- Bind arguments to locals
        IF array_length(args, 1) > 0 THEN
            FOR i IN 1..array_length(args, 1) LOOP
                -- Get argument name from varnames tuple (0-indexed)
                v_arg_name_uuid := public.vm_tuple_getitem(v_varnames_id, i - 1);
                SELECT str_value INTO v_arg_name_str 
                FROM public.py_unicode_object 
                WHERE ob_base = v_arg_name_uuid;
                
                -- Set in locals
                PERFORM public.vm_dict_set_item(v_locals_id, v_arg_name_str, args[i]);
            END LOOP;
        END IF;

        -- Run frame with code and locals
        RETURN public.vm_run_frame(v_code_id, v_locals_id, NULL);
    END IF;
    
    RAISE EXCEPTION 'TypeError: Object % is not callable', callable_id;
END;
$$ LANGUAGE plpgsql;
