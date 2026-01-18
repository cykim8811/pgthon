-- Migration: Grant usage and select permissions to anon and authenticated roles
-- Created at: 2026-01-16 00:00:00

-- Grant usage on schema (usually enabled by default, but good to ensure)
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;

-- Grant select on all python runtime tables to anon and authenticated
GRANT SELECT ON public.py_object TO anon, authenticated;
GRANT SELECT ON public.py_type_object TO anon, authenticated;
GRANT SELECT ON public.py_unicode_object TO anon, authenticated;
GRANT SELECT ON public.py_tuple_object TO anon, authenticated;
GRANT SELECT ON public.py_list_object TO anon, authenticated;
GRANT SELECT ON public.py_dict_object TO anon, authenticated;
GRANT SELECT ON public.py_dict_entry TO anon, authenticated;
GRANT SELECT ON public.py_set_object TO anon, authenticated;
GRANT SELECT ON public.py_long_object TO anon, authenticated;
GRANT SELECT ON public.py_float_object TO anon, authenticated;
GRANT SELECT ON public.py_code_object TO anon, authenticated;
GRANT SELECT ON public.py_function_object TO anon, authenticated;
GRANT SELECT ON public.py_instance_object TO anon, authenticated;

-- Also ensure sequences are accessible if needed (though we use UUIDs mostly)
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
