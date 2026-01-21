-- =====================================================
-- Migration: Fix vm_create_function Signature and Globals (Force Replace)
-- Description: 
--   1. DROP existing overload to resolve ambiguity.
--   2. Update vm_create_function to accept p_globals (Base ID) and explicit p_code_base_id.
-- =====================================================

-- Drop old signature explicitly to avoid ambiguity
DROP FUNCTION IF EXISTS public.vm_create_function(uuid, uuid, uuid, text);

-- Define new signature
CREATE OR REPLACE FUNCTION public.vm_create_function(
    p_id uuid,          -- Base ID of the new function object
    p_func_id uuid,     -- Table ID of the new function object
    p_code_base_id uuid,-- Base ID of code object
    p_name text,
    p_globals uuid DEFAULT NULL -- Base ID of globals dictionary
)
RETURNS void AS $$
DECLARE
    ID_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000008';
BEGIN
    INSERT INTO public.py_object (id, ob_type) VALUES (p_id, ID_FNC_TYPE);
    
    INSERT INTO public.py_function_object (id, ob_base, func_name, func_code, func_globals)
    VALUES (p_func_id, p_id, p_name, p_code_base_id, p_globals);
END;
$$ LANGUAGE plpgsql;
