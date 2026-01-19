-- =====================================================
-- Migration: VM Helper Functions
-- Description: Core helper functions for object creation and manipulation
-- =====================================================

-------------------------------------------------------
-- 1. vm_get_none: Get the None singleton
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_get_none()
RETURNS uuid AS $$
DECLARE
    ID_NONE_OBJ uuid := '00000000-0000-4000-b000-000000000001';
BEGIN
    RETURN ID_NONE_OBJ;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 2. vm_create_int: Create a new integer object
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_create_int(p_val bigint)
RETURNS uuid AS $$
DECLARE
    ID_INT_TYPE uuid := '00000000-0000-4000-a000-000000000004';
    v_obj_id uuid;
    v_base_id uuid;
BEGIN
    v_base_id := gen_random_uuid();
    v_obj_id := gen_random_uuid();
    
    -- Create py_object
    INSERT INTO public.py_object (id, ob_type) VALUES (v_base_id, ID_INT_TYPE);
    
    -- Create py_long_object
    INSERT INTO public.py_long_object (id, ob_base, long_value) 
    VALUES (v_obj_id, v_base_id, p_val);
    
    RETURN v_base_id;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 3. vm_get_int_value: Get integer value from object
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_get_int_value(p_obj_id uuid)
RETURNS bigint AS $$
DECLARE
    v_val bigint;
BEGIN
    SELECT long_value INTO v_val FROM public.py_long_object WHERE ob_base = p_obj_id;
    RETURN COALESCE(v_val, 0);
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 4. vm_create_str: Create a new string object
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_create_str(p_val text)
RETURNS uuid AS $$
DECLARE
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    v_obj_id uuid;
    v_base_id uuid;
BEGIN
    v_base_id := gen_random_uuid();
    v_obj_id := gen_random_uuid();
    
    INSERT INTO public.py_object (id, ob_type) VALUES (v_base_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (id, ob_base, str_value) 
    VALUES (v_obj_id, v_base_id, p_val);
    
    RETURN v_base_id;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 4.2. vm_get_str_value: Get string value from object
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_get_str_value(p_obj_id uuid)
RETURNS text AS $$
DECLARE
    v_val text;
BEGIN
    SELECT str_value INTO v_val FROM public.py_unicode_object WHERE ob_base = p_obj_id;
    RETURN COALESCE(v_val, '');
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 4.5. vm_create_dict: Create a new empty dictionary object
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_create_dict()
RETURNS uuid AS $$
DECLARE
    ID_DCT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
    v_obj_id uuid;
    v_base_id uuid;
BEGIN
    v_base_id := gen_random_uuid();
    v_obj_id := gen_random_uuid();
    
    -- Create py_object
    INSERT INTO public.py_object (id, ob_type) VALUES (v_base_id, ID_DCT_TYPE);
    
    -- Create py_dict_object
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) 
    VALUES (v_obj_id, v_base_id, 0);
    
    RETURN v_base_id; -- Consistently return base object ID
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 4.8. vm_create_tuple: Create a new tuple object from array of IDs
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_create_tuple(p_items uuid[])
RETURNS uuid AS $$
DECLARE
    ID_TUP_TYPE uuid := '00000000-0000-4000-a000-000000000007';
    v_obj_id uuid;
    v_base_id uuid;
BEGIN
    v_base_id := gen_random_uuid();
    v_obj_id := gen_random_uuid();
    
    -- Create py_object
    INSERT INTO public.py_object (id, ob_type) VALUES (v_base_id, ID_TUP_TYPE);
    
    -- Create py_tuple_object
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item) 
    VALUES (v_obj_id, v_base_id, p_items);
    
    RETURN v_base_id;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 5. vm_tuple_getitem: Get item from tuple by index
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_tuple_getitem(p_tuple_id uuid, p_index integer)
RETURNS uuid AS $$
DECLARE
    v_items uuid[];
BEGIN
    SELECT ob_item INTO v_items FROM public.py_tuple_object WHERE ob_base = p_tuple_id;
    
    -- Check bounds (convert from 0-based Python index to 1-based SQL)
    IF p_index + 1 > array_length(v_items, 1) OR p_index < 0 THEN
        RAISE EXCEPTION 'IndexError: tuple index out of range';
    END IF;
    
    RETURN v_items[p_index + 1];
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 6. vm_dict_set_item: Set item in dictionary by string key
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_dict_set_item(
    p_dict_id uuid, 
    p_key_str text, 
    p_value_id uuid
)
RETURNS void AS $$
DECLARE
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    v_key_obj uuid;
    v_key_base uuid;
    v_existing uuid;
    v_internal_dict_id uuid;
