-- Migration: VM Implementation Step 3 (Schema Schema Update, Int Ops & Interpreter Base)
-- Created at: 2026-01-17 00:00:03

DO $$
BEGIN
    -- 1. Alter py_code_object to match CPython structure
    -- co_consts: tuple of constants used in bytecode
    BEGIN
        ALTER TABLE public.py_code_object ADD COLUMN co_consts UUID REFERENCES public.py_object(id);
    EXCEPTION WHEN duplicate_column THEN NULL; END;

    -- co_names: tuple of names (global variables, attributes)
    BEGIN
        ALTER TABLE public.py_code_object ADD COLUMN co_names UUID REFERENCES public.py_object(id);
    EXCEPTION WHEN duplicate_column THEN NULL; END;

    -- co_varnames: tuple of local variable names (arguments first)
    BEGIN
        ALTER TABLE public.py_code_object ADD COLUMN co_varnames UUID REFERENCES public.py_object(id);
    EXCEPTION WHEN duplicate_column THEN NULL; END;

    -- REGISTER CODE TYPE (Missing Bootstrap)
    DECLARE
        ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
        ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
        ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
        
        ID_DICT_CODE UUID := gen_random_uuid();
        B_DICT_CODE  UUID := gen_random_uuid();
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM public.py_type_object WHERE id = ID_CODE_TYPE) THEN
            -- Create PyObject for Type
            INSERT INTO public.py_object (id, ob_type) VALUES (ID_CODE_TYPE, ID_OBJ_TYPE); -- Type's type is Type, but wait...
            -- Actually Type's type is Type (0002). But for simplicity here use Object or Type. 
            -- Let's use ID_OBJ_TYPE as placeholder or correct ID_TYP_TYPE if known.
            -- Using ID_OBJ_TYPE is safer if ID_TYP_TYPE is not declared in this block.
            -- Update: Let's fetch ID_TYP_TYPE or hardcode.
            -- 0002 is Type.
            UPDATE public.py_object SET ob_type = '00000000-0000-4000-a000-000000000002' WHERE id = ID_CODE_TYPE;
            
            -- Create Type Object
            INSERT INTO public.py_type_object (id, ob_base, tp_name, tp_bases, tp_dict)
            VALUES (ID_CODE_TYPE, ID_CODE_TYPE, 'code', NULL, ID_DICT_CODE);
            
            -- Create Dict for Type
            INSERT INTO public.py_object (id, ob_type) VALUES (B_DICT_CODE, ID_DCT_TYPE);
            INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (ID_DICT_CODE, B_DICT_CODE, 0);
        END IF;
    END;
END $$;


-------------------------------------------------------
-- 2. Helper: Int & List/Tuple Operations
-------------------------------------------------------

-- Create a new int object
CREATE OR REPLACE FUNCTION public.vm_create_int(p_val BIGINT)
RETURNS UUID AS $$
DECLARE
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    v_obj_id UUID;
    v_base_id UUID;
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

-- Get int value
CREATE OR REPLACE FUNCTION public.vm_get_int_value(p_obj_id UUID)
RETURNS BIGINT AS $$
DECLARE
    v_val BIGINT;
BEGIN
    SELECT long_value INTO v_val FROM public.py_long_object WHERE ob_base = p_obj_id;
    IF v_val IS NULL THEN
        RETURN 0; 
    END IF;
    RETURN v_val; 
END;
$$ LANGUAGE plpgsql;

-- Get Tuple Item (needed for LOAD_CONST)
CREATE OR REPLACE FUNCTION public.vm_tuple_getitem(p_tuple_id UUID, p_index INTEGER)
RETURNS UUID AS $$
DECLARE
    v_items UUID[];
BEGIN
    SELECT ob_item INTO v_items FROM public.py_tuple_object WHERE ob_base = p_tuple_id;
    
    -- Check bounds (1-based index in SQL, python bytecode uses 0-based)
    -- So we expect user to pass 0-based index, we convert to 1-based.
    IF p_index + 1 > array_length(v_items, 1) OR p_index < 0 THEN
        RAISE EXCEPTION 'IndexError: tuple index out of range';
    END IF;
    
    RETURN v_items[p_index + 1];
END;
$$ LANGUAGE plpgsql;


-------------------------------------------------------
-- 3. Update Native Dispatch for __add__
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_native_dispatch(fn_name TEXT, args UUID[])
RETURNS UUID AS $$
DECLARE
    v_self_id UUID;
    v_arg1 UUID;
    
    -- int vars
    v_i1 BIGINT;
    v_i2 BIGINT;
    v_res BIGINT;
BEGIN
    -- Switch-Case for Native Functions
    CASE fn_name
        -- [ list.append(self, item) ]
        WHEN 'append' THEN
            UPDATE public.py_list_object
            SET ob_item = array_append(ob_item, args[2])
            WHERE ob_base = args[1]; -- self
            
            RETURN public.vm_get_none();
            
        -- [ int.__add__(self, other) ]
        WHEN '__add__' THEN
            v_self_id := args[1];
            v_arg1 := args[2];
            
            -- Get Native Values (Assume both are ints for MVP)
            v_i1 := public.vm_get_int_value(v_self_id);
            v_i2 := public.vm_get_int_value(v_arg1);
            
            -- Add
            v_res := v_i1 + v_i2;
            
            -- Return new Int Object
            RETURN public.vm_create_int(v_res);

        ELSE
            RAISE EXCEPTION 'NotImplementedError: Native function % is not implemented yet.', fn_name;
    END CASE;
    
    RETURN public.vm_get_none();
END;
$$ LANGUAGE plpgsql;
