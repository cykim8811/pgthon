-- Migration: VM REPL Helpers (vm_execute_source)
-- Created at: 2026-01-18 00:00:40

-------------------------------------------------------
-- API: Execute Source (Assemble + Run)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_execute_source(p_source TEXT)
RETURNS UUID AS $$
DECLARE
    v_code_id UUID;
    v_locals_id UUID;
    v_base_locals UUID := gen_random_uuid();
    v_res UUID;
    
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
BEGIN
    -- 1. Assemble
    v_code_id := public.vm_assemble(p_source, 'web_repl');
    
    -- 2. Create Locals
    v_locals_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_base_locals, ID_DCT_TYPE);
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (v_locals_id, v_base_locals, 0);
    
    -- 3. Run
    v_res := public.vm_run_frame(v_code_id, v_locals_id, NULL);
    
    RETURN v_res;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
