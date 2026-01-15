-- Migration: Add methods to built-in types (tp_dict)
-- Created at: 2026-01-15 22:00:00

DO $$
DECLARE
    -- Type IDs
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_LST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';

    -- New Dict IDs for types
    ID_DICT_OBJ UUID := gen_random_uuid();
    B_DICT_OBJ  UUID := gen_random_uuid();
    
    ID_DICT_LST UUID := gen_random_uuid();
    B_DICT_LST  UUID := gen_random_uuid();
    
    ID_DICT_DCT UUID := gen_random_uuid();
    B_DICT_DCT  UUID := gen_random_uuid();
    
    ID_DICT_STR UUID := gen_random_uuid();
    B_DICT_STR  UUID := gen_random_uuid();

    -- Variables for loop unrolling
    V_METH_NAME TEXT;
    V_ARG_COUNT INTEGER;
    
    V_FUNC_OBJ UUID;
    V_FUNC_BASE UUID;
    V_CODE_OBJ UUID;
    V_CODE_BASE UUID;
    V_KEY_OBJ UUID; -- PyObject ID for the key
    V_KEY_BASE UUID; -- technically key object ID is the generic PyObject ID
    
    V_TARGET_DICT_ID UUID;

BEGIN
    -------------------------------------------------------
    -- 1. Create tp_dict objects for types
    -------------------------------------------------------
    
    -- object.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_OBJ, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_OBJ, B_DICT_OBJ, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_OBJ WHERE id = ID_OBJ_TYPE;

    -- list.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_LST, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_LST, B_DICT_LST, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_LST WHERE id = ID_LST_TYPE;

    -- dict.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_DCT, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_DCT, B_DICT_DCT, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_DCT WHERE id = ID_DCT_TYPE;

    -- str.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_STR, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_STR, B_DICT_STR, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_STR WHERE id = ID_STR_TYPE;


    -------------------------------------------------------
    -- 2. Create Methods
    -------------------------------------------------------
    
    -- Define a temp table to iterate over needed methods
    CREATE TEMP TABLE temp_methods (
        type_dict_id UUID,
        method_name TEXT,
        arg_count INTEGER
    ) ON COMMIT DROP;

    INSERT INTO temp_methods VALUES 
    (ID_DICT_OBJ, '__init__', 1),
    (ID_DICT_OBJ, '__str__', 1),
    (ID_DICT_OBJ, '__repr__', 1),
    
    (ID_DICT_LST, 'append', 2), -- self, item
    (ID_DICT_LST, 'pop', 1),
    (ID_DICT_LST, 'extend', 2),
    
    (ID_DICT_DCT, 'keys', 1),
    (ID_DICT_DCT, 'values', 1),
    (ID_DICT_DCT, 'items', 1),
    (ID_DICT_DCT, 'get', 2),
    
    (ID_DICT_STR, 'upper', 1),
    (ID_DICT_STR, 'lower', 1),
    (ID_DICT_STR, 'strip', 1);

    -- Loop through and create objects
    FOR V_TARGET_DICT_ID, V_METH_NAME, V_ARG_COUNT IN SELECT type_dict_id, method_name, arg_count FROM temp_methods LOOP
        
        -- Generate IDs
        V_FUNC_OBJ := gen_random_uuid();
        V_FUNC_BASE := gen_random_uuid();
        V_CODE_OBJ := gen_random_uuid();
        V_CODE_BASE := gen_random_uuid();
        V_KEY_BASE := gen_random_uuid(); -- This serves as the PyObject ID for the string key

        -- 1. Create Key String Object
        INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_BASE, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_BASE, V_METH_NAME);

        -- 2. Create Code Object
        INSERT INTO public.py_object (id, ob_type) VALUES (V_CODE_BASE, ID_CODE_TYPE);
        INSERT INTO public.py_code_object (id, ob_base, co_name, co_filename, co_argcount, co_code) 
        VALUES (V_CODE_OBJ, V_CODE_BASE, V_METH_NAME, '<method ' || V_METH_NAME || '>', V_ARG_COUNT, '<built-in method ' || V_METH_NAME || '>');

        -- 3. Create Function Object (Method)
        INSERT INTO public.py_object (id, ob_type) VALUES (V_FUNC_BASE, ID_FNC_TYPE);
        INSERT INTO public.py_function_object (id, ob_base, func_name, func_code, func_globals)
        VALUES (V_FUNC_OBJ, V_FUNC_BASE, V_METH_NAME, V_CODE_OBJ, NULL);

        -- 4. Link to Dict
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) 
        VALUES (gen_random_uuid(), V_TARGET_DICT_ID, V_KEY_BASE, V_FUNC_BASE);
        
        -- Update usage count
        UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = V_TARGET_DICT_ID;
        
    END LOOP;

END $$;
