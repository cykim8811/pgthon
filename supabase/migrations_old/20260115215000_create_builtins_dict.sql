-- Migration: Create __builtins__ dictionary
-- Created at: 2026-01-15 21:50:00

DO $$
DECLARE
    -- Object IDs from previous migrations
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    
    -- Types to register
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYP_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_LST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUP_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    
    -- Functions to register (from builtin_functions.sql)
    -- Since we didn't specify fixed IDs for function objects in the previous migration (we used gen_random_uuid() inside variables only),
    -- we actually need to look them up by name to link them.
    -- However, for the keys (string objects), we need to create new PyUnicodeObjects.
    
    -- Module Object for 'builtins'
    ID_MOD_BUILTINS UUID := '00000000-0000-4000-c000-000000000001';
    B_MOD_BUILTINS  UUID := gen_random_uuid();
    
    -- The main dictionary for __builtins__
    ID_DICT_BUILTINS UUID := '00000000-0000-4000-c000-000000000002';
    B_DICT_BUILTINS  UUID := gen_random_uuid();

    -- Helper variables
    V_KEY_ID UUID;
    V_VAL_ID UUID;
    
BEGIN
    -------------------------------------------------------
    -- 1. Create the __builtins__ Dictionary Object
    -------------------------------------------------------
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_BUILTINS, ID_DICT_TYPE);
    
    -- We can set ma_table later via PyDictEntry or just leave it empty for now?
    -- The spec has ma_table as JSONB but we are using py_dict_entry table mostly.
    -- Let's create the PyDictObject entry.
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_BUILTINS, B_DICT_BUILTINS, 0);

    -------------------------------------------------------
    -- 2. Helper Procedure to Add Entries
    -------------------------------------------------------
    -- Since we cannot define functions inside DO block easily that reuse variables for IDs without more complex PL/pgSQL,
    -- we will just write the inserts directly for key items.

    -- --- Register 'len' ---
    -- 1. Find the object ID for function 'len'
    SELECT ob_base INTO V_VAL_ID FROM public.py_function_object WHERE func_name = 'len' LIMIT 1;
    -- 2. Create a string object for key "len"
    V_KEY_ID := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_ID, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_ID, 'len');
    -- 3. Link in PyDictEntry
    INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) VALUES (gen_random_uuid(), ID_DICT_BUILTINS, V_KEY_ID, V_VAL_ID);

    -- --- Register 'print' ---
    SELECT ob_base INTO V_VAL_ID FROM public.py_function_object WHERE func_name = 'print' LIMIT 1;
    V_KEY_ID := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_ID, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_ID, 'print');
    INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) VALUES (gen_random_uuid(), ID_DICT_BUILTINS, V_KEY_ID, V_VAL_ID);

    -- --- Register 'type' (The Type) ---
    -- Note: 'type' is both a type and a function-like constructor. We have ID_TYP_TYPE (the type object).
    -- Let's register the Type Object itself as 'type'.
    V_VAL_ID := (SELECT ob_base FROM public.py_type_object WHERE id = ID_TYP_TYPE);
    V_KEY_ID := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_ID, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_ID, 'type');
    INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) VALUES (gen_random_uuid(), ID_DICT_BUILTINS, V_KEY_ID, V_VAL_ID);

    -- --- Register 'int' ---
    V_VAL_ID := (SELECT ob_base FROM public.py_type_object WHERE id = ID_INT_TYPE);
    V_KEY_ID := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_ID, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_ID, 'int');
    INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) VALUES (gen_random_uuid(), ID_DICT_BUILTINS, V_KEY_ID, V_VAL_ID);

    -- --- Register 'str' ---
    V_VAL_ID := (SELECT ob_base FROM public.py_type_object WHERE id = ID_STR_TYPE);
    V_KEY_ID := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_ID, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_ID, 'str');
    INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) VALUES (gen_random_uuid(), ID_DICT_BUILTINS, V_KEY_ID, V_VAL_ID);

    -- --- Register 'list' ---
    V_VAL_ID := (SELECT ob_base FROM public.py_type_object WHERE id = ID_LST_TYPE);
    V_KEY_ID := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_ID, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_ID, 'list');
    INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) VALUES (gen_random_uuid(), ID_DICT_BUILTINS, V_KEY_ID, V_VAL_ID);
    
    -- --- Register 'dict' ---
    V_VAL_ID := (SELECT ob_base FROM public.py_type_object WHERE id = ID_DCT_TYPE);
    V_KEY_ID := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_ID, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_ID, 'dict');
    INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) VALUES (gen_random_uuid(), ID_DICT_BUILTINS, V_KEY_ID, V_VAL_ID);

    -- Update usage count
    UPDATE public.py_dict_object SET ma_used = 7 WHERE id = ID_DICT_BUILTINS;

END $$;
