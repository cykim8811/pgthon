-- =====================================================
-- Migration: Builtin Function Dynamic Dispatch Support
-- Description: 
--   1. Add 'fn_impl_name' to py_js_function_object for SQL implementation mapping.
--   2. Helper function to register built-ins cleanly.
-- =====================================================

-------------------------------------------------------
-- 1. Schema Extension
-------------------------------------------------------
ALTER TABLE public.py_builtin_function_object 
ADD COLUMN IF NOT EXISTS fn_impl_name text;

COMMENT ON COLUMN public.py_builtin_function_object.fn_impl_name IS 'Name of the PL/pgSQL function implementing this built-in';

-------------------------------------------------------
-- 2. Helper: Register Builtin
-------------------------------------------------------
-- Usage: vm_register_builtin('append', 'vm_impl_list_append', ID_BUILTIN_OBJ)
CREATE OR REPLACE FUNCTION public.vm_register_builtin(
    p_name text,
    p_impl_name text,
    p_builtin_id uuid, -- Table ID
    p_base_id uuid     -- Base ID
)
RETURNS void AS $$
DECLARE
    -- Builtin Function Type ID (Unified Base ID)
    ID_JS_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000012';
BEGIN
    -- 1. Create Base Object
    INSERT INTO public.py_object (id, ob_type) 
    VALUES (p_base_id, ID_JS_FNC_TYPE)
    ON CONFLICT (id) DO NOTHING;
    
    -- 2. Create Builtin Function Object
    INSERT INTO public.py_builtin_function_object (id, ob_base, fn_name, fn_impl_name)
    VALUES (p_builtin_id, p_base_id, p_name, p_impl_name)
    ON CONFLICT (id) 
    DO UPDATE SET fn_impl_name = EXCLUDED.fn_impl_name;
END;
$$ LANGUAGE plpgsql;
