-- =====================================================
-- Migration: Type Methods Registration
-- Description: Add __dict__ to types and register methods (str, list, int, dict, object)
-- =====================================================

DO $$
DECLARE
    -- Type IDs
    ID_OBJ_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    ID_LST_TYPE uuid := '00000000-0000-4000-a000-000000000005';
    ID_DCT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
    ID_JS_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000012';

    -- Dict IDs for type __dict__
    ID_DICT_OBJ uuid := gen_random_uuid();
    B_DICT_OBJ uuid := gen_random_uuid();
    
    ID_DICT_STR uuid := gen_random_uuid();
    B_DICT_STR uuid := gen_random_uuid();
    
    ID_DICT_INT uuid := gen_random_uuid();
    B_DICT_INT uuid := gen_random_uuid();
    
    ID_DICT_LST uuid := gen_random_uuid();
    B_DICT_LST uuid := gen_random_uuid();
    
    ID_DICT_DCT uuid := gen_random_uuid();
    B_DICT_DCT uuid := gen_random_uuid();

    -- Helper variables
    method_rec record;
    func_obj_id uuid;
    func_base_id uuid;
    key_base_id uuid;
BEGIN
    -------------------------------------------------------
    -- 1. Create tp_dict for Each Type
    -------------------------------------------------------
    
    -- object.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_OBJ, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_OBJ, B_DICT_OBJ, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_OBJ WHERE id = ID_OBJ_TYPE;

    -- str.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_STR, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_STR, B_DICT_STR, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_STR WHERE id = ID_STR_TYPE;

    -- int.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_INT, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_INT, B_DICT_INT, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_INT WHERE id = ID_INT_TYPE;

    -- list.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_LST, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_LST, B_DICT_LST, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_LST WHERE id = ID_LST_TYPE;

    -- dict.__dict__
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_DCT, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_DCT, B_DICT_DCT, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_DCT WHERE id = ID_DCT_TYPE;

    -------------------------------------------------------
    -- 2. Register Methods for Each Type
    -------------------------------------------------------
    
    -- Create a temporary table with all methods to register
    CREATE TEMP TABLE temp_type_methods (
        type_dict_id uuid,
        method_name text
    ) ON COMMIT DROP;

    -- object methods
    INSERT INTO temp_type_methods VALUES 
    (ID_DICT_OBJ, '__init__'),
    (ID_DICT_OBJ, '__str__'),
    (ID_DICT_OBJ, '__repr__'),
    
    -- str methods
    (ID_DICT_STR, 'upper'),
    (ID_DICT_STR, 'lower'),
    (ID_DICT_STR, 'strip'),
    (ID_DICT_STR, 'split'),
    (ID_DICT_STR, 'join'),
    (ID_DICT_STR, 'replace'),
    (ID_DICT_STR, 'startswith'),
    (ID_DICT_STR, 'endswith'),
    
    -- int methods (and magic methods)
    (ID_DICT_INT, '__add__'),
    (ID_DICT_INT, '__sub__'),
    (ID_DICT_INT, '__mul__'),
    (ID_DICT_INT, '__floordiv__'),
    (ID_DICT_INT, '__mod__'),
    (ID_DICT_INT, '__pow__'),
    (ID_DICT_INT, '__str__'),
    (ID_DICT_INT, '__repr__'),
    
    -- list methods
    (ID_DICT_LST, 'append'),
    (ID_DICT_LST, 'extend'),
    (ID_DICT_LST, 'pop'),
    (ID_DICT_LST, 'remove'),
    (ID_DICT_LST, 'insert'),
    (ID_DICT_LST, 'clear'),
    (ID_DICT_LST, 'sort'),
    (ID_DICT_LST, 'reverse'),
    (ID_DICT_LST, '__iter__'),
    
    -- dict methods
    (ID_DICT_DCT, 'keys'),
    (ID_DICT_DCT, 'values'),
    (ID_DICT_DCT, 'items'),
    (ID_DICT_DCT, 'get'),
    (ID_DICT_DCT, 'pop'),
    (ID_DICT_DCT, 'update'),
    (ID_DICT_DCT, 'clear');

    -- Loop through and create method objects
    FOR method_rec IN SELECT type_dict_id, method_name FROM temp_type_methods
    LOOP
        func_obj_id := gen_random_uuid();
        func_base_id := gen_random_uuid();
        key_base_id := gen_random_uuid();

        -- Create Key String Object
        INSERT INTO public.py_object (id, ob_type) VALUES (key_base_id, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) 
        VALUES (gen_random_uuid(), key_base_id, method_rec.method_name);

        -- Create JS Function Object (Method)
        INSERT INTO public.py_object (id, ob_type) VALUES (func_base_id, ID_JS_FNC_TYPE);
        INSERT INTO public.py_js_function_object (id, ob_base, fn_name)
        VALUES (func_obj_id, func_base_id, method_rec.method_name);

        -- Link to Type Dict
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) 
        VALUES (gen_random_uuid(), method_rec.type_dict_id, key_base_id, func_base_id);
        
        -- Update usage count
        UPDATE public.py_dict_object SET ma_used = ma_used + 1 
        WHERE id = method_rec.type_dict_id;
    END LOOP;

END $$;
