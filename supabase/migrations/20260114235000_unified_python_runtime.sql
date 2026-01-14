-- Unified Migration: Python Internal Runtime (Snake Case)
-- This file replaces all previous PyObject migrations and sets up the core runtime.

-------------------------------------------------------
-- 1. Core Tables
-------------------------------------------------------

-- Root object
CREATE TABLE public.py_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_type UUID, -- Refers to py_type_object
  ob_refcnt INTEGER DEFAULT 1,
  address BIGINT -- Simulated memory address
);

-- Type definitions
CREATE TABLE public.py_type_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  tp_name TEXT NOT NULL,
  tp_bases UUID, -- Refers to py_tuple_object
  tp_dict UUID,  -- Refers to py_dict_object
  tp_doc TEXT
);

-- Circular reference: link py_object to py_type_object
ALTER TABLE public.py_object 
ADD CONSTRAINT fk_py_object_type FOREIGN KEY (ob_type) REFERENCES public.py_type_object(id);

-- String/Unicode
CREATE TABLE public.py_unicode_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  str_value TEXT,
  ob_size INTEGER -- Length of string
);

-- Tuple
CREATE TABLE public.py_tuple_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  ob_item UUID[], -- Array of py_object IDs
  ob_size INTEGER
);

-- List
CREATE TABLE public.py_list_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  ob_item UUID[], -- Array of py_object IDs
  ob_size INTEGER,
  allocated INTEGER
);

-- Dictionary
CREATE TABLE public.py_dict_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  ma_used INTEGER DEFAULT 0
);

-- Dictionary Entry
CREATE TABLE public.py_dict_entry (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dict_id UUID REFERENCES public.py_dict_object(id) ON DELETE CASCADE,
  me_key UUID REFERENCES public.py_object(id),
  me_value UUID REFERENCES public.py_object(id)
);

-- Set
CREATE TABLE public.py_set_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  ob_item UUID[],
  ob_size INTEGER
);

-- Long (Integer)
CREATE TABLE public.py_long_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  long_value BIGINT
);

-- Float
CREATE TABLE public.py_float_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  double_value DOUBLE PRECISION
);

-- Code
CREATE TABLE public.py_code_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  co_name TEXT,
  co_filename TEXT,
  co_argcount INTEGER,
  co_code TEXT
);

-- Function
CREATE TABLE public.py_function_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  func_name TEXT,
  func_code UUID REFERENCES public.py_code_object(id),
  func_globals UUID REFERENCES public.py_dict_object(id)
);

-- Instance
CREATE TABLE public.py_instance_object (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  in_dict UUID REFERENCES public.py_dict_object(id)
);

-------------------------------------------------------
-- 2. Bootstrap Logic (Internal Objects)
-------------------------------------------------------

DO $$
DECLARE
    -- Core Type UUIDs
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYP_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_LST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUP_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    
    -- Base PyObject IDs
    B_OBJ UUID := gen_random_uuid();
    B_TYP UUID := gen_random_uuid();
    B_STR UUID := gen_random_uuid();
    B_INT UUID := gen_random_uuid();
    B_LST UUID := gen_random_uuid();
    B_DCT UUID := gen_random_uuid();
    B_TUP UUID := gen_random_uuid();
    B_FNC UUID := gen_random_uuid();

    -- Helpers
    ID_TUP_OBJ_ONLY UUID := gen_random_uuid();
    B_TUP_OBJ_ONLY UUID := gen_random_uuid();
BEGIN
    -- 1. Create Base PyObjects
    INSERT INTO public.py_object (id, ob_type, address) VALUES 
    (B_OBJ, NULL, 0x100), (B_TYP, NULL, 0x110), (B_STR, NULL, 0x120),
    (B_INT, NULL, 0x130), (B_LST, NULL, 0x140), (B_DCT, NULL, 0x150),
    (B_TUP, NULL, 0x160), (B_FNC, NULL, 0x170), (B_TUP_OBJ_ONLY, NULL, 0x999);

    -- 2. Create Core Types
    INSERT INTO public.py_type_object (id, ob_base, tp_name) VALUES
    (ID_OBJ_TYPE, B_OBJ, 'object'), (ID_TYP_TYPE, B_TYP, 'type'),
    (ID_STR_TYPE, B_STR, 'str'),    (ID_INT_TYPE, B_INT, 'int'),
    (ID_LST_TYPE, B_LST, 'list'),   (ID_DCT_TYPE, B_DCT, 'dict'),
    (ID_TUP_TYPE, B_TUP, 'tuple'),  (ID_FNC_TYPE, B_FNC, 'function');

    -- 3. Circular References
    UPDATE public.py_object SET ob_type = ID_TYP_TYPE WHERE id IN (B_OBJ, B_TYP, B_STR, B_INT, B_LST, B_DCT, B_TUP, B_FNC, B_TUP_OBJ_ONLY);

    -- 4. Set Hierarchy
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item, ob_size) VALUES (ID_TUP_OBJ_ONLY, B_TUP_OBJ_ONLY, ARRAY[B_OBJ], 1);
    UPDATE public.py_object SET ob_type = ID_TUP_TYPE WHERE id = B_TUP_OBJ_ONLY;

    UPDATE public.py_type_object SET tp_bases = ID_TUP_OBJ_ONLY WHERE id != ID_OBJ_TYPE;
END $$;

-------------------------------------------------------
-- 3. Security (RLS)
-------------------------------------------------------

ALTER TABLE public.py_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_type_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_unicode_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_tuple_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_list_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_dict_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_dict_entry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_set_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_long_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_float_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_code_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_function_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_instance_object ENABLE ROW LEVEL SECURITY;

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
