-- Migration: Add methods for bool, tuple, and NoneType
-- Created at: 2026-01-15 23:45:00

DO $$
DECLARE
    -- Type IDs
    ID_BOOL_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    ID_TUP_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_NONE_TYPE UUID := '00000000-0000-4000-a000-000000000009';
    
    ID_FNC_TYPE  UUID := '00000000-0000-4000-a000-000000000008';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_STR_TYPE  UUID := '00000000-0000-4000-a000-000000000003';
    ID_DCT_TYPE  UUID := '00000000-0000-4000-a000-000000000006';

    -- Dict IDs
    ID_DICT_BOOL UUID := gen_random_uuid();
    B_DICT_BOOL  UUID := gen_random_uuid();
    
    ID_DICT_TUP  UUID := gen_random_uuid();
    B_DICT_TUP   UUID := gen_random_uuid();
    
    ID_DICT_NONE UUID := gen_random_uuid();
    B_DICT_NONE  UUID := gen_random_uuid();

    -- Variables for loop
    V_DICT_ID   UUID;
    V_METH_NAME TEXT;
    V_ARG_COUNT INTEGER;
    V_SIGNATURE TEXT;
    
    V_FUNC_OBJ  UUID;
    V_FUNC_BASE UUID;
    V_CODE_OBJ  UUID;
    V_CODE_BASE UUID;
    V_KEY_BASE  UUID;

BEGIN
    -------------------------------------------------------
    -- 1. Create and Link Dictionaries
    -------------------------------------------------------
    
    -- bool.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_BOOL, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_BOOL, B_DICT_BOOL, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_BOOL WHERE id = ID_BOOL_TYPE;

    -- tuple.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_TUP, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_TUP, B_DICT_TUP, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_TUP WHERE id = ID_TUP_TYPE;

    -- NoneType.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_NONE, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_NONE, B_DICT_NONE, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_NONE WHERE id = ID_NONE_TYPE;


    -------------------------------------------------------
    -- 2. Define Methods to Add
    -------------------------------------------------------
    CREATE TEMP TABLE temp_remaining_methods (
        target_dict_id UUID,
        method_name TEXT,
        arg_count INTEGER,
        signature TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_remaining_methods VALUES 
    -- bool: mostly inherits from int, but has its own repr/and/or
    (ID_DICT_BOOL, '__repr__', 1, 'bool.__repr__(self) -> str'),
    (ID_DICT_BOOL, '__and__', 2, 'bool.__and__(self, other) -> bool'),
    (ID_DICT_BOOL, '__or__', 2, 'bool.__or__(self, other) -> bool'),
    (ID_DICT_BOOL, '__xor__', 2, 'bool.__xor__(self, other) -> bool'),

    -- tuple: Immutable sequence
    (ID_DICT_TUP, '__getitem__', 2, 'tuple.__getitem__(self, index) -> object'),
    (ID_DICT_TUP, '__len__', 1, 'tuple.__len__(self) -> int'),
    (ID_DICT_TUP, '__iter__', 1, 'tuple.__iter__(self) -> iterator'),
    (ID_DICT_TUP, '__contains__', 2, 'tuple.__contains__(self, value) -> bool'),
    (ID_DICT_TUP, '__add__', 2, 'tuple.__add__(self, other) -> tuple'),
    (ID_DICT_TUP, '__mul__', 2, 'tuple.__mul__(self, n) -> tuple'),
    (ID_DICT_TUP, 'count', 2, 'tuple.count(self, value) -> int'),
    (ID_DICT_TUP, 'index', 2, 'tuple.index(self, value, [start, [stop]]) -> int'),
    (ID_DICT_TUP, '__repr__', 1, 'tuple.__repr__(self) -> str'),

    -- NoneType: The singleton type
    (ID_DICT_NONE, '__repr__', 1, 'NoneType.__repr__(self) -> str'),
    (ID_DICT_NONE, '__bool__', 1, 'NoneType.__bool__(self) -> False');

    -------------------------------------------------------
    -- 3. Loop and Create
    -------------------------------------------------------
    FOR V_DICT_ID, V_METH_NAME, V_ARG_COUNT, V_SIGNATURE IN SELECT target_dict_id, method_name, arg_count, signature FROM temp_remaining_methods LOOP
        
        -- Generate IDs
        V_FUNC_OBJ := gen_random_uuid();
        V_FUNC_BASE := gen_random_uuid();
        V_CODE_OBJ := gen_random_uuid();
        V_CODE_BASE := gen_random_uuid();
        V_KEY_BASE := gen_random_uuid();

        -- 1. Create Key String Object
        INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_BASE, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_BASE, V_METH_NAME);

        -- 2. Create Code Object with Signature
        INSERT INTO public.py_object (id, ob_type) VALUES (V_CODE_BASE, ID_CODE_TYPE);
        INSERT INTO public.py_code_object (id, ob_base, co_name, co_filename, co_argcount, co_code) 
        VALUES (V_CODE_OBJ, V_CODE_BASE, V_METH_NAME, '<slot wrapper ' || V_METH_NAME || '>', V_ARG_COUNT, V_SIGNATURE);

        -- 3. Create Function Object
        INSERT INTO public.py_object (id, ob_type) VALUES (V_FUNC_BASE, ID_FNC_TYPE);
        INSERT INTO public.py_function_object (id, ob_base, func_name, func_code, func_globals)
        VALUES (V_FUNC_OBJ, V_FUNC_BASE, V_METH_NAME, V_CODE_OBJ, NULL);

        -- 4. Link to Dict
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) 
        VALUES (gen_random_uuid(), V_DICT_ID, V_KEY_BASE, V_FUNC_BASE);
        
        -- Update usage count
        UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = V_DICT_ID;
        
    END LOOP;

END $$;
