-- Migration: Add type and object metaclass methods (__new__, __init__, etc.)
-- Created at: 2026-01-15 23:30:00

DO $$
DECLARE
    -- Type IDs
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYP_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    -- Use JS Function Type
    ID_JS_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

    -- Target Dictionary Names
    ID_DICT_OBJ UUID;
    ID_DICT_TYP UUID;
    
    -- Variables for loop
    V_DICT_ID UUID;
    V_METH_NAME TEXT;

    V_JS_FUNC_OBJ UUID;
    V_JS_FUNC_BASE UUID;
    V_KEY_BASE UUID;

BEGIN
    -- 1. Find dictionaries for 'object' and 'type'
    SELECT tp_dict INTO ID_DICT_OBJ FROM public.py_type_object WHERE id = ID_OBJ_TYPE;
    SELECT tp_dict INTO ID_DICT_TYP FROM public.py_type_object WHERE id = ID_TYP_TYPE;
    
    -------------------------------------------------------
    -- 2. Define Methods to Add
    -------------------------------------------------------
    CREATE TEMP TABLE temp_meta_methods (
        target_dict_id UUID,
        method_name TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_meta_methods VALUES 
    -- object methods (base)
    (ID_DICT_OBJ, '__new__'), -- static method conceptually
    (ID_DICT_OBJ, '__init_subclass__'), -- class method
    (ID_DICT_OBJ, '__format__'),
    (ID_DICT_OBJ, '__eq__'),
    (ID_DICT_OBJ, '__ne__'),
    (ID_DICT_OBJ, '__ge__'),
    (ID_DICT_OBJ, '__gt__'),
    (ID_DICT_OBJ, '__le__'),
    (ID_DICT_OBJ, '__lt__'),
    (ID_DICT_OBJ, '__hash__'),
    (ID_DICT_OBJ, '__class__'), -- Just adding as entry, though strictly it's a descriptor/getset

    -- type methods (metaclass)
    (ID_DICT_TYP, '__new__'),
    (ID_DICT_TYP, '__init__'),
    (ID_DICT_TYP, '__prepare__'),
    (ID_DICT_TYP, '__instancecheck__'),
    (ID_DICT_TYP, '__subclasscheck__'),
    (ID_DICT_TYP, 'mro'); -- Already added potentially but good to confirm

    -------------------------------------------------------
    -- 3. Loop and Create (Skipping duplicates if they exist)
    -------------------------------------------------------
    FOR V_DICT_ID, V_METH_NAME IN SELECT target_dict_id, method_name FROM temp_meta_methods LOOP
        
        -- Check if method already exists to avoid duplication
        IF NOT EXISTS (
            SELECT 1 FROM public.py_dict_entry 
            WHERE dict_id = V_DICT_ID 
            AND me_key IN (
                SELECT id FROM public.py_object 
                WHERE id IN (SELECT ob_base FROM public.py_unicode_object WHERE str_value = V_METH_NAME)
            )
        ) THEN

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
        
        END IF;
        
    END LOOP;

END $$;
