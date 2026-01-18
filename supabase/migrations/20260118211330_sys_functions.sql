-- =====================================================
-- Migration: sys Module Functions
-- Description: Python sys module functions for frame introspection
-- =====================================================

-------------------------------------------------------
-- 1. Execution Context Table (Thread-local simulation)
-------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.vm_execution_context (
    session_id text PRIMARY KEY DEFAULT current_setting('application_name', true),
    current_frame_id uuid REFERENCES public.py_object(id),
    updated_at timestamp DEFAULT now()
);

COMMENT ON TABLE public.vm_execution_context IS 'Simulates thread-local storage for current frame';

-------------------------------------------------------
-- 2. Context Management Functions
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_set_current_frame(p_frame_id uuid)
RETURNS void AS $$
BEGIN
    INSERT INTO public.vm_execution_context (session_id, current_frame_id, updated_at)
    VALUES (current_setting('application_name', true), p_frame_id, now())
    ON CONFLICT (session_id) 
    DO UPDATE SET current_frame_id = p_frame_id, updated_at = now();
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.vm_get_current_frame()
RETURNS uuid AS $$
DECLARE
    v_frame_id uuid;
BEGIN
    SELECT current_frame_id INTO v_frame_id
    FROM public.vm_execution_context
    WHERE session_id = current_setting('application_name', true);
    
    RETURN v_frame_id;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 3. sys._getframe(depth=0)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sys_getframe(p_depth integer DEFAULT 0)
RETURNS uuid AS $$
DECLARE
    v_frame_id uuid;
    i integer;
BEGIN
    -- Get current frame
    v_frame_id := vm_get_current_frame();
    
    IF v_frame_id IS NULL THEN
        RAISE EXCEPTION 'ValueError: no current frame';
    END IF;
    
    -- Walk back 'depth' frames
    FOR i IN 1..p_depth LOOP
        SELECT f_back INTO v_frame_id
        FROM public.py_frame_object
        WHERE ob_base = v_frame_id;
        
        IF v_frame_id IS NULL THEN
            RAISE EXCEPTION 'ValueError: call stack is not deep enough';
        END IF;
    END LOOP;
    
    RETURN v_frame_id;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- 4. Format Traceback
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_format_traceback(p_frame_id uuid)
RETURNS text AS $$
DECLARE
    v_frames jsonb[];
    v_frame jsonb;
    v_traceback text := E'Traceback (most recent call last):\n';
    v_code_name text;
    v_lineno integer;
BEGIN
    -- Get frame chain
    v_frames := vm_walk_frames(p_frame_id);
    
    IF array_length(v_frames, 1) IS NULL THEN
        RETURN 'Traceback: (empty call stack)';
    END IF;
    
    -- Format each frame
    FOR i IN 1..array_length(v_frames, 1) LOOP
        v_frame := v_frames[i];
        v_code_name := v_frame->>'code_name';
        v_lineno := (v_frame->>'f_lineno')::integer;
        
        v_traceback := v_traceback || format(
            '  Frame at line %s\n    in %s\n',
            v_lineno,
            COALESCE(v_code_name, '<unknown>')
        );
    END LOOP;
    
    RETURN v_traceback;
END;
$$ LANGUAGE plpgsql;
