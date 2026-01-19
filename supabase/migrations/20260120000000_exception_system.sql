-- =====================================================
-- Migration: Exception System Infrastructure
-- Description: Define Exception object table and register core Exception types
-- =====================================================

-------------------------------------------------------
-- 1. Exception Object Table
-------------------------------------------------------
-- Stores instances of exceptions (e.g., TypeError('msg'))
CREATE TABLE public.py_exception_object (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE,
    ex_args uuid REFERENCES public.py_object(id), -- Tuple of arguments (usually message)
    ex_traceback jsonb, -- Stored traceback information
    ex_cause uuid REFERENCES public.py_object(id), -- For 'raise ... from ...'
    ex_context uuid REFERENCES public.py_object(id), -- For chained exceptions
    created_at timestamp DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.py_exception_object ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public Read Access" ON public.py_exception_object FOR SELECT USING (true);
CREATE POLICY "Public Insert Access" ON public.py_exception_object FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Update Access" ON public.py_exception_object FOR UPDATE USING (true);
GRANT ALL ON public.py_exception_object TO anon, authenticated;

-------------------------------------------------------
-- 2. Register Exception Types and Add to __builtins__
-------------------------------------------------------
DO $$
DECLARE
    -- Core Object IDs (References)
    ID_TYP_TYPE uuid := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE uuid := '00000000-0000-4000-a000-000000000003';
    
    -- Builtin Dictionary Base ID
    ID_DT_BUILTINS uuid := '00000000-0000-4000-c000-000000000002'; -- The dict object ID (technically py_dict_object.id is used for entries)
    
    -- New Exception Type IDs (These will be py_type_object.id)
    ID_BASE_EXC    uuid := '00000000-0000-4000-e000-000000000001'; -- BaseException
    ID_EXC         uuid := '00000000-0000-4000-e000-000000000002'; -- Exception
    ID_TYPE_ERR    uuid := '00000000-0000-4000-e000-000000000003'; -- TypeError
    ID_VALUE_ERR   uuid := '00000000-0000-4000-e000-000000000004'; -- ValueError
    ID_NAME_ERR    uuid := '00000000-0000-4000-e000-000000000005'; -- NameError
    ID_INDEX_ERR   uuid := '00000000-0000-4000-e000-000000000006'; -- IndexError
    ID_KEY_ERR     uuid := '00000000-0000-4000-e000-000000000007'; -- KeyError
    ID_ATTR_ERR    uuid := '00000000-0000-4000-e000-000000000008'; -- AttributeError
    ID_ZERO_DIV    uuid := '00000000-0000-4000-e000-000000000009'; -- ZeroDivisionError
    
    -- Helper for registration
    v_type_record record;
    key_base uuid;
    key_obj uuid;
    v_base_id uuid; -- The py_object ID for the type instance
BEGIN
    -- Define types to create
    CREATE TEMP TABLE temp_exceptions (
        tid uuid,
        tname text
    ) ON COMMIT DROP;

    INSERT INTO temp_exceptions VALUES 
    (ID_BASE_EXC, 'BaseException'),
    (ID_EXC, 'Exception'),
    (ID_TYPE_ERR, 'TypeError'),
    (ID_VALUE_ERR, 'ValueError'),
    (ID_NAME_ERR, 'NameError'),
    (ID_INDEX_ERR, 'IndexError'),
    (ID_KEY_ERR, 'KeyError'),
    (ID_ATTR_ERR, 'AttributeError'),
    (ID_ZERO_DIV, 'ZeroDivisionError');

    FOR v_type_record IN SELECT * FROM temp_exceptions
    LOOP
        v_base_id := gen_random_uuid();
        
        -- 1. Create Type Object (Base object)
        -- This represents the 'class' object itself, which is an instance of 'type'
        INSERT INTO public.py_object (id, ob_type) 
        VALUES (v_base_id, ID_TYP_TYPE)
        ON CONFLICT (id) DO NOTHING;
        
        -- 2. Create py_type_object entry
        -- Linking the fixed Type ID to the Base ID
        INSERT INTO public.py_type_object (id, ob_base, tp_name)
        VALUES (v_type_record.tid, v_base_id, v_type_record.tname)
        ON CONFLICT (id) DO NOTHING;

        -- 3. Register to __builtins__
        -- Create String Key
        key_base := gen_random_uuid();
        key_obj := gen_random_uuid();
        
        INSERT INTO public.py_object (id, ob_type) VALUES (key_base, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) 
        VALUES (key_obj, key_base, v_type_record.tname);
        
        -- Insert into dict (__builtins__ maps name -> object id)
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value)
        VALUES (gen_random_uuid(), ID_DT_BUILTINS, key_base, v_base_id);
        
        -- Increment usage
        UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = ID_DT_BUILTINS;
        
    END LOOP;

END $$;
