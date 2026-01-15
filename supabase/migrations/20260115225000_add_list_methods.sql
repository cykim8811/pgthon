-- Migration: Add missing list methods (index, count, sort, etc.)
-- Created at: 2026-01-15 22:50:00

DO $$
DECLARE
    -- Type ID for List
    ID_LST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

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
    -- 1. Find the dictionary for 'list' type
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_LST_TYPE;
    
    -------------------------------------------------------
    -- 2. Define Methods to Add
    -------------------------------------------------------
    CREATE TEMP TABLE temp_lst_methods (
        method_name TEXT,
        arg_count INTEGER,
        signature TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_lst_methods VALUES 
    ('insert', 3, 'list.insert(self, index, object) -> None'),
    ('remove', 2, 'list.remove(self, value) -> None'),
    ('clear', 1, 'list.clear(self) -> None'),
    ('count', 2, 'list.count(self, value) -> int'),
    ('index', 2, 'list.index(self, value, start=0, stop=9223372036854775807) -> int'),
    ('reverse', 1, 'list.reverse(self) -> None'),
    ('sort', 1, 'list.sort(self, key=None, reverse=False) -> None'),
    ('copy', 1, 'list.copy(self) -> list'),
    ('__iter__', 1, 'list.__iter__(self) -> iterator'),
    ('__contains__', 2, 'list.__contains__(self, value) -> bool'), -- 'x' in list
    ('__add__', 2, 'list.__add__(self, value) -> list'), -- list + list
    ('__iadd__', 2, 'list.__iadd__(self, value) -> list'), -- list += list
    ('__mul__', 2, 'list.__mul__(self, value) -> list'), -- list * n
    ('__imul__', 2, 'list.__imul__(self, value) -> list'); -- list *= n

    -------------------------------------------------------
    -- 3. Loop and Create
    -------------------------------------------------------
    FOR V_METH_NAME, V_ARG_COUNT, V_SIGNATURE IN SELECT method_name, arg_count, signature FROM temp_lst_methods LOOP
        
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
