-- Migration: Add missing dict methods (update, pop, etc.)
-- Created at: 2026-01-15 23:15:00

DO $$
DECLARE
    -- Type ID for Dict
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    -- Use JS Function Type
    ID_JS_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

    -- Type Dictionary
    V_DICT_ID UUID;
    
    -- Variables for loop
    V_METH_NAME TEXT;

    V_JS_FUNC_OBJ UUID;
    V_JS_FUNC_BASE UUID;
    V_KEY_BASE UUID;

BEGIN
    -- 1. Find the dictionary for 'dict' type
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_DCT_TYPE;
    
    -------------------------------------------------------
    -- 2. Define Methods to Add
    -------------------------------------------------------
    CREATE TEMP TABLE temp_dict_methods (
        method_name TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_dict_methods VALUES 
    ('update'),
    ('setdefault'),
    ('pop'),
    ('popitem'),
    ('clear'),
    ('copy'),
    ('fromkeys'), -- classmethod
    
    -- Magic Methods
    ('__iter__'),
    ('__len__'),
    ('__repr__'),
    ('__eq__'),
    ('__ne__'),
    ('__or__'), -- | operator (Python 3.9+)
    ('__ior__'); -- |= operator

    -------------------------------------------------------
    -- 3. Loop and Create
    -------------------------------------------------------
    FOR V_METH_NAME IN SELECT method_name FROM temp_dict_methods LOOP
        
        -- Generate IDs
        V_JS_FUNC_OBJ := gen_random_uuid();
        V_JS_FUNC_BASE := gen_random_uuid();
        V_KEY_BASE := gen_random_uuid();

        -- 1. Create Key String Object (Method Name)
        INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_BASE, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_BASE, V_METH_NAME);

        -- 2. Create JS Function Object
        INSERT INTO public.py_object (id, ob_type) VALUES (V_JS_FUNC_BASE, ID_JS_FNC_TYPE);
        INSERT INTO public.py_js_function_object (id, ob_base, fn_name)
        VALUES (V_JS_FUNC_OBJ, V_JS_FUNC_BASE, V_METH_NAME);

        -- 3. Link to Dict
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) 
        VALUES (gen_random_uuid(), V_DICT_ID, V_KEY_BASE, V_JS_FUNC_BASE);
        
        -- Update usage count
        UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = V_DICT_ID;
        
    END LOOP;

END $$;
