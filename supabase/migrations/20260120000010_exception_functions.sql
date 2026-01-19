-- =====================================================
-- Migration: Exception Helper Functions
-- Description: Functions to create and manipulate Exception objects
-- =====================================================

-------------------------------------------------------
-- 1. vm_create_exception: Create a new exception instance
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_create_exception(
    p_type_id uuid, -- The Type ID (e.g., ID_TYPE_ERR)
    p_msg text DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
    v_base_id uuid;
    v_exc_id uuid;
    v_args_tuple uuid;
    v_msg_str uuid;
    v_items uuid[];
BEGIN
    -- 1. Create Arguments Tuple (args)
    IF p_msg IS NOT NULL THEN
        -- Create string object for message
        v_msg_str := public.vm_create_str(p_msg);
        v_items := ARRAY[v_msg_str];
    ELSE
        -- Empty tuple
        v_items := ARRAY[]::uuid[];
    END IF;
    
    v_args_tuple := public.vm_create_tuple(v_items);
    
    -- 2. Create Base Object
    v_base_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) 
    VALUES (v_base_id, p_type_id);
    
    -- 3. Create Exception Object
    v_exc_id := gen_random_uuid();
    INSERT INTO public.py_exception_object (id, ob_base, ex_args) 
    VALUES (v_exc_id, v_base_id, v_args_tuple);
    
    RETURN v_base_id;
END;
$$ LANGUAGE plpgsql;
