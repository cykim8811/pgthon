-- =====================================================
-- Migration: Python Type System Bootstrap
-- Description: Initialize core Python types (object, type, str, int, list, dict, tuple, function)
-- =====================================================

DO $$
DECLARE
    -- Core Type UUIDs (Fixed IDs for bootstrapping)
    ID_OBJ_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    ID_TYP_TYPE uuid := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    ID_LST_TYPE uuid := '00000000-0000-4000-a000-000000000005';
    ID_DCT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
    ID_TUP_TYPE uuid := '00000000-0000-4000-a000-000000000007';
    ID_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000008';
    ID_NONE_TYPE uuid := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE uuid := '00000000-0000-4000-a000-000000000010';
    ID_CODE_TYPE uuid := '00000000-0000-4000-a000-000000000011';
    ID_JS_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000012';
    ID_METHOD_TYPE uuid := '00000000-0000-4000-a000-000000000013';
    
    -- Base PyObject IDs
    B_OBJ uuid := gen_random_uuid();
    B_TYP uuid := gen_random_uuid();
    B_STR uuid := gen_random_uuid();
    B_INT uuid := gen_random_uuid();
    B_LST uuid := gen_random_uuid();
    B_DCT uuid := gen_random_uuid();
    B_TUP uuid := gen_random_uuid();
    B_FNC uuid := gen_random_uuid();
    B_NONE_T uuid := gen_random_uuid();
    B_BOOL_T uuid := gen_random_uuid();
    B_CODE_T uuid := gen_random_uuid();
    B_JS_FNC uuid := gen_random_uuid();
    B_METHOD_T uuid := gen_random_uuid();

    -- Helper Tuples
    ID_TUP_OBJ_ONLY uuid :=gen_random_uuid();
    B_TUP_OBJ_ONLY uuid := gen_random_uuid();
    ID_TUP_INT_ONLY uuid := gen_random_uuid();
    B_TUP_INT_ONLY uuid := gen_random_uuid();
    
    -- Dicts for type __dict__
    ID_DICT_METHOD uuid := gen_random_uuid();
    B_DICT_METHOD uuid := gen_random_uuid();
    ID_DICT_CODE uuid := gen_random_uuid();
    B_DICT_CODE uuid := gen_random_uuid();
BEGIN
    -------------------------------------------------------
    -- 1. Create Base PyObjects
    -------------------------------------------------------
    INSERT INTO public.py_object (id, ob_type) VALUES 
    (B_OBJ, NULL), (B_TYP, NULL), (B_STR, NULL),
    (B_INT, NULL), (B_LST, NULL), (B_DCT, NULL),
    (B_TUP, NULL), (B_FNC, NULL), (B_TUP_OBJ_ONLY, NULL),
    (B_NONE_T, NULL), (B_BOOL_T, NULL), (B_CODE_T, NULL),
    (B_JS_FNC, NULL), (B_METHOD_T, NULL),
    (B_TUP_INT_ONLY, NULL);

    -------------------------------------------------------
    -- 2. Create Core Types
    -------------------------------------------------------
    INSERT INTO public.py_type_object (id, ob_base, tp_name) VALUES
    (ID_OBJ_TYPE, B_OBJ, 'object'), 
    (ID_TYP_TYPE, B_TYP, 'type'),
    (ID_STR_TYPE, B_STR, 'str'),    
    (ID_INT_TYPE, B_INT, 'int'),
    (ID_LST_TYPE, B_LST, 'list'),   
    (ID_DCT_TYPE, B_DCT, 'dict'),
    (ID_TUP_TYPE, B_TUP, 'tuple'),  
    (ID_FNC_TYPE, B_FNC, 'function'),
    (ID_NONE_TYPE, B_NONE_T, 'NoneType'),
    (ID_BOOL_TYPE, B_BOOL_T, 'bool'),
    (ID_CODE_TYPE, B_CODE_T, 'code'),
    (ID_JS_FNC_TYPE, B_JS_FNC, 'builtin_function_or_method'),
    (ID_METHOD_TYPE, B_METHOD_T, 'method');

    -------------------------------------------------------
    -- 3. Set ob_type for all type objects (circular reference)
    -------------------------------------------------------
    UPDATE public.py_object SET ob_type = ID_TYP_TYPE 
    WHERE id IN (
        B_OBJ, B_TYP, B_STR, B_INT, B_LST, B_DCT, B_TUP, B_FNC,
        B_NONE_T, B_BOOL_T, B_CODE_T, B_JS_FNC, B_METHOD_T
    );

    -------------------------------------------------------
    -- 4. Set up Type Hierarchy (tp_bases)
    -------------------------------------------------------
    
    -- Create tuple containing only 'object' for most types
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item) 
    VALUES (ID_TUP_OBJ_ONLY, B_TUP_OBJ_ONLY, ARRAY[B_OBJ]);
    UPDATE public.py_object SET ob_type = ID_TUP_TYPE WHERE id = B_TUP_OBJ_ONLY;

    -- Create tuple containing only 'int' for bool
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item) 
    VALUES (ID_TUP_INT_ONLY, B_TUP_INT_ONLY, ARRAY[B_INT]);
    UPDATE public.py_object SET ob_type = ID_TUP_TYPE WHERE id = B_TUP_INT_ONLY;

    -- Set tp_bases: all types except 'object' inherit from it
    UPDATE public.py_type_object SET tp_bases = ID_TUP_OBJ_ONLY 
    WHERE id != ID_OBJ_TYPE AND id != ID_BOOL_TYPE;
    
    -- bool inherits from int
    UPDATE public.py_type_object SET tp_bases = ID_TUP_INT_ONLY 
    WHERE id = ID_BOOL_TYPE;

    -------------------------------------------------------
    -- 5. Create empty __dict__ for special types
    -------------------------------------------------------
    
    -- method type dict
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_METHOD, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_METHOD, B_DICT_METHOD, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_METHOD WHERE id = ID_METHOD_TYPE;
    
    -- code type dict
    INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_CODE, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_CODE, B_DICT_CODE, 0);
    UPDATE public.py_type_object SET tp_dict = ID_DICT_CODE WHERE id = ID_CODE_TYPE;

END $$;
