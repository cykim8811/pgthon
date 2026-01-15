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
    V_ARG_COUNT INTEGER;
    V_TARGET_DICT_ID UUID;
    V_FUNC_OBJ UUID;
    V_FUNC_BASE UUID;
    V_CODE_OBJ UUID;
    V_CODE_BASE UUID;
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
        method_name TEXT,
        arg_count INTEGER
    ) ON COMMIT DROP;

    INSERT INTO temp_magic_methods VALUES 
    -- type: Essential for instantiation (e.g., MyClass())
    (ID_DICT_TYP, '__call__', 1), -- args, kwargs
    (ID_DICT_TYP, 'mro', 1),
    
    -- int: Basic arithmetic and comparison
    (ID_DICT_INT, '__add__', 2), -- self, other
    (ID_DICT_INT, '__sub__', 2),
    (ID_DICT_INT, '__mul__', 2),
    (ID_DICT_INT, '__eq__', 2),
    (ID_DICT_INT, '__lt__', 2),
    
    -- list: Essential container protocols
    (ID_DICT_LST, '__init__', 1),
    (ID_DICT_LST, '__getitem__', 2), -- self, index
    (ID_DICT_LST, '__setitem__', 3), -- self, index, value
    (ID_DICT_LST, '__len__', 1),
    
    -- dict: Essential container protocols
    (ID_DICT_DCT, '__init__', 1),
    (ID_DICT_DCT, '__getitem__', 2), -- self, key
    (ID_DICT_DCT, '__setitem__', 3), -- self, key, value
    (ID_DICT_DCT, '__delitem__', 2), -- self, key
    (ID_DICT_DCT, '__contains__', 2);

    -------------------------------------------------------
    -- 2. Loop and Create
    -------------------------------------------------------
    FOR V_TARGET_DICT_ID, V_METH_NAME, V_ARG_COUNT IN SELECT type_dict_id, method_name, arg_count FROM temp_magic_methods LOOP
        
        -- Generate IDs
        V_FUNC_OBJ := gen_random_uuid();
        V_FUNC_BASE := gen_random_uuid();
        V_CODE_OBJ := gen_random_uuid();
        V_CODE_BASE := gen_random_uuid();
        V_KEY_BASE := gen_random_uuid();

        -- 1. Create Key String Object
        INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_BASE, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_BASE, V_METH_NAME);

        -- 2. Create Code Object (Use wrapper description)
        INSERT INTO public.py_object (id, ob_type) VALUES (V_CODE_BASE, ID_CODE_TYPE);
        INSERT INTO public.py_code_object (id, ob_base, co_name, co_filename, co_argcount, co_code) 
        VALUES (V_CODE_OBJ, V_CODE_BASE, V_METH_NAME, '<slot wrapper>', V_ARG_COUNT, '<slot wrapper ' || V_METH_NAME || '>');

        -- 3. Create Function Object
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
