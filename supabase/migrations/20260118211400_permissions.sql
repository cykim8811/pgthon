-- =====================================================
-- Migration: Row Level Security & Permissions
-- Description: Enable RLS and set policies for Python runtime tables
-- =====================================================

-------------------------------------------------------
-- 1. Enable RLS on all Python object tables
-------------------------------------------------------
ALTER TABLE public.py_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_type_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_unicode_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_long_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_float_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_tuple_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_list_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_dict_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_dict_entry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_set_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_code_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_function_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_instance_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_js_function_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_bound_method_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_list_iterator_object ENABLE ROW LEVEL SECURITY;

-------------------------------------------------------
-- 2. Public Read Access Policies
-- Note: For educational/experimental purposes, allowing everyone to read
-- In production, you'd want more restrictive policies
-------------------------------------------------------
CREATE POLICY "Public Read Access" ON public.py_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_type_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_unicode_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_long_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_float_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_tuple_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_list_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_dict_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_dict_entry FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_set_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_code_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_function_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_instance_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_js_function_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_bound_method_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_list_iterator_object FOR SELECT USING (true);

-------------------------------------------------------
-- 2.5 Public Write Access Policies  
-- Note: For educational/experimental purposes, allowing everyone to write
-- This enables the REPL and VM operations from the web interface
-------------------------------------------------------
CREATE POLICY "Public Insert Access" ON public.py_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_type_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_unicode_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_long_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_float_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_tuple_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_list_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_dict_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_dict_entry FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_set_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_code_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_function_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_instance_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_js_function_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_bound_method_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Insert Access" ON public.py_list_iterator_object FOR INSERT WITH CHECK (true);

CREATE POLICY "Public Update Access" ON public.py_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_type_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_unicode_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_long_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_float_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_tuple_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_list_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_dict_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_dict_entry FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_set_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_code_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_function_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_instance_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_js_function_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_bound_method_object FOR UPDATE USING (true);
CREATE POLICY "Public Update Access" ON public.py_list_iterator_object FOR UPDATE USING (true);

-------------------------------------------------------
-- 3. Grant Execute Permissions on VM Functions
-------------------------------------------------------

-- Grant execute on VM core functions
GRANT EXECUTE ON FUNCTION public.vm_get_type(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_lookup_in_type(uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_descriptor_get(uuid, uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_getattr(uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_create_bound_method(uuid, uuid) TO anon, authenticated;

-- Grant execute on VM helpers
GRANT EXECUTE ON FUNCTION public.vm_get_none() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_create_int(bigint) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_get_int_value(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_create_str(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_tuple_getitem(uuid, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_dict_set_item(uuid, text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_dict_get_item(uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_is_true(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_compare(uuid, uuid, integer) TO anon, authenticated;

-- Grant execute on VM operations
GRANT EXECUTE ON FUNCTION public.vm_add(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_native_dispatch(text, uuid[]) TO anon, authenticated;

-- Grant execute on VM call system
GRANT EXECUTE ON FUNCTION public.vm_call(uuid, uuid[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_run_frame(uuid, uuid, uuid) TO anon, authenticated;

-- Grant execute on VM tools
GRANT EXECUTE ON FUNCTION public.vm_assemble(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_assembler_get_or_create_const(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_inspect_object(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vm_execute_source(text) TO anon, authenticated;

-------------------------------------------------------
-- 4. Grant Insert/Update Permissions for VM Operations
-- VM functions need to create and modify objects during execution
-------------------------------------------------------
GRANT INSERT, UPDATE ON public.py_object TO anon, authenticated;
GRANT INSERT, UPDATE ON public.py_long_object TO anon, authenticated;
GRANT INSERT, UPDATE ON public.py_unicode_object TO anon, authenticated;
GRANT INSERT, UPDATE ON public.py_tuple_object TO anon, authenticated;
GRANT INSERT, UPDATE ON public.py_list_object TO anon, authenticated;
GRANT INSERT, UPDATE ON public.py_dict_object TO anon, authenticated;
GRANT INSERT, UPDATE ON public.py_dict_entry TO anon, authenticated;
GRANT INSERT, UPDATE ON public.py_code_object TO anon, authenticated;
GRANT INSERT, UPDATE ON public.py_bound_method_object TO anon, authenticated;
GRANT INSERT, UPDATE ON public.py_list_iterator_object TO anon, authenticated;
