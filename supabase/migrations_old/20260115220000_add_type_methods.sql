-- Migration: Add methods to built-in types (tp_dict)
-- Created at: 2026-01-15 22:00:00

DO $$
DECLARE
    -- Type IDs
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_LST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    -- Use JS Function Type
    ID_JS_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000012';

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
    
    V_JS_FUNC_OBJ UUID;
    V_JS_FUNC_BASE UUID;
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
        method_name TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_methods VALUES 
    (ID_DICT_OBJ, '__init__'),
    (ID_DICT_OBJ, '__str__'),
    (ID_DICT_OBJ, '__repr__'),
    
    (ID_DICT_LST, 'append'), 
    (ID_DICT_LST, 'pop'),
    (ID_DICT_LST, 'extend'),
    
    (ID_DICT_DCT, 'keys'),
    (ID_DICT_DCT, 'values'),
    (ID_DICT_DCT, 'items'),
    (ID_DICT_DCT, 'get'),
    
    (ID_DICT_STR, 'upper'),
    (ID_DICT_STR, 'lower'),
    (ID_DICT_STR, 'strip');

    -- Loop through and create objects
    FOR V_TARGET_DICT_ID, V_METH_NAME IN SELECT type_dict_id, method_name FROM temp_methods LOOP
        
        -- Generate IDs
        V_JS_FUNC_OBJ := gen_random_uuid();
        V_JS_FUNC_BASE := gen_random_uuid();
        V_KEY_BASE := gen_random_uuid(); -- This serves as the PyObject ID for the string key

        -- 1. Create Key String Object
        INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_BASE, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_BASE, V_METH_NAME);

        -- 2. Create JS Function Object (Method)
        INSERT INTO public.py_object (id, ob_type) VALUES (V_JS_FUNC_BASE, ID_JS_FNC_TYPE);
        INSERT INTO public.py_builtin_function_object (id, ob_base, fn_name)
        VALUES (V_JS_FUNC_OBJ, V_JS_FUNC_BASE, V_METH_NAME);

        -- 3. Link to Dict
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) 
        VALUES (gen_random_uuid(), V_TARGET_DICT_ID, V_KEY_BASE, V_JS_FUNC_BASE);
        
        -- Update usage count
        UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = V_TARGET_DICT_ID;
        
    END LOOP;

END $$;