BEGIN
    -- Resolve base object ID to internal dict ID
    SELECT id INTO v_internal_dict_id FROM public.py_dict_object WHERE ob_base = p_dict_id;
    IF v_internal_dict_id IS NULL THEN
        -- If it's already an internal ID, use it directly (fallback)
        v_internal_dict_id := p_dict_id;
    END IF;

    -- Check if key already exists
    SELECT me_key INTO v_existing
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = v_internal_dict_id AND u.str_value = p_key_str
    LIMIT 1;
    
    IF v_existing IS NOT NULL THEN
        -- Update existing entry
        UPDATE public.py_dict_entry 
        SET me_value = p_value_id
        WHERE dict_id = p_dict_id AND me_key = v_existing;
    ELSE
        -- Create new key string object
        v_key_base := gen_random_uuid();
        v_key_obj := gen_random_uuid();
        
        INSERT INTO public.py_object (id, ob_type) VALUES (v_key_base, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) 
        VALUES (v_key_obj, v_key_base, p_key_str);
        
        -- Insert new entry
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value)
        VALUES (gen_random_uuid(), v_internal_dict_id, v_key_base, p_value_id);
        
        -- Update usage count
        UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = v_internal_dict_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 7. vm_dict_get_item: Get item from dictionary by string key
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_dict_get_item(p_dict_id uuid, p_key_str text)
RETURNS uuid AS $$
DECLARE
    v_val_id uuid;
    v_internal_dict_id uuid;
BEGIN
    -- Resolve base object ID to internal dict ID
    SELECT id INTO v_internal_dict_id FROM public.py_dict_object WHERE ob_base = p_dict_id;
    IF v_internal_dict_id IS NULL THEN
        v_internal_dict_id := p_dict_id;
    END IF;

    SELECT e.me_value INTO v_val_id
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = v_internal_dict_id AND u.str_value = p_key_str
    LIMIT 1;
    
    RETURN v_val_id;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 8. vm_is_true: Truth testing for Python objects
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_is_true(p_obj_id uuid)
RETURNS boolean AS $$
DECLARE
    ID_TRUE_OBJ  uuid := '00000000-0000-4000-b000-000000000002';
    ID_FALSE_OBJ uuid := '00000000-0000-4000-b000-000000000003';
    ID_NONE_OBJ  uuid := '00000000-0000-4000-b000-000000000001';
    
    v_long_val bigint;
BEGIN
    -- 1. Check singletons
    IF p_obj_id = ID_TRUE_OBJ THEN RETURN TRUE; END IF;
    IF p_obj_id = ID_FALSE_OBJ THEN RETURN FALSE; END IF;
    IF p_obj_id = ID_NONE_OBJ THEN RETURN FALSE; END IF;
    
    -- 2. Check Int/Bool (0 is False, non-zero is True)
    SELECT long_value INTO v_long_val FROM public.py_long_object WHERE ob_base = p_obj_id;
    IF v_long_val IS NOT NULL THEN
        RETURN v_long_val <> 0;
    END IF;
    
    -- 3. Default: True (like Python objects)
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 9. vm_compare: Comparison operations
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_compare(p_left uuid, p_right uuid, p_op_idx integer)
RETURNS uuid AS $$
DECLARE
    ID_TRUE_OBJ  uuid := '00000000-0000-4000-b000-000000000002';
    ID_FALSE_OBJ uuid := '00000000-0000-4000-b000-000000000003';
    
    v_l_val bigint;
    v_r_val bigint;
    v_result boolean;
BEGIN
    -- Try fetching integer values (works for int and bool)
    SELECT long_value INTO v_l_val FROM public.py_long_object WHERE ob_base = p_left;
    SELECT long_value INTO v_r_val FROM public.py_long_object WHERE ob_base = p_right;
    
    IF v_l_val IS NOT NULL AND v_r_val IS NOT NULL THEN
        -- Comparison operations: 0:<, 1:<=, 2:==, 3:!=, 4:>, 5:>=
        CASE p_op_idx
            WHEN 0 THEN v_result := (v_l_val < v_r_val);
            WHEN 1 THEN v_result := (v_l_val <= v_r_val);
            WHEN 2 THEN v_result := (v_l_val = v_r_val);
            WHEN 3 THEN v_result := (v_l_val <> v_r_val);
            WHEN 4 THEN v_result := (v_l_val > v_r_val);
            WHEN 5 THEN v_result := (v_l_val >= v_r_val);
            ELSE v_result := FALSE;
        END CASE;
        
        IF v_result THEN RETURN ID_TRUE_OBJ; ELSE RETURN ID_FALSE_OBJ; END IF;
    END IF;
    
    -- Fallback: identity comparison for == and !=
    IF p_op_idx = 2 THEN -- ==
        IF p_left = p_right THEN RETURN ID_TRUE_OBJ; ELSE RETURN ID_FALSE_OBJ; END IF;
    ELSIF p_op_idx = 3 THEN -- !=
        IF p_left <> p_right THEN RETURN ID_TRUE_OBJ; ELSE RETURN ID_FALSE_OBJ; END IF;
    END IF;
    
    RAISE EXCEPTION 'TypeError: Comparison not supported for these types';
END;
$$ LANGUAGE plpgsql;
