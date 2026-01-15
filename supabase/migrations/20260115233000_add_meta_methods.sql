-- Migration: Add type and object metaclass methods (__new__, __init__, etc.)
-- Created at: 2026-01-15 23:30:00

DO $$
DECLARE
    -- Type IDs
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYP_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

    -- Target Dictionary Names
    ID_DICT_OBJ UUID;
    ID_DICT_TYP UUID;
    
    -- Variables for loop
    V_DICT_ID UUID;
    V_METH_NAME TEXT;
    V_ARG_COUNT INTEGER;
    V_SIGNATURE TEXT;
    
    V_FUNC_OBJ UUID;
    V_FUNC_BASE UUID;
    V_CODE_OBJ UUID;
    V_CODE_BASE UUID;
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
        method_name TEXT,
        arg_count INTEGER,
        signature TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_meta_methods VALUES 
    -- object methods (base)
    (ID_DICT_OBJ, '__new__', 1, 'object.__new__(cls) -> object'), -- static method conceptually
    (ID_DICT_OBJ, '__init_subclass__', 1, 'object.__init_subclass__(cls) -> None'), -- class method
    (ID_DICT_OBJ, '__format__', 2, 'object.__format__(self, format_spec) -> str'),
    (ID_DICT_OBJ, '__eq__', 2, 'object.__eq__(self, other) -> bool'),
    (ID_DICT_OBJ, '__ne__', 2, 'object.__ne__(self, other) -> bool'),
    (ID_DICT_OBJ, '__ge__', 2, 'object.__ge__(self, other) -> bool'),
    (ID_DICT_OBJ, '__gt__', 2, 'object.__gt__(self, other) -> bool'),
    (ID_DICT_OBJ, '__le__', 2, 'object.__le__(self, other) -> bool'),
    (ID_DICT_OBJ, '__lt__', 2, 'object.__lt__(self, other) -> bool'),
    (ID_DICT_OBJ, '__hash__', 1, 'object.__hash__(self) -> int'),
    (ID_DICT_OBJ, '__class__', 1, 'object.__class__ property'), -- Just adding as entry, though strictly it's a descriptor/getset

    -- type methods (metaclass)
    (ID_DICT_TYP, '__new__', 4, 'type.__new__(cls, name, bases, dict, **kwds) -> type'),
    (ID_DICT_TYP, '__init__', 4, 'type.__init__(self, name, bases, dict, **kwds) -> None'),
    (ID_DICT_TYP, '__prepare__', 3, 'type.__prepare__(name, bases, **kwds) -> dict'),
    (ID_DICT_TYP, '__instancecheck__', 2, 'type.__instancecheck__(self, instance) -> bool'),
    (ID_DICT_TYP, '__subclasscheck__', 2, 'type.__subclasscheck__(self, subclass) -> bool'),
    (ID_DICT_TYP, 'mro', 1, 'type.mro(self) -> list'); -- Already added potentially but good to confirm

    -------------------------------------------------------
    -- 3. Loop and Create (Skipping duplicates if they exist)
    -------------------------------------------------------
    FOR V_DICT_ID, V_METH_NAME, V_ARG_COUNT, V_SIGNATURE IN SELECT target_dict_id, method_name, arg_count, signature FROM temp_meta_methods LOOP
        
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
        
        END IF;
        
    END LOOP;

END $$;
