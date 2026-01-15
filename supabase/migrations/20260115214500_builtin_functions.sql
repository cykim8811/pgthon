-- Migration: Built-in Functions as Objects
-- Created at: 2026-01-15 21:45:00

DO $$
DECLARE
    -- Type IDs
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008'; -- function type
    -- We'll need a code object type too, but for now we just use PyObject
    -- Let's assume there's a PyCodeObject.id? Actually we didn't define a specific PyTypeObject for 'code' yet in the bootstrap.
    -- Let's just create a generic type for code if it doesn't exist, or just use what we have.
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    
    -- Helper IDs for types
    B_CODE_T UUID := gen_random_uuid();
    
    -- Function: len
    B_LEN_OBJ UUID := gen_random_uuid();
    B_LEN_CODE UUID := gen_random_uuid();
    ID_LEN_CODE UUID := gen_random_uuid();
    ID_LEN_FNC UUID := gen_random_uuid();

    -- Function: print
    B_PRT_OBJ UUID := gen_random_uuid();
    B_PRT_CODE UUID := gen_random_uuid();
    ID_PRT_CODE UUID := gen_random_uuid();
    ID_PRT_FNC UUID := gen_random_uuid();

    -- Function: id
    B_ID_OBJ UUID := gen_random_uuid();
    B_ID_CODE UUID := gen_random_uuid();
    ID_ID_CODE UUID := gen_random_uuid();
    ID_ID_FNC UUID := gen_random_uuid();

    -- Function: type
    B_TYP_OBJ UUID := gen_random_uuid();
    B_TYP_CODE UUID := gen_random_uuid();
    ID_TYP_CODE UUID := gen_random_uuid();
    ID_TYP_FNC UUID := gen_random_uuid();

BEGIN
    -------------------------------------------------------
    -- 0. Bootstrap Code Type if missing
    -------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE id = ID_CODE_TYPE) THEN
        INSERT INTO public.py_object (id, ob_type) VALUES (B_CODE_T, '00000000-0000-4000-a000-000000000002'); -- type is 'type'
        INSERT INTO public.py_type_object (id, ob_base, tp_name) VALUES (ID_CODE_TYPE, B_CODE_T, 'code');
    END IF;

    -------------------------------------------------------
    -- 1. Create Base Objects for Functions and Code
    -------------------------------------------------------
    INSERT INTO public.py_object (id, ob_type) VALUES 
    (B_LEN_OBJ, ID_FNC_TYPE), (B_LEN_CODE, ID_CODE_TYPE),
    (B_PRT_OBJ, ID_FNC_TYPE), (B_PRT_CODE, ID_CODE_TYPE),
    (B_ID_OBJ,  ID_FNC_TYPE), (B_ID_CODE,  ID_CODE_TYPE),
    (B_TYP_OBJ, ID_FNC_TYPE), (B_TYP_CODE, ID_CODE_TYPE);

    -------------------------------------------------------
    -- 2. Create Code Objects
    -------------------------------------------------------
    INSERT INTO public.py_code_object (id, ob_base, co_name, co_filename, co_argcount, co_code) VALUES
    (ID_LEN_CODE, B_LEN_CODE, 'len', '<built-in>', 1, '<built-in function len>'),
    (ID_PRT_CODE, B_PRT_CODE, 'print', '<built-in>', 0, '<built-in function print>'),
    (ID_ID_CODE,  B_ID_CODE,  'id', '<built-in>', 1, '<built-in function id>'),
    (ID_TYP_CODE, B_TYP_CODE, 'type', '<built-in>', 1, '<built-in function type>');

    -------------------------------------------------------
    -- 3. Create Function Objects
    -------------------------------------------------------
    INSERT INTO public.py_function_object (id, ob_base, func_name, func_code, func_globals) VALUES
    (ID_LEN_FNC, B_LEN_OBJ, 'len', ID_LEN_CODE, NULL),
    (ID_PRT_FNC, B_PRT_OBJ, 'print', ID_PRT_CODE, NULL),
    (ID_ID_FNC,  B_ID_OBJ,  'id', ID_ID_CODE, NULL),
    (ID_TYP_FNC, B_TYP_OBJ, 'type', ID_TYP_CODE, NULL);

END $$;
