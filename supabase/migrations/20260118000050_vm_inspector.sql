-- Migration: VM Inspector (Step 11)
-- Unified Inspector API for Web UI
-- Created at: 2026-01-18 00:00:50

CREATE OR REPLACE FUNCTION public.vm_inspect_object(p_obj_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_type_id UUID;
    v_type_name TEXT;
    
    -- IDs
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYP_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_TUP_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    
    -- Values
    v_str_val TEXT;
    v_int_val BIGINT;
    v_list_items UUID[];
    v_json_items JSONB[];
    v_item_json JSONB;
    v_limit INTEGER := 10; -- Max items to show
    
BEGIN
    -- 1. Get Type Info
    v_type_id := public.vm_get_type(p_obj_id);
    
    -- Get Type Name
    SELECT tp_name INTO v_type_name 
    FROM public.py_type_object 
    WHERE ob_base = v_type_id;
    
    IF v_type_name IS NULL THEN v_type_name := 'unknown'; END IF;
    
    -- 2. Inspect based on type
    
    -- INT or BOOL
    IF v_type_id = ID_INT_TYPE OR v_type_name = 'bool' THEN
        SELECT long_value INTO v_int_val FROM public.py_long_object WHERE ob_base = p_obj_id;
        RETURN jsonb_build_object(
            'id', p_obj_id,
            'type', v_type_name,
            'value', v_int_val,
            'repr', v_int_val::TEXT
        );
    END IF;
    
    -- STRING
    IF v_type_id = ID_STR_TYPE THEN
        SELECT str_value INTO v_str_val FROM public.py_unicode_object WHERE ob_base = p_obj_id;
        RETURN jsonb_build_object(
            'id', p_obj_id,
            'type', v_type_name,
            'value', v_str_val,
            'repr', '"' || v_str_val || '"'
        );
    END IF;
    
    -- TUPLE (and subclasses)
    -- LIST (and subclasses) - Assuming list uses tuple-like storage for MVP or query needed
    IF v_type_name = 'tuple' OR v_type_name = 'list' THEN
        -- Get items from py_tuple_object (or py_list_object if implemented later)
        -- Currently list methods use py_tuple_object structure for MVP in some places or custom.
        -- Let's check py_tuple_object first.
        SELECT ob_item INTO v_list_items FROM public.py_tuple_object WHERE ob_base = p_obj_id;
        
        -- Build preview
        v_json_items := ARRAY[]::JSONB[];
        IF v_list_items IS NOT NULL AND array_length(v_list_items, 1) IS NOT NULL THEN
            FOR i IN 1..LEAST(array_length(v_list_items, 1), v_limit) LOOP
                -- Recursive call (lite version?) - For safety just ID and Type name
                -- To avoid recursion depth, let's just get type name of children
                DECLARE
                    child_id UUID := v_list_items[i];
                    child_type_id UUID;
                    child_type_name TEXT;
                    child_val TEXT;
                BEGIN
                     child_type_id := public.vm_get_type(child_id);
                     SELECT tp_name INTO child_type_name FROM public.py_type_object WHERE ob_base = child_type_id;
                     
                     -- Try simple value
                     IF child_type_name = 'int' THEN
                        SELECT long_value::TEXT INTO child_val FROM public.py_long_object WHERE ob_base = child_id;
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
                END;
            END LOOP;
        END IF;
        
        RETURN jsonb_build_object(
            'id', p_obj_id,
            'type', v_type_name,
            'length', coalesce(array_length(v_list_items, 1), 0),
            'children', to_jsonb(v_json_items)
        );
    END IF;
    
    -- LIST ITERATOR
    IF v_type_name = 'list_iterator' THEN
        DECLARE
            v_li_index INTEGER;
            v_li_list UUID;
        BEGIN
            SELECT li_index, li_list INTO v_li_index, v_li_list 
            FROM public.py_list_iterator_object WHERE ob_base = p_obj_id;
            
            RETURN jsonb_build_object(
                'id', p_obj_id,
                'type', v_type_name,
                'index', v_li_index,
                'list_id', v_li_list,
                'repr', '<list_iterator at ' || p_obj_id || '>'
            );
        END;
    END IF;
    
    -- Default
    RETURN jsonb_build_object(
        'id', p_obj_id,
        'type', v_type_name,
        'repr', '<' || v_type_name || ' object at ' || p_obj_id || '>'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
