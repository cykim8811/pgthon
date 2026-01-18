-- =====================================================
-- Migration: Frame Object
-- Description: Create py_frame_object table and frame type
-- =====================================================

-------------------------------------------------------
-- 1. Create Frame Type
-------------------------------------------------------
DO $$
DECLARE
    ID_FRAME_TYPE uuid := '00000000-0000-4000-a000-000000000014';
    ID_TYPE_TYPE uuid := '00000000-0000-4000-a000-000000000002';
    ID_OBJ_TYPE uuid := '00000000-0000-4000-a000-000000000001';
    
    v_frame_type_base uuid := gen_random_uuid();
    v_type_base uuid;
BEGIN
    -- Create base object for frame type
    INSERT INTO public.py_object (id, ob_type) 
    VALUES (v_frame_type_base, ID_TYPE_TYPE);
    
    -- Create frame type
    INSERT INTO public.py_type_object (id, ob_base, tp_name, tp_bases, tp_dict)
    VALUES (ID_FRAME_TYPE, v_frame_type_base, 'frame', NULL, NULL);
    
    RAISE NOTICE 'Frame type created with ID: %', ID_FRAME_TYPE;
END $$;

-------------------------------------------------------
-- 2. Create Frame Object Table
-------------------------------------------------------
CREATE TABLE public.py_frame_object (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ob_base uuid REFERENCES public.py_object(id) ON DELETE CASCADE UNIQUE NOT NULL,
    
    -- Frame Chain
    f_back uuid REFERENCES public.py_object(id),  -- Previous frame (can be NULL for top frame)
    
    -- Code and Namespaces
    f_code uuid REFERENCES public.py_object(id) NOT NULL,     -- Code object
    f_locals uuid REFERENCES public.py_object(id),            -- Local namespace
    f_globals uuid REFERENCES public.py_object(id),           -- Global namespace
    f_builtins uuid REFERENCES public.py_object(id),          -- Built-in namespace
    
    -- Execution State
    f_lasti integer DEFAULT 0,                                -- Last instruction index
    f_lineno integer DEFAULT 1,                               -- Current line number
    
    -- Metadata
    created_at timestamp DEFAULT now(),
    updated_at timestamp DEFAULT now()
);

-- Indexes for performance
CREATE INDEX idx_frame_f_back ON public.py_frame_object(f_back);
CREATE INDEX idx_frame_f_code ON public.py_frame_object(f_code);
CREATE INDEX idx_frame_ob_base ON public.py_frame_object(ob_base);

-- Comments
COMMENT ON TABLE public.py_frame_object IS 'Python frame objects (execution contexts)';
COMMENT ON COLUMN public.py_frame_object.f_back IS 'Previous frame in call stack (NULL for top)';
COMMENT ON COLUMN public.py_frame_object.f_lasti IS 'Index of last executed instruction';
