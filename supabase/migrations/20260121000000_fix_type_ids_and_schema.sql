-- =====================================================
-- Migration: Complete Base ID Unification
-- Description: 
--   1. Align Built-in Type Base IDs with their Fixed Table IDs
--      (Fixes ob_type references implicitly).
--   2. Fix py_type_object.tp_bases to use Base IDs.
--   3. Update Schema Constraints to enforce Base ID usage.
--   4. Update VM functions to use Base ID lookups.
-- =====================================================

DO $$
DECLARE
    -- The list of fixed IDs for Built-in Types (from bootstrap)
    IDS uuid[] := ARRAY[
        '00000000-0000-4000-a000-000000000001', -- object
        '00000000-0000-4000-a000-000000000002', -- type
        '00000000-0000-4000-a000-000000000003', -- str
        '00000000-0000-4000-a000-000000000004', -- int
        '00000000-0000-4000-a000-000000000005', -- list
        '00000000-0000-4000-a000-000000000006', -- dict
        '00000000-0000-4000-a000-000000000007', -- tuple
        '00000000-0000-4000-a000-000000000008', -- function
        '00000000-0000-4000-a000-000000000009', -- NoneType
        '00000000-0000-4000-a000-000000000010', -- bool
        '00000000-0000-4000-a000-000000000011', -- code
        '00000000-0000-4000-a000-000000000012', -- builtin_function_or_method
        '00000000-0000-4000-a000-000000000013'  -- method
    ];
    v_fixed_id uuid;
    v_current_base uuid;
    v_type_of_type uuid;
BEGIN
    -- 1. Unify Built-in Types: Force Base ID == Table ID
    -- This ensures that 'ob_type' fields (which hold Table IDs) become valid Base ID references.
    
    FOREACH v_fixed_id IN ARRAY IDS LOOP
         -- Get current Base ID for this type (e.g., random UUID)
         SELECT ob_base INTO v_current_base 
         FROM public.py_type_object 
         WHERE id = v_fixed_id;
         
         -- If Base ID is different from Fixed ID, swap it
         IF v_current_base IS NOT NULL AND v_current_base != v_fixed_id THEN
            
            -- Get the type of this type (usually 'type' ID ...002)
            SELECT ob_type INTO v_type_of_type 
            FROM public.py_object 
            WHERE id = v_current_base;
            
            -- If the type matches the old base, it means it's self-referential (type is type).
            -- We should map it to the new fixed ID if we are processing it.
            IF v_type_of_type = v_current_base THEN
                v_type_of_type := v_fixed_id;
            END IF;

            -- 1.1 Create NEW PyObject at the Fixed ID location
            -- Note: We temporarily allow constraints to be potentially invalid until we fix referencing rows
            INSERT INTO public.py_object (id, ob_type) 
            VALUES (v_fixed_id, v_type_of_type);
            
            -- 1.2 Update py_type_object to point to the new Base ID
            UPDATE public.py_type_object 
            SET ob_base = v_fixed_id 
            WHERE id = v_fixed_id;
            
            -- 1.3 Update references in other tables
            -- Lists, Tuples, Sets (contents)
            UPDATE public.py_list_object SET ob_item = array_replace(ob_item, v_current_base, v_fixed_id);
            UPDATE public.py_tuple_object SET ob_item = array_replace(ob_item, v_current_base, v_fixed_id);
            UPDATE public.py_set_object SET ob_item = array_replace(ob_item, v_current_base, v_fixed_id);
            
            -- Dicts (Values and Keys)
            UPDATE public.py_dict_entry SET me_key = v_fixed_id WHERE me_key = v_current_base;
            UPDATE public.py_dict_entry SET me_value = v_fixed_id WHERE me_value = v_current_base;
            
            -- Bound Methods
            UPDATE public.py_bound_method_object SET im_self = v_fixed_id WHERE im_self = v_current_base;
            
            -- 1.4 Delete the old Base Object
            DELETE FROM public.py_object WHERE id = v_current_base;
            
         END IF;
    END LOOP;
END $$;


-- 2. Fix Schema Constraints (py_object.ob_type)

-- 2.1 Drop old constraint referencing py_type_object(id)
ALTER TABLE public.py_object DROP CONSTRAINT IF EXISTS fk_py_object_type;

-- 2.2 Add new constraint referencing py_object(id)
-- Note: Since we aligned Base IDs of types to their Table IDs, existing ob_type values (Table IDs) are now valid Base IDs.
ALTER TABLE public.py_object 
ADD CONSTRAINT fk_py_object_type 
FOREIGN KEY (ob_type) REFERENCES public.py_object(id);


-- 3. Fix py_type_object.tp_bases (Tuple of bases)

-- 3.1 Convert tp_bases data from Table ID to Base ID
UPDATE public.py_type_object t
SET tp_bases = tup.ob_base
FROM public.py_tuple_object tup
WHERE t.tp_bases = tup.id;

-- 3.2 Add Constraint (tp_bases must point to a specific object, ideally a tuple)
-- We reference py_object(id) generally.
ALTER TABLE public.py_type_object
ADD CONSTRAINT py_type_object_tp_bases_fkey
FOREIGN KEY (tp_bases) REFERENCES public.py_object(id);


-- 4. Fix VM Functions to use Base ID Lookups

-- 4.1 vm_lookup_in_type: use ob_base for lookup
CREATE OR REPLACE FUNCTION public.vm_lookup_in_type(type_id uuid, attr_name text)
RETURNS uuid AS $$
DECLARE
    v_dict_base uuid;
    v_value_id uuid;
    ID_OBJ_TYPE uuid := '00000000-0000-4000-a000-000000000001';
BEGIN
    -- 1. Look in current Type's tp_dict (Base ID of dict)
    -- Lookup by 'ob_base' because 'type_id' is now a Base ID.
    SELECT tp_dict INTO v_dict_base
    FROM public.py_type_object
    WHERE ob_base = type_id;

    -- Search in dict by string key
    SELECT e.me_value
    INTO v_value_id
    FROM public.py_dict_entry e
    JOIN public.py_unicode_object u ON u.ob_base = e.me_key
    WHERE e.dict_id = v_dict_base
      AND u.str_value = attr_name
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

-- 4.2 vm_get_type: No change needed logic-wise, but good to refresh comments
-- It returns ob_type, which is now verified to be a Base ID.
CREATE OR REPLACE FUNCTION public.vm_get_type(obj_id uuid)
RETURNS uuid AS $$
DECLARE
    v_type uuid;
BEGIN
    SELECT ob_type INTO v_type FROM public.py_object WHERE id = obj_id;
    RETURN v_type;
END;
$$ LANGUAGE plpgsql;

