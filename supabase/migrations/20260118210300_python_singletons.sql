-- =====================================================
-- Migration: Python Singletons
-- Description: Create None, True, False singleton objects
-- =====================================================

DO $$
DECLARE
    -- Type IDs
    ID_NONE_TYPE uuid := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE uuid := '00000000-0000-4000-a000-000000000010';
    
    -- Singleton Base Object IDs (Fixed UUIDs)
    B_NONE  uuid := '00000000-0000-4000-b000-000000000001';
    B_TRUE  uuid := '00000000-0000-4000-b000-000000000002';
    B_FALSE uuid := '00000000-0000-4000-b000-000000000003';
BEGIN
    -------------------------------------------------------
    -- 1. Create Base Objects with Fixed UUIDs
    -------------------------------------------------------
    INSERT INTO public.py_object (id, ob_type) VALUES 
    (B_NONE, ID_NONE_TYPE),
    (B_TRUE, ID_BOOL_TYPE),
    (B_FALSE, ID_BOOL_TYPE);

    -------------------------------------------------------
    -- 2. Create Singleton Data
    -------------------------------------------------------
    
    -- None: exists as py_object only (no additional data needed)
    -- The B_NONE object itself represents None
    
    -- True and False: bool inherits from int, so store in py_long_object
    -- The py_long_object.id can be random, ob_base points to the fixed py_object
    INSERT INTO public.py_long_object (id, ob_base, long_value) VALUES 
    (gen_random_uuid(), B_TRUE, 1),
    (gen_random_uuid(), B_FALSE, 0);

END $$;

