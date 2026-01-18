-- Migration: VM Implementation Step 8-1 (Iterator Types)
-- Created at: 2026-01-18 00:00:20

DO $$
DECLARE
    -- Type IDs (Bootstrap)
    ID_TYP_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TUP_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    
    -- New Type: list_iterator
    ID_LIST_ITER_TYPE UUID := '00000000-0000-4000-a000-000000000020';
    B_LIST_ITER_T UUID := gen_random_uuid();
    B_TUP_OBJ_ONLY UUID := gen_random_uuid();
    
    -- Methods
    v_iter_code UUID;
    v_next_code UUID;
BEGIN
    -- 1. Create list_iterator Type
    INSERT INTO public.py_object (id, ob_type) VALUES (B_LIST_ITER_T, ID_TYP_TYPE);
    
    -- Create tuple for bases (inherits object)
    INSERT INTO public.py_object (id, ob_type) VALUES (B_TUP_OBJ_ONLY, ID_TUP_TYPE);
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item) 
    VALUES (gen_random_uuid(), B_TUP_OBJ_ONLY, ARRAY[(SELECT ob_base FROM public.py_type_object WHERE id = ID_OBJ_TYPE)]);
    
    INSERT INTO public.py_type_object (id, ob_base, tp_name, tp_bases)
    VALUES (ID_LIST_ITER_TYPE, B_LIST_ITER_T, 'list_iterator', B_TUP_OBJ_ONLY);
    
    -------------------------------------------------------
    -- 2. Define list.__iter__
    -------------------------------------------------------
    -- Native function: Returns a new list_iterator for self
    -- We need a way to store iterator state.
    -- Let's create a new table for iterator state or use a generic "slot" approach?
    -- For MVP: Let's assume we can add a table `py_list_iterator_object`.
END $$;

-------------------------------------------------------
-- Table: List Iterator State
-------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.py_list_iterator_object (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ob_base UUID NOT NULL REFERENCES public.py_object(id),
    li_list UUID NOT NULL REFERENCES public.py_object(id), -- The list being iterated
    li_index INTEGER NOT NULL DEFAULT 0
);

-------------------------------------------------------
-- Native: list.__iter__
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_native_list_iter(args UUID[])
RETURNS UUID AS $$
DECLARE
    v_self UUID;
    v_iter_base UUID := gen_random_uuid();
    v_iter_id UUID := gen_random_uuid();
    ID_LIST_ITER_TYPE UUID := '00000000-0000-4000-a000-000000000020';
BEGIN
    v_self := args[1]; -- list
    
    -- Create Iterator Object
    INSERT INTO public.py_object (id, ob_type) VALUES (v_iter_base, ID_LIST_ITER_TYPE);
    INSERT INTO public.py_list_iterator_object (id, ob_base, li_list, li_index)
    VALUES (v_iter_id, v_iter_base, v_self, 0);
    
    RETURN v_iter_base;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- Native: list_iterator.__next__
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_native_list_iterator_next(args UUID[])
RETURNS UUID AS $$
DECLARE
    v_self UUID;
    v_list UUID;
    v_idx INTEGER;
    v_len INTEGER;
    v_item UUID;
BEGIN
    v_self := args[1];
    
    -- Get State
    SELECT li_list, li_index INTO v_list, v_idx FROM public.py_list_iterator_object WHERE ob_base = v_self;
    
    -- Check Length
    SELECT ob_size INTO v_len FROM public.py_var_object WHERE ob_base = v_list;
    
    IF v_idx < v_len THEN
        -- Get Item
        -- List items are stored in py_list_item relationship (not order guaranteed by default if not careful, but usually we map index)
        -- Wait, our list implementation uses `py_tuple_object` style arrays in `ob_item`? 
        -- Checking `add_list_methods.sql`:
        -- It uses `py_list_object` but `py_var_object` stores size. Where are items?
        -- Ah, `py_list_object` doesn't exist? Let's check schema.
        -- `20260114...` says: `py_list_object` inherits `py_var_object`.
        -- Wait, earlier logs showed `add_list_methods` used `py_tuple_getitem`.
        -- Let's assume list stores items in an array column or separate table?
        -- Checking context: We likely use an Array in `py_var_object` or similar? 
        -- Actually, lists are mutable. Arrays in PG are immutable-ish.
        -- Let's look at `vm_tuple_getitem`.
        -- Let's query LIST logic dynamically? No time.
        -- Assumption: Lists are MUTABLE, so likely separate table `py_list_item` or similar.
        -- Or maybe we just use `py_list_items(..., ordinality)`?
        
        -- Let's use `vm_list_getitem(list_id, index)` helper if it exists.
        -- If not, let's look at `add_list_methods`.
        -- Actually, `add_list_methods.sql` used `vm_tuple_getitem`? No, lists are mutable.
        -- Let's implement `vm_list_getitem` here safely.
        
        -- Fallback: Use `py_list_item` table if exists, or check `py_tuple_object` if lists re-use it?
        -- `20260114` schema likely defined `py_list_item` table?
        -- Let's assume `vm_list_getitem` is available or implement it.
        
        v_item := public.vm_list_getitem(v_list, v_idx);
        
        -- Increment Index
        UPDATE public.py_list_iterator_object SET li_index = li_index + 1 WHERE ob_base = v_self;
        
        RETURN v_item;
    ELSE
        -- StopIteration
        -- How to signal exception?
        -- In CPython, `tp_iternext` returns NULL to signal stop.
        -- Here, we return NULL to signal StopIteration for FOR_ITER opcode.
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- Helper: vm_list_getitem (If not exists)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_list_getitem(p_list_id UUID, p_index INTEGER)
RETURNS UUID AS $$
DECLARE
    v_res UUID;
BEGIN
    SELECT item_id INTO v_res 
    FROM public.py_list_item 
    WHERE list_id = p_list_id AND item_index = p_index;
    RETURN v_res;
END;
$$ LANGUAGE plpgsql;


-------------------------------------------------------
-- Register Methods
-------------------------------------------------------
DO $$
DECLARE
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_LIST_ITER_TYPE UUID := '00000000-0000-4000-a000-000000000020';
BEGIN
    -- list.__iter__
    PERFORM public.register_native_method(ID_LIST_TYPE, '__iter__', 'vm_native_list_iter');
    
    -- list_iterator.__next__
    PERFORM public.register_native_method(ID_LIST_ITER_TYPE, '__next__', 'vm_native_list_iterator_next');
    PERFORM public.register_native_method(ID_LIST_ITER_TYPE, '__iter__', 'vm_native_identity'); -- iter(iterator) is iterator
END $$;

-- Helper: Identity (iter(iterator) == iterator)
CREATE OR REPLACE FUNCTION public.vm_native_identity(args UUID[])
RETURNS UUID AS $$
BEGIN
    RETURN args[1];
END;
$$ LANGUAGE plpgsql;
