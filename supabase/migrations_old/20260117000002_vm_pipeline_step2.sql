-- Migration: VM Implementation Step 2 (Call Dispatch & Native Append)
-- Created at: 2026-01-17 00:00:02

DO $$
BEGIN
    -- Ensure native function types are registered if not already
    -- (Should be handled by previous migrations)
END $$;

-------------------------------------------------------
-- 1. Helper: Get None UUID
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_get_none()
RETURNS UUID AS $$
DECLARE
    ID_NONE_TYPE UUID := '00000000-0000-4000-a000-000000000009';
    v_none_id UUID;
BEGIN
    -- Singleton Pattern: Find the instance of NoneType
    SELECT id INTO v_none_id FROM public.py_object WHERE ob_type = ID_NONE_TYPE LIMIT 1;
    RETURN v_none_id;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 2. Native Dispatcher (Implementation of built-ins)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_native_dispatch(fn_name TEXT, args UUID[])
RETURNS UUID AS $$
DECLARE
    v_ret UUID;
    v_self_id UUID;
    v_arg1 UUID;
    v_list_id UUID;
    v_current_items UUID[];
BEGIN
    -- Switch-Case for Native Functions
    CASE fn_name
        -- [ list.append(self, item) ]
        WHEN 'append' THEN
            IF array_length(args, 1) < 2 THEN
                RAISE EXCEPTION 'TypeError: append() takes exactly one argument';
            END IF;
            
            v_self_id := args[1]; -- self
            v_arg1 := args[2];    -- item
            
            -- Verify it's a list (Optional strict check)
            -- Update the list storage
            -- Note: We need to find the specific py_list_object entry.
            -- Since py_list_object references py_object(id) via ob_base (which is unique)
            
            UPDATE public.py_list_object
            SET ob_item = array_append(ob_item, v_arg1)
            WHERE ob_base = v_self_id; -- ob_base is the object ID
            
            -- Return None
            RETURN public.vm_get_none();
            
        -- [ list.__len__(self) ] -> Returns int object (Not Implemented yet fully, need int creation)
        -- For now, let's stick to update operations or simple returns.
        
        ELSE
            RAISE EXCEPTION 'NotImplementedError: Native function % is not implemented yet.', fn_name;
    END CASE;
    
    RETURN public.vm_get_none();
END;
$$ LANGUAGE plpgsql;


-------------------------------------------------------
-- 3. VM Call (Main Execution Entry)
-------------------------------------------------------
-- vm_call(callable_id, args[]) -> result_id
CREATE OR REPLACE FUNCTION public.vm_call(callable_id UUID, args UUID[])
RETURNS UUID AS $$
DECLARE
    v_type_id UUID;
    v_native_name TEXT;
    
    -- IDs
    ID_JS_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000013';
    
    -- Bound Method Support
    v_im_func UUID;
    v_im_self UUID;
    v_new_args UUID[];
BEGIN
    -- 1. Get Type of Callable
    v_type_id := public.vm_get_type(callable_id);
    
    -- 2. Case: Bound Method
    IF v_type_id = ID_METHOD_TYPE THEN
        -- Unwrap
        SELECT im_func, im_self INTO v_im_func, v_im_self 
        FROM public.py_bound_method_object 
        WHERE ob_base = callable_id;
        
        -- Prepend self to args
        v_new_args := array_prepend(v_im_self, args);
        
        -- Recursive Call with unwrapped function and new args
        RETURN public.vm_call(v_im_func, v_new_args);
    END IF;
    
    -- 3. Case: Native Function (JS/Pg)
    IF v_type_id = ID_JS_FNC_TYPE THEN
        -- Get Function Name
        SELECT fn_name INTO v_native_name 
        FROM public.py_builtin_function_object 
        WHERE ob_base = callable_id;
        
        -- Dispatch
        RETURN public.vm_native_dispatch(v_native_name, args);
    END IF;
    
    -- 4. Case: Python Bytecode Function (TODO)
    -- IF v_type_id = ID_FNC_TYPE THEN ... END IF;
    
    RAISE EXCEPTION 'TypeError: Object % is not callable (Type: %)', callable_id, v_type_id;
END;
$$ LANGUAGE plpgsql;
