-- Migration: VM Implementation Step 1 (Bound Method & GetAttr)
-- Created at: 2026-01-17 00:00:00

DO $$
DECLARE
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    -- Method Type UUID
    ID_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000013';
    
    ID_DICT_METH UUID := gen_random_uuid();
    B_DICT_METH  UUID := gen_random_uuid();
BEGIN

    -------------------------------------------------------
    -- 1. Register 'builtin_method' type (or 'method')
    -------------------------------------------------------
    -- We'll call it 'method' for simplicity
    IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE id = ID_METHOD_TYPE) THEN
        -- Create Type Object
        INSERT INTO public.py_object (id, ob_type) VALUES (ID_METHOD_TYPE, ID_OBJ_TYPE);
        INSERT INTO public.py_type_object (id, ob_base, tp_name, tp_bases, tp_dict)
        VALUES (ID_METHOD_TYPE, ID_METHOD_TYPE, 'method', NULL, ID_DICT_METH); -- tp_dict will be created below
        
        -- Create empty dict for method type
        INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_METH, ID_DCT_TYPE);
        INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_METH, B_DICT_METH, 0);
        
        -- Update
        UPDATE public.py_type_object SET tp_dict = ID_DICT_METH WHERE id = ID_METHOD_TYPE;
    END IF;

END $$;

-------------------------------------------------------
-- 2. Create Table for Bound Methods
-------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.py_bound_method_object (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ob_base UUID REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
    im_func UUID REFERENCES public.py_object(id), -- Points to function (py or js)
    im_self UUID REFERENCES public.py_object(id)  -- Points to instance
);

-------------------------------------------------------
-- 3. VM Helper Functions
-------------------------------------------------------

-- A. vm_get_type(obj_id)
CREATE OR REPLACE FUNCTION public.vm_get_type(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    v_type UUID;
BEGIN
    SELECT ob_type INTO v_type FROM public.py_object WHERE id = obj_id;
    RETURN v_type;
END;
$$ LANGUAGE plpgsql;

-- B. vm_lookup_in_type(type_id, attr_name)
-- Searches for an attribute in the type's tp_dict.
-- TODO: Implement full MRO search. Currently checks Type -> Object.
CREATE OR REPLACE FUNCTION public.vm_lookup_in_type(type_id UUID, attr_name UUID)
RETURNS UUID AS $$
DECLARE
    v_dict_id UUID;
    v_value_id UUID;
    v_attr_str TEXT;
BEGIN
    -- This overload accepts UUID attr_name (key object) ?? 
    -- Actually user passes TEXT. Let's make a TEXT version.
    RETURN NULL; 
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS public.vm_lookup_in_type(UUID, UUID);

CREATE OR REPLACE FUNCTION public.vm_lookup_in_type(type_id UUID, attr_name TEXT)
RETURNS UUID AS $$
DECLARE
    v_dict_id UUID;
    v_value_id UUID;
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
BEGIN
    -- 1. Look in current Type
    SELECT tp_dict INTO v_dict_id FROM public.py_type_object WHERE id = type_id;
    
    -- Search in dict
    SELECT me_value INTO v_value_id
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = v_dict_id AND u.str_value = attr_name
    LIMIT 1;
    
    IF v_value_id IS NOT NULL THEN
        RETURN v_value_id;
    END IF;
    
    -- 2. Fallback to Object (if not already Object)
    IF type_id <> ID_OBJ_TYPE THEN
        RETURN public.vm_lookup_in_type(ID_OBJ_TYPE, attr_name);
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- C. vm_descriptor_get(descriptor_id, obj_id, type_id)
-- Handles turning a function into a bound method
CREATE OR REPLACE FUNCTION public.vm_descriptor_get(descriptor_id UUID, obj_id UUID, type_id UUID)
RETURNS UUID AS $$
DECLARE
    v_desc_type UUID;
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    ID_JS_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    ID_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000013';
    
    v_bound_base UUID;
    v_bound_obj UUID;
BEGIN
    v_desc_type := public.vm_get_type(descriptor_id);
    
    -- If it is a function (JS or Py), and accessed via instance (obj_id not null)
    IF (v_desc_type = ID_FNC_TYPE OR v_desc_type = ID_JS_FNC_TYPE) AND obj_id IS NOT NULL THEN
        -- Create Bound Method
        v_bound_base := gen_random_uuid();
        v_bound_obj := gen_random_uuid();
        
        -- Insert PyObject
        INSERT INTO public.py_object (id, ob_type) VALUES (v_bound_base, ID_METHOD_TYPE);
        
        -- Insert BoundMethod
        INSERT INTO public.py_bound_method_object (id, ob_base, im_func, im_self)
        VALUES (v_bound_obj, v_bound_base, descriptor_id, obj_id);
        
        RETURN v_bound_base; -- Return the PyObject ID
    END IF;
    
    -- Default: return descriptor itself
    RETURN descriptor_id;
END;
$$ LANGUAGE plpgsql;


-- D. vm_getattr(obj_id, attr_name)
CREATE OR REPLACE FUNCTION public.vm_getattr(obj_id UUID, attr_name TEXT)
RETURNS UUID AS $$
DECLARE
    v_type_id UUID;
    v_found_id UUID;
    v_bound_id UUID;
BEGIN
    -- 1. Get Type
    v_type_id := public.vm_get_type(obj_id);
    
    -- 2. Look in Type (and bases)
    v_found_id := public.vm_lookup_in_type(v_type_id, attr_name);
    
    IF v_found_id IS NOT NULL THEN
        -- 3. Descriptor Protocol (Simulated for functions)
        v_bound_id := public.vm_descriptor_get(v_found_id, obj_id, v_type_id);
        RETURN v_bound_id;
    END IF;
    
    -- 4. Look in Instance Dict (Not implemented yet for built-in types as they don't have usually)
    -- TODO: Add logic for custom object instances
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
