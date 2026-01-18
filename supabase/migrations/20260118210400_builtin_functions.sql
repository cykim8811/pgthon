-- =====================================================
-- Migration: Built-in Functions
-- Description: Register built-in functions (len, print, id, type) as objects
-- =====================================================

DO $$
DECLARE
    -- Type ID
    ID_JS_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000012';
    
    -- Function objects
    funcs text[] := ARRAY['len', 'print', 'id', 'type'];
    func_name text;
    base_id uuid;
    obj_id uuid;
BEGIN
    -------------------------------------------------------
    -- Create Built-in Function Objects
    -------------------------------------------------------
    FOREACH func_name IN ARRAY funcs
    LOOP
        base_id := gen_random_uuid();
        obj_id := gen_random_uuid();
        
        -- Create PyObject
        INSERT INTO public.py_object (id, ob_type) VALUES (base_id, ID_JS_FNC_TYPE);
        
        -- Create JS Function Object
        INSERT INTO public.py_js_function_object (id, ob_base, fn_name)
        VALUES (obj_id, base_id, func_name);
    END LOOP;

END $$;
