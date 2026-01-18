-- =====================================================
-- Migration: Python Object Model
-- Description: Core tables for Python's internal object model
-- =====================================================

-------------------------------------------------------
-- 1. Core Object Table
-------------------------------------------------------
CREATE TABLE public.py_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_type uuid -- References py_type_object, added later due to circular dependency
);

-------------------------------------------------------
-- 2. Type System
-------------------------------------------------------
CREATE TABLE public.py_type_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  tp_name text NOT NULL,
  tp_bases uuid,  -- References py_tuple_object
  tp_dict uuid    -- References py_dict_object
);

-- Add circular reference constraint
ALTER TABLE public.py_object 
ADD CONSTRAINT fk_py_object_type 
FOREIGN KEY (ob_type) REFERENCES public.py_type_object(id);

-------------------------------------------------------
-- 3. String/Unicode Objects
-------------------------------------------------------
CREATE TABLE public.py_unicode_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  str_value text
);

-------------------------------------------------------
-- 4. Integer (Long) Objects
------- ------------------------------------------------
CREATE TABLE public.py_long_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  long_value bigint
);

-------------------------------------------------------
-- 5. Float Objects
-------------------------------------------------------
CREATE TABLE public.py_float_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  double_value double precision
);

-------------------------------------------------------
-- 6. Tuple Objects
-------------------------------------------------------
CREATE TABLE public.py_tuple_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  ob_item uuid[] -- Array of py_object IDs
);

-------------------------------------------------------
-- 7. List Objects
-------------------------------------------------------
CREATE TABLE public.py_list_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  ob_item uuid[] -- Array of py_object IDs
);

-------------------------------------------------------
-- 8. Dictionary Objects
-------------------------------------------------------
CREATE TABLE public.py_dict_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  ma_table jsonb, -- For potential JSON storage representation
  ma_used integer DEFAULT 0
);

CREATE TABLE public.py_dict_entry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dict_id uuid REFERENCES public.py_dict_object(id) ON DELETE CASCADE,
  me_key uuid REFERENCES public.py_object(id),
  me_value uuid REFERENCES public.py_object(id)
);

-------------------------------------------------------
-- 9. Set Objects
-------------------------------------------------------
CREATE TABLE public.py_set_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  ob_item uuid[]
);

-------------------------------------------------------
-- 10. Code Objects (Bytecode)
-------------------------------------------------------
CREATE TABLE public.py_code_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  co_name text,
  co_filename text,
  co_argcount integer,
  co_code text,
  co_consts uuid REFERENCES public.py_object(id),    -- Tuple of constants
  co_names uuid REFERENCES public.py_object(id),     -- Tuple of names
  co_varnames uuid REFERENCES public.py_object(id)   -- Tuple of local variable names
);

-------------------------------------------------------
-- 11. Function Objects
-------------------------------------------------------
CREATE TABLE public.py_function_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  func_name text,
  func_code uuid REFERENCES public.py_code_object(id),
  func_globals uuid REFERENCES public.py_dict_object(id)
);

-------------------------------------------------------
-- 12. Instance Objects
-------------------------------------------------------
CREATE TABLE public.py_instance_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  in_dict uuid REFERENCES public.py_dict_object(id)
);

-------------------------------------------------------
-- 13. Native/Built-in Function Objects
-------------------------------------------------------
CREATE TABLE public.py_js_function_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  fn_name text NOT NULL
);

-------------------------------------------------------
-- 14. Bound Method Objects
-------------------------------------------------------
CREATE TABLE public.py_bound_method_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  im_func uuid REFERENCES public.py_object(id), -- Points to function (py or js)
  im_self uuid REFERENCES public.py_object(id)  -- Points to instance
);

-------------------------------------------------------
-- 15. List Iterator Objects (for iteration support)
-------------------------------------------------------
CREATE TABLE public.py_list_iterator_object (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
  li_index integer DEFAULT 0,
  li_list uuid REFERENCES public.py_object(id)
);
