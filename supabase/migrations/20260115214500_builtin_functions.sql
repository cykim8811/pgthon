-- Migration: Built-in Functions as Objects
-- Created at: 2026-01-15 21:45:00

DO $$
DECLARE
    -- Type IDs
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008'; 
    -- Change to JS Function Type for built-ins
    ID_JS_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    
    -- Helper IDs (Base Objects)
    -- Function: len
    B_LEN_OBJ UUID := gen_random_uuid();
    ID_LEN_FNC UUID := gen_random_uuid();

    -- Function: print
    B_PRT_OBJ UUID := gen_random_uuid();
    ID_PRT_FNC UUID := gen_random_uuid();

    -- Function: id
    B_ID_OBJ UUID := gen_random_uuid();
    ID_ID_FNC UUID := gen_random_uuid();

    -- Function: type
    B_TYP_OBJ UUID := gen_random_uuid();
    ID_TYP_FNC UUID := gen_random_uuid();

BEGIN
    -------------------------------------------------------
    -- 1. Create Base Objects for Functions (Type is JS_FNC now)
    -------------------------------------------------------
    INSERT INTO public.py_object (id, ob_type) VALUES 
    (B_LEN_OBJ, ID_JS_FNC_TYPE),
    (B_PRT_OBJ, ID_JS_FNC_TYPE),
    (B_ID_OBJ,  ID_JS_FNC_TYPE),
    (B_TYP_OBJ, ID_JS_FNC_TYPE);

    -------------------------------------------------------
    -- 2. Create JS Function Objects (Native Implementation)
    -------------------------------------------------------
    INSERT INTO public.py_js_function_object (id, ob_base, fn_name) VALUES
    (ID_LEN_FNC, B_LEN_OBJ, 'len'),
    (ID_PRT_FNC, B_PRT_OBJ, 'print'),
    (ID_ID_FNC,  B_ID_OBJ,  'id'),
    (ID_TYP_FNC, B_TYP_OBJ, 'type');

END $$;
