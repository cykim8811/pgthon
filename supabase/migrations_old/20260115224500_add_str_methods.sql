-- Migration: Add missing string methods (split, join, replace, etc.)
-- Created at: 2026-01-15 22:45:00

DO $$
DECLARE
    -- Type ID for String
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    -- Use JS Function Type
    ID_JS_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000012';

    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001'; -- Generic Object type needed for PyUnicodeObject insert if strict, but we use ID_STR_TYPE for keys.

    -- Type Dictionary
    V_DICT_ID UUID;
    
    -- Variables for loop
    V_METH_NAME TEXT;
    
    V_JS_FUNC_OBJ UUID;
    V_JS_FUNC_BASE UUID;
    V_KEY_BASE UUID;

BEGIN
    -- 1. Find the dictionary for 'str' type
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_STR_TYPE;
    
    -------------------------------------------------------
    -- 2. Define Methods to Add
    -------------------------------------------------------
    CREATE TEMP TABLE temp_str_methods (
        method_name TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_str_methods VALUES 
    ('split'),
    ('join'),
    ('replace'),
    ('find'),
    ('count'),
    ('startswith'),
    ('endswith'),
    ('format'),
    ('title'),
    ('capitalize'),
    ('index'),
    ('__add__'), -- String concatenation
    ('__contains__'), -- 'x' in 'str'
    ('__getitem__'), -- s[0]
    ('__len__'); 

    -------------------------------------------------------
    -- 3. Loop and Create
    -------------------------------------------------------
    FOR V_METH_NAME IN SELECT method_name FROM temp_str_methods LOOP
        
        -- Generate IDs
        V_JS_FUNC_OBJ := gen_random_uuid();
        V_JS_FUNC_BASE := gen_random_uuid();
        V_KEY_BASE := gen_random_uuid();

        -- 1. Create Key String Object (Method Name)
        INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_BASE, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_BASE, V_METH_NAME);

        -- 2. Create JS Function Object
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
