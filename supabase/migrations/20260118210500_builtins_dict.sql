-- =====================================================
-- Migration: __builtins__ Dictionary
-- Description: Create the __builtins__ dictionary and populate with core functions and types
-- =====================================================

DO $$
DECLARE
    -- Type IDs
    ID_DICT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    
    -- Core Types to register
    ID_OBJ_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_TYP_TYPE uuid := '00000000-0000-4000-a000-000000000002';
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    ID_LST_TYPE uuid := '00000000-0000-4000-a000-000000000005';
    ID_DCT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
    
    -- __builtins__ Dictionary
    ID_DICT_BUILTINS uuid := '00000000-0000-4000-c000-000000000002';
    B_DICT_BUILTINS uuid := gen_random_uuid();

    -- Helper variables
    key_id uuid;
    val_id uuid;
    
    -- Function names to register
    func_names text[] := ARRAY['len', 'print', 'id'];
    func_name text;
    
    -- Type registration pairs: (name, type_id)
    type_reg record;
BEGIN
    -------------------------------------------------------
    -- 1. Create __builtins__ Dictionary
    -------------------------------------------------------
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_BUILTINS, ID_DICT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_BUILTINS, B_DICT_BUILTINS, 0);

    -------------------------------------------------------
    -- 2. Register Built-in Functions
    -------------------------------------------------------
    FOREACH func_name IN ARRAY func_names
    LOOP
        -- Find function object by name
        SELECT ob_base INTO val_id 
        FROM public.py_js_function_object 
        WHERE fn_name = func_name 
        LIMIT 1;
        
        IF val_id IS NOT NULL THEN
            -- Create string key
            key_id := gen_random_uuid();
            INSERT INTO public.py_object (id, ob_type) VALUES (key_id, ID_STR_TYPE);
            INSERT INTO public.py_unicode_object (id, ob_base, str_value) 
            VALUES (gen_random_uuid(), key_id, func_name);
            
            -- Add to dictionary
            INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) 
            VALUES (gen_random_uuid(), ID_DICT_BUILTINS, key_id, val_id);
            
            UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = ID_DICT_BUILTINS;
        END IF;
    END LOOP;

    -------------------------------------------------------
    -- 3. Register Core Types
    -------------------------------------------------------
    FOR type_reg IN 
        SELECT 'type' AS name, ID_TYP_TYPE AS type_id
        UNION ALL SELECT 'int', ID_INT_TYPE
        UNION ALL SELECT 'str', ID_STR_TYPE
        UNION ALL SELECT 'list', ID_LST_TYPE
        UNION ALL SELECT 'dict', ID_DCT_TYPE
        UNION ALL SELECT 'object', ID_OBJ_TYPE
    LOOP
        -- Get the type's PyObject ID
        SELECT ob_base INTO val_id 
        FROM public.py_type_object 
        WHERE id = type_reg.type_id;
        
        -- Create string key
        key_id := gen_random_uuid();
        INSERT INTO public.py_object (id, ob_type) VALUES (key_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) 
        VALUES (gen_random_uuid(), key_id, type_reg.name);
        
        -- Add to dictionary
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) 
        VALUES (gen_random_uuid(), ID_DICT_BUILTINS, key_id, val_id);
        
        UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = ID_DICT_BUILTINS;
    END LOOP;

END $$;
