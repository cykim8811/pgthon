-- Migration: Open RLS for Python Runtime tables to public (anon)
-- Created at: 2026-01-15 23:50:00

-- Drop existing policies first to ideally avoid conflicts or multiple policies
DROP POLICY IF EXISTS "Public Read Access" ON public.py_object;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_type_object;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_unicode_object;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_tuple_object;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_list_object;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_dict_object;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_dict_entry;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_set_object;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_long_object;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_float_object;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_code_object;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_function_object;
DROP POLICY IF EXISTS "Public Read Access" ON public.py_instance_object;

-- Create new policies allowing access to everyone (true)
CREATE POLICY "Public Read Access" ON public.py_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_type_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_unicode_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_tuple_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_list_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_dict_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_dict_entry FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_set_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_long_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_float_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_code_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_function_object FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON public.py_instance_object FOR SELECT USING (true);
