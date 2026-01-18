-- Migration: Add core magic methods (type.__call__, int.__add__, etc.)
-- Created at: 2026-01-15 22:15:00

DO $$
DECLARE
    -- Type IDs
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYP_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_LST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    -- Use JS Function Type
    ID_JS_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

    -- Dict IDs (we need to find or create them for type and int)
    ID_DICT_TYP UUID := gen_random_uuid();
    B_DICT_TYP  UUID := gen_random_uuid();
    
    ID_DICT_INT UUID := gen_random_uuid();
    B_DICT_INT  UUID := gen_random_uuid();

    -- Existing Dict IDs to look up
    ID_DICT_LST UUID;
    ID_DICT_DCT UUID;

    -- Generic generic variables
    V_METH_NAME TEXT;
    
    V_TARGET_DICT_ID UUID;
    V_JS_FUNC_OBJ UUID;
    V_JS_FUNC_BASE UUID;
    V_KEY_BASE UUID;

BEGIN
    -------------------------------------------------------
    -- 0. Prepare Type Dictionaries (type & int)
    -------------------------------------------------------
    
    -- type.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_TYP, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_TYP, B_DICT_TYP, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_TYP WHERE id = ID_TYP_TYPE;

    -- int.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_INT, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_INT, B_DICT_INT, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_INT WHERE id = ID_INT_TYPE;

    -- Fetch existing dict IDs for list/dict
    SELECT tp_dict INTO ID_DICT_LST FROM public.py_type_object WHERE id = ID_LST_TYPE;
    SELECT tp_dict INTO ID_DICT_DCT FROM public.py_type_object WHERE id = ID_DCT_TYPE;

    -------------------------------------------------------
    -- 1. Define Methods to Add
    -------------------------------------------------------
    
    CREATE TEMP TABLE temp_magic_methods (
        type_dict_id UUID,
        method_name TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_magic_methods VALUES 
    -- type: Essential for instantiation (e.g., MyClass())
    (ID_DICT_TYP, '__call__'),
    (ID_DICT_TYP, 'mro'),
    
    -- int: Basic arithmetic and comparison
    (ID_DICT_INT, '__add__'),
    (ID_DICT_INT, '__sub__'),
    (ID_DICT_INT, '__mul__'),
    (ID_DICT_INT, '__eq__'),
    (ID_DICT_INT, '__lt__'),
    
    -- list: Essential container protocols
    (ID_DICT_LST, '__init__'),
    (ID_DICT_LST, '__getitem__'),
    (ID_DICT_LST, '__setitem__'),
    (ID_DICT_LST, '__len__'),
    
    -- dict: Essential container protocols
    (ID_DICT_DCT, '__init__'),
    (ID_DICT_DCT, '__getitem__'),
    (ID_DICT_DCT, '__setitem__'),
    (ID_DICT_DCT, '__delitem__'),
    (ID_DICT_DCT, '__contains__');

    -------------------------------------------------------
    -- 2. Loop and Create
    -------------------------------------------------------
    FOR V_TARGET_DICT_ID, V_METH_NAME IN SELECT type_dict_id, method_name FROM temp_magic_methods LOOP
        
        -- Generate IDs
        V_JS_FUNC_OBJ := gen_random_uuid();
        V_JS_FUNC_BASE := gen_random_uuid();
        V_KEY_BASE := gen_random_uuid();

        -- 1. Create Key String Object
        INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_BASE, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_BASE, V_METH_NAME);

        -- 2. Create JS Function Object
        INSERT INTO public.py_object (id, ob_type) VALUES (V_JS_FUNC_BASE, ID_JS_FNC_TYPE);
        INSERT INTO public.py_js_function_object (id, ob_base, fn_name)
        VALUES (V_JS_FUNC_OBJ, V_JS_FUNC_BASE, V_METH_NAME);

        -- 3. Link to Dict
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) 
        VALUES (gen_random_uuid(), V_TARGET_DICT_ID, V_KEY_BASE, V_JS_FUNC_BASE);
        
        -- Update usage count
        UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = V_TARGET_DICT_ID;
        
    END LOOP;

END $$;
