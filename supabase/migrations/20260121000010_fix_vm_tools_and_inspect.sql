-- =====================================================
-- Migration: Fix VM Tools (Inspect & Execute) for Base ID
-- Description: Update helper functions to respect Base ID Unification
-- =====================================================

-------------------------------------------------------
-- vm_inspect_object: Fix type name lookup (use ob_base)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_inspect_object(p_obj_id uuid)
RETURNS jsonb AS $$
DECLARE
    v_type_id uuid;
    v_type_name text;
    
    -- Type IDs (Now these are Base IDs for built-ins)
    -- But strict lookup by type name via DB is safer
    
    -- Values
    v_str_val text;
    v_int_val bigint;
    v_list_items uuid[];
    v_json_items jsonb[];
    v_limit integer := 10; -- Max items to show in preview
    
    -- For iteration
    child_id uuid;
    child_type_id uuid;
    child_type_name text;
    child_val text;
    i integer;
BEGIN
    -- 1. Get type info (Base ID)
    v_type_id := public.vm_get_type(p_obj_id);
    
    -- Lookup Type Name using Base ID
    SELECT tp_name INTO v_type_name 
    FROM public.py_type_object 
    WHERE ob_base = v_type_id;
    
    IF v_type_name IS NULL THEN 
        v_type_name := 'unknown'; 
    END IF;
    
    -----------------------------------------------------------------
    -- 2. Inspect based on type
    -----------------------------------------------------------------
    
    -- INT or BOOL
    IF v_type_name IN ('int', 'bool') THEN
        SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = p_obj_id;
        RETURN jsonb_build_object(
            'id', p_obj_id,
            'type', v_type_name,
            'value', v_int_val,
            'repr', v_int_val::text
        );
    END IF;
    
    -- STRING
    IF v_type_name = 'str' THEN
        SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = p_obj_id;
        RETURN jsonb_build_object(
            'id', p_obj_id,
            'type', v_type_name,
            'value', v_str_val,
            'repr', '"' || v_str_val || '"'
        );
    END IF;
    
    -- TUPLE or LIST
    IF v_type_name IN ('tuple', 'list') THEN
        -- Get items (both use tuple storage for MVP)
        IF v_type_name = 'tuple' THEN
            SELECT ob_item INTO v_list_items FROM public.py_tuple_object WHERE ob_base = p_obj_id;
        ELSE
            SELECT ob_item INTO v_list_items FROM public.py_list_object WHERE ob_base = p_obj_id;
        END IF;
        
        -- Build preview of children
        v_json_items := ARRAY[]::jsonb[];
        IF v_list_items IS NOT NULL AND array_length(v_list_items, 1) IS NOT NULL THEN
            FOR i IN 1..LEAST(array_length(v_list_items, 1), v_limit) LOOP
                child_id := v_list_items[i];
                child_type_id := public.vm_get_type(child_id);
                
                SELECT tp_name INTO child_type_name 
                FROM public.py_type_object 
                WHERE ob_base = child_type_id;
                
                -- Try to get simple value for preview
                IF child_type_name = 'int' THEN
                    SELECT long_value::text INTO child_val FROM public.py_long_object WHERE ob_base = child_id;
                ELSIF child_type_name = 'str' THEN
                    SELECT str_value INTO child_val FROM public.py_unicode_object WHERE ob_base = child_id;
                ELSE
                    child_val := '...';
                END IF;
                
                v_json_items := array_append(v_json_items, jsonb_build_object(
                    'id', child_id,
                    'type', child_type_name,
                    'preview', child_val
                ));
            END LOOP;
        END IF;
        
        RETURN jsonb_build_object(
            'id', p_obj_id,
            'type', v_type_name,
            'length', COALESCE(array_length(v_list_items, 1), 0),
            'children', to_jsonb(v_json_items)
        );
    END IF;
    
    -- LIST ITERATOR
    IF v_type_name = 'list_iterator' THEN
        DECLARE
            v_li_index integer;
            v_li_list uuid;
        BEGIN
            SELECT li_index, li_list INTO v_li_index, v_li_list 
            FROM public.py_list_iterator_object 
            WHERE ob_base = p_obj_id;
            
            RETURN jsonb_build_object(
                'id', p_obj_id,
                'type', v_type_name,
                'index', v_li_index,
                'list_id', v_li_list,
                'repr', '<list_iterator at ' || p_obj_id || '>'
            );
        END;
    END IF;
    
    -- Default fallback
    RETURN jsonb_build_object(
        'id', p_obj_id,
        'type', v_type_name,
        'repr', '<' || v_type_name || ' object at ' || p_obj_id || '>'
    );
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------
-- vm_execute_source: Fix locals passing (use Base ID)
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vm_execute_source(p_source text)
RETURNS uuid AS $$
DECLARE
    v_code_id uuid;
    v_locals_id uuid;
    v_base_locals uuid := gen_random_uuid();
    v_res uuid;
    
    ID_DCT_TYPE uuid := '00000000-0000-4000-a000-000000000006';
BEGIN
    -- 1. Assemble source into code object
    v_code_id := public.vm_assemble(p_source, 'web_repl');
    
    -- 2. Create empty locals dictionary
    -- Create PyObject (Base)
    INSERT INTO public.py_object (id, ob_type) VALUES (v_base_locals, ID_DCT_TYPE);
    
    -- Create DictObject (Table)
    v_locals_id := gen_random_uuid();
    INSERT INTO public.py_dict_object (id, ob_base, ma_used) VALUES (v_locals_id, v_base_locals, 0);
    
    -- 3. Execute code
    -- IMPORTANT: vm_run_frame expects Base ID for locals
    v_res := public.vm_run_frame(v_code_id, v_base_locals, NULL);
    
    RETURN v_res;
END;
$$ LANGUAGE plpgsql;
