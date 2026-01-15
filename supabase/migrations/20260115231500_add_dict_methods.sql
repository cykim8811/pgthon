-- Migration: Add missing dict methods (update, pop, etc.)
-- Created at: 2026-01-15 23:15:00

DO $$
DECLARE
    -- Type ID for Dict
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
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
    -- 1. Find the dictionary for 'dict' type
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_DCT_TYPE;
    
    -------------------------------------------------------
    -- 2. Define Methods to Add
    -------------------------------------------------------
    CREATE TEMP TABLE temp_dict_methods (
        method_name TEXT,
        arg_count INTEGER,
        signature TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_dict_methods VALUES 
    ('update', 2, 'dict.update(self, E, **F) -> None'),
    ('setdefault', 3, 'dict.setdefault(self, key, default=None) -> value'),
    ('pop', 3, 'dict.pop(self, key, default=<unbound>) -> value'),
    ('popitem', 1, 'dict.popitem(self) -> (key, value)'),
    ('clear', 1, 'dict.clear(self) -> None'),
    ('copy', 1, 'dict.copy(self) -> dict'),
    ('fromkeys', 2, 'dict.fromkeys(iterable, value=None) -> dict'), -- classmethod
    
    -- Magic Methods
    ('__iter__', 1, 'dict.__iter__(self) -> iterator'),
    ('__len__', 1, 'dict.__len__(self) -> int'),
    ('__repr__', 1, 'dict.__repr__(self) -> str'),
    ('__eq__', 2, 'dict.__eq__(self, other) -> bool'),
    ('__ne__', 2, 'dict.__ne__(self, other) -> bool'),
    ('__or__', 2, 'dict.__or__(self, other) -> dict'), -- | operator (Python 3.9+)
    ('__ior__', 2, 'dict.__ior__(self, other) -> dict'); -- |= operator

    -------------------------------------------------------
    -- 3. Loop and Create
    -------------------------------------------------------
    FOR V_METH_NAME, V_ARG_COUNT, V_SIGNATURE IN SELECT method_name, arg_count, signature FROM temp_dict_methods LOOP
        
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
