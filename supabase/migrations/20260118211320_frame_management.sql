-- =====================================================
-- Migration: Frame Management Functions
-- Description: Functions to create, update, and query frames
-- =====================================================

-------------------------------------------------------
-- 1. vm_create_frame: Create a new frame object
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_create_frame(
    p_code_id uuid,
    p_locals_id uuid,
    p_globals_id uuid,
    p_builtins_id uuid DEFAULT NULL,
    p_back_frame_id uuid DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
    ID_FRAME_TYPE uuid := '00000000-0000-4000-a000-000000000014';
    ID_B_BUILTINS uuid := '00000000-0000-4000-c000-000000000001';
    
    v_frame_base_id uuid := gen_random_uuid();
    v_frame_id uuid;
    v_effective_builtins uuid;
BEGIN
    -- Use default builtins if not provided
    v_effective_builtins := COALESCE(p_builtins_id, ID_B_BUILTINS);
    
    -- 1. Create base py_object
    INSERT INTO public.py_object (id, ob_type)
    VALUES (v_frame_base_id, ID_FRAME_TYPE);
    
    -- 2. Create frame object
    INSERT INTO public.py_frame_object (
        id, ob_base, f_back, f_code, f_locals, f_globals, f_builtins, f_lasti, f_lineno
    ) VALUES (
        gen_random_uuid(),
        v_frame_base_id,
        p_back_frame_id,
        p_code_id,
        p_locals_id,
        p_globals_id,
        v_effective_builtins,
        0,
        1
    )
    RETURNING id INTO v_frame_id;
    
    RETURN v_frame_base_id;  -- Return the ob_base (frame's py_object id)
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 2. vm_update_frame: Update frame execution state
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_update_frame(
    p_frame_id uuid,
    p_lasti integer,
    p_lineno integer DEFAULT NULL
)
RETURNS void AS $$
BEGIN
    UPDATE public.py_frame_object
    SET 
        f_lasti = p_lasti,
        f_lineno = COALESCE(p_lineno, f_lineno),
        updated_at = now()
    WHERE ob_base = p_frame_id;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 3. vm_get_frame_info: Get frame information
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_get_frame_info(p_frame_id uuid)
RETURNS jsonb AS $$
DECLARE
    v_frame record;
    v_code_name text;
BEGIN
    -- Get frame data
    SELECT 
        f.f_back,
        f.f_code,
        f.f_locals,
        f.f_globals,
        f.f_lasti,
        f.f_lineno
    INTO v_frame
    FROM public.py_frame_object f
    WHERE f.ob_base = p_frame_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'error', 'Frame not found',
            'frame_id', p_frame_id
        );
    END IF;
    
    -- Get code name
    SELECT co_name INTO v_code_name
    FROM public.py_code_object
    WHERE ob_base = v_frame.f_code;
    
    RETURN jsonb_build_object(
        'frame_id', p_frame_id,
        'f_back', v_frame.f_back,
        'f_code', v_frame.f_code,
        'f_locals', v_frame.f_locals,
        'f_globals', v_frame.f_globals,
        'f_lasti', v_frame.f_lasti,
        'f_lineno', v_frame.f_lineno,
        'code_name', COALESCE(v_code_name, '<unknown>')
    );
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 4. vm_walk_frames: Get frame chain
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_walk_frames(p_frame_id uuid, p_max_depth integer DEFAULT 10)
RETURNS jsonb[] AS $$
DECLARE
    v_frames jsonb[] := ARRAY[]::jsonb[];
    v_current_frame uuid := p_frame_id;
    v_depth integer := 0;
    v_frame_info jsonb;
BEGIN
    WHILE v_current_frame IS NOT NULL AND v_depth < p_max_depth LOOP
        -- Get frame info
        v_frame_info := vm_get_frame_info(v_current_frame);
        v_frames := array_append(v_frames, v_frame_info);
        
        -- Move to previous frame
        SELECT f_back INTO v_current_frame
        FROM public.py_frame_object
        WHERE ob_base = v_current_frame;
        
        v_depth := v_depth + 1;
    END LOOP;
    
    RETURN v_frames;
END;
$$ LANGUAGE plpgsql;
