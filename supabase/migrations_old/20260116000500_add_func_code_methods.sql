-- Migration: Add minimal methods for function and code types
-- Created at: 2026-01-16 00:05:00

DO $$
DECLARE
    -- Type IDs
    ID_FNC_TYPE  UUID := '00000000-0000-4000-a000-000000000008';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_STR_TYPE  UUID := '00000000-0000-4000-a000-000000000003';
    ID_DCT_TYPE  UUID := '00000000-0000-4000-a000-000000000006';

    -- Dict IDs
    ID_DICT_FNC UUID := gen_random_uuid();
    B_DICT_FNC  UUID := gen_random_uuid();
    
    ID_DICT_CODE UUID := gen_random_uuid();
    B_DICT_CODE  UUID := gen_random_uuid();

    -- Variables for loop
    V_DICT_ID   UUID;
    V_METH_NAME TEXT;
    
    V_JS_FUNC_OBJ  UUID;
    V_JS_FUNC_BASE UUID;
    V_KEY_BASE  UUID;
    
    ID_JS_FNC_TYPE  UUID := '00000000-0000-4000-a000-000000000012';

BEGIN
    -------------------------------------------------------
    -- 1. Create and Link Dictionaries
    -------------------------------------------------------
    
    -- function.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_FNC, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_FNC, B_DICT_FNC, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_FNC WHERE id = ID_FNC_TYPE;

    -- code.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_CODE, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_CODE, B_DICT_CODE, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_CODE WHERE id = ID_CODE_TYPE;


    -------------------------------------------------------
    -- 2. Define Methods to Add (Minimal)
    -------------------------------------------------------
    CREATE TEMP TABLE temp_func_methods (
        target_dict_id UUID,
        method_name TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_func_methods VALUES 
    -- function
    (ID_DICT_FNC, '__call__'),
    (ID_DICT_FNC, '__get__'),
    (ID_DICT_FNC, '__repr__'),

    -- code (Minimal)
    (ID_DICT_CODE, '__repr__');

    -------------------------------------------------------
    -- 3. Loop and Create
    -------------------------------------------------------
    FOR V_DICT_ID, V_METH_NAME IN SELECT target_dict_id, method_name FROM temp_func_methods LOOP
        
        -- Generate IDs
        V_JS_FUNC_OBJ := gen_random_uuid();
        V_JS_FUNC_BASE := gen_random_uuid();
        V_KEY_BASE := gen_random_uuid();

        -- 1. Create Key String Object
        INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_BASE, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_BASE, V_METH_NAME);

        -- 2. Create JS Function Object (Native)
        INSERT INTO public.py_object (id, ob_type) VALUES (V_JS_FUNC_BASE, ID_JS_FNC_TYPE);
        INSERT INTO public.py_builtin_function_object (id, ob_base, fn_name)
        VALUES (V_JS_FUNC_OBJ, V_JS_FUNC_BASE, V_METH_NAME);

        -- 3. Link to Dict
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) 
        VALUES (gen_random_uuid(), V_DICT_ID, V_KEY_BASE, V_JS_FUNC_BASE);
        
        -- Update usage count
        UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = V_DICT_ID;
        
    END LOOP;

END $$;
