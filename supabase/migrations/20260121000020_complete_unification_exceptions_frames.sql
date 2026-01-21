-- =====================================================
-- Migration: Complete Base ID Unification (Part 2)
-- Description: Unify Frame Type and Exception Types to have Base ID == Table ID.
--              This ensures vm_create_frame and exception raising works correctly.
-- =====================================================

DO $$
DECLARE
    -- The list of fixed IDs for Frame and Exception Types
    IDS uuid[] := ARRAY[
        '00000000-0000-4000-a000-000000000014', -- frame
        
        -- Exceptions
        '00000000-0000-4000-e000-000000000001', -- BaseException
        '00000000-0000-4000-e000-000000000002', -- Exception
        '00000000-0000-4000-e000-000000000003', -- TypeError
        '00000000-0000-4000-e000-000000000004', -- ValueError
        '00000000-0000-4000-e000-000000000005', -- NameError
        '00000000-0000-4000-e000-000000000006', -- IndexError
        '00000000-0000-4000-e000-000000000007', -- KeyError
        '00000000-0000-4000-e000-000000000008', -- AttributeError
        '00000000-0000-4000-e000-000000000009'  -- ZeroDivisionError
    ];
    v_fixed_id uuid;
    v_current_base uuid;
    v_type_of_type uuid;
BEGIN
    FOREACH v_fixed_id IN ARRAY IDS LOOP
         -- Get current Base ID
         SELECT ob_base INTO v_current_base 
         FROM public.py_type_object 
         WHERE id = v_fixed_id;
         
         -- If Base ID is different from Fixed ID, swap it
         IF v_current_base IS NOT NULL AND v_current_base != v_fixed_id THEN
            
            -- Get "Type of Type" (usually 'type' ID ...002, which is already fixed)
            SELECT ob_type INTO v_type_of_type 
            FROM public.py_object 
            WHERE id = v_current_base;
            
            -- 1. Create NEW PyObject at the Fixed ID location
            INSERT INTO public.py_object (id, ob_type) 
            VALUES (v_fixed_id, v_type_of_type);
            
            -- 2. Update py_type_object to point to the new Base ID
            UPDATE public.py_type_object 
            SET ob_base = v_fixed_id 
            WHERE id = v_fixed_id;
            
            -- 3. Update references in other tables
            -- Lists, Tuples, Sets
            UPDATE public.py_list_object SET ob_item = array_replace(ob_item, v_current_base, v_fixed_id);
            UPDATE public.py_tuple_object SET ob_item = array_replace(ob_item, v_current_base, v_fixed_id);
            UPDATE public.py_set_object SET ob_item = array_replace(ob_item, v_current_base, v_fixed_id);
            
            -- Dictionary Entries (likely in __builtins__)
            UPDATE public.py_dict_entry SET me_key = v_fixed_id WHERE me_key = v_current_base;
            UPDATE public.py_dict_entry SET me_value = v_fixed_id WHERE me_value = v_current_base;
            
            -- Bound Methods
            UPDATE public.py_bound_method_object SET im_self = v_fixed_id WHERE im_self = v_current_base;
            
            -- Exception Fields (if any exception instances exist, unlikely but safe to check)
             -- None of the core tables reference 'cause' or 'context' by type yet, 
             -- except maybe as generic py_object references.
            
            -- 4. Delete the old Base Object
            DELETE FROM public.py_object WHERE id = v_current_base;
            
         END IF;
    END LOOP;
END $$;
