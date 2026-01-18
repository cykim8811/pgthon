-- =====================================================
-- Migration: VM Object Protocol
-- Description: Core VM functions for object attribute access and type lookup
-- =====================================================

-------------------------------------------------------
-- 1. vm_get_type: Get the type of an object
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_get_type(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    v_type uuid;
BEGIN
    SELECT ob_type INTO v_type FROM public.py_object WHERE id = obj_id;
    RETURN v_type;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 2. vm_lookup_in_type: Search for attribute in type's MRO
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_lookup_in_type(type_id uuid, attr_name text)
RETURNS uuid AS $$
DECLARE
    v_dict_id uuid;
    v_value_id uuid;
    ID_OBJ_TYPE uuid := '00000000-0000-4000-a000-000000000001';
BEGIN
    -- 1. Look in current Type's tp_dict
    SELECT tp_dict INTO v_dict_id FROM public.py_type_object WHERE id = type_id;
    
    -- Search in dict by string key
    SELECT e.me_value INTO v_value_id
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = v_dict_id AND u.str_value = attr_name
    LIMIT 1;
    
    IF v_value_id IS NOT NULL THEN
        RETURN v_value_id;
    END IF;
    
    -- 2. Fallback to 'object' type (simplified MRO)
    IF type_id <> ID_OBJ_TYPE THEN
        RETURN public.vm_lookup_in_type(ID_OBJ_TYPE, attr_name);
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 3. vm_descriptor_get: Handle descriptor protocol (function binding)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_descriptor_get(
    descriptor_id uuid, 
    obj_id uuid, 
    type_id uuid
)
RETURNS uuid AS $$
DECLARE
    v_desc_type uuid;
    ID_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000008';
    ID_JS_FNC_TYPE uuid := '00000000-0000-4000-a000-000000000012';
    ID_METHOD_TYPE uuid := '00000000-0000-4000-a000-000000000013';
    
    v_bound_base uuid;
    v_bound_obj uuid;
BEGIN
    v_desc_type := public.vm_get_type(descriptor_id);
    
    -- If it's a function and accessed via instance, create bound method
    IF (v_desc_type = ID_FNC_TYPE OR v_desc_type = ID_JS_FNC_TYPE) AND obj_id IS NOT NULL THEN
        v_bound_base := gen_random_uuid();
        v_bound_obj := gen_random_uuid();
        
        -- Create PyObject for bound method
        INSERT INTO public.py_object (id, ob_type) VALUES (v_bound_base, ID_METHOD_TYPE);
        
        -- Create BoundMethod linking function and self
        INSERT INTO public.py_bound_method_object (id, ob_base, im_func, im_self)
        VALUES (v_bound_obj, v_bound_base, descriptor_id, obj_id);
        
        RETURN v_bound_base;
    END IF;
    
    -- Default: return descriptor itself (e.g., class method, static method, or data)
    RETURN descriptor_id;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 4. vm_getattr: Get attribute from object
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_getattr(obj_id uuid, attr_name text)
RETURNS uuid AS $$
DECLARE
    v_type_id uuid;
    v_found_id uuid;
    v_bound_id uuid;
BEGIN
    -- 1. Get object's type
    v_type_id := public.vm_get_type(obj_id);
    
    -- 2. Look in Type (and bases via MRO)
    v_found_id := public.vm_lookup_in_type(v_type_id, attr_name);
    
    IF v_found_id IS NOT NULL THEN
        -- 3. Apply descriptor protocol (bind if it's a function)
        v_bound_id := public.vm_descriptor_get(v_found_id, obj_id, v_type_id);
        RETURN v_bound_id;
    END IF;
    
    -- 4. TODO: Look in instance __dict__ for custom objects
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 5. vm_create_bound_method: Helper to create bound methods
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_create_bound_method(func_id uuid, self_id uuid)
RETURNS uuid AS $$
DECLARE
    v_method_id uuid := gen_random_uuid();
    v_base_id uuid := gen_random_uuid();
    ID_METHOD_TYPE uuid := '00000000-0000-4000-a000-000000000013';
BEGIN
    INSERT INTO public.py_object (id, ob_type) VALUES (v_base_id, ID_METHOD_TYPE);
    INSERT INTO public.py_bound_method_object (id, ob_base, im_func, im_self)
    VALUES (v_method_id, v_base_id, func_id, self_id);
    
    RETURN v_base_id;
END;
$$ LANGUAGE plpgsql;
