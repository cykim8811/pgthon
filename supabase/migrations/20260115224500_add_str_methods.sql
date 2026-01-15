-- Migration: Add missing string methods (split, join, replace, etc.)
-- Created at: 2026-01-15 22:45:00

DO $$
DECLARE
    -- Type ID for String
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001'; -- Generic Object type needed for PyUnicodeObject insert if strict, but we use ID_STR_TYPE for keys.

    -- Type Dictionary
    V_DICT_ID UUID;
    
    -- Variables for loop
    V_METH_NAME TEXT;
    V_ARG_COUNT INTEGER;
    V_SIGNATURE TEXT;
    
    V_FUNC_OBJ UUID;
    V_FUNC_BASE UUID;
    V_CODE_OBJ UUID;
    V_CODE_BASE UUID;
    V_KEY_BASE UUID;

BEGIN
    -- 1. Find the dictionary for 'str' type
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_STR_TYPE;
    
    -------------------------------------------------------
    -- 2. Define Methods to Add
    -------------------------------------------------------
    CREATE TEMP TABLE temp_str_methods (
        method_name TEXT,
        arg_count INTEGER,
        signature TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_str_methods VALUES 
    ('split', 2, 'str.split(self, sep=None, maxsplit=-1) -> list'),
    ('join', 2, 'str.join(self, iterable) -> str'),
    ('replace', 3, 'str.replace(self, old, new, count=-1) -> str'),
    ('find', 2, 'str.find(self, sub, start=0, end=None) -> int'),
    ('count', 2, 'str.count(self, sub, start=0, end=None) -> int'),
    ('startswith', 2, 'str.startswith(self, prefix, start=0, end=None) -> bool'),
    ('endswith', 2, 'str.endswith(self, suffix, start=0, end=None) -> bool'),
    ('format', 1, 'str.format(self, *args, **kwargs) -> str'),
    ('title', 1, 'str.title(self) -> str'),
    ('capitalize', 1, 'str.capitalize(self) -> str'),
    ('index', 2, 'str.index(self, sub, start=0, end=None) -> int'),
    ('__add__', 2, 'str.__add__(self, other) -> str'), -- String concatenation
    ('__contains__', 2, 'str.__contains__(self, char) -> bool'), -- 'x' in 'str'
    ('__getitem__', 2, 'str.__getitem__(self, index) -> str'), -- s[0]
    ('__len__', 1, 'str.__len__(self) -> int'); 

    -------------------------------------------------------
    -- 3. Loop and Create
    -------------------------------------------------------
    FOR V_METH_NAME, V_ARG_COUNT, V_SIGNATURE IN SELECT method_name, arg_count, signature FROM temp_str_methods LOOP
        
        -- Generate IDs
        V_FUNC_OBJ := gen_random_uuid();
        V_FUNC_BASE := gen_random_uuid();
        V_CODE_OBJ := gen_random_uuid();
        V_CODE_BASE := gen_random_uuid();
        V_KEY_BASE := gen_random_uuid();

        -- 1. Create Key String Object (Method Name)
        INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_BASE, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_BASE, V_METH_NAME);

        -- 2. Create Code Object with Signature
        INSERT INTO public.py_object (id, ob_type) VALUES (V_CODE_BASE, ID_CODE_TYPE);
        INSERT INTO public.py_code_object (id, ob_base, co_name, co_filename, co_argcount, co_code) 
        VALUES (V_CODE_OBJ, V_CODE_BASE, V_METH_NAME, '<method ' || V_METH_NAME || '>', V_ARG_COUNT, V_SIGNATURE);

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
