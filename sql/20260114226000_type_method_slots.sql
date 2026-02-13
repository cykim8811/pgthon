-- ============================================================================
-- Migration: Type Method Slots (CPython Structure Fidelity)
-- Created: 2026-01-14 22:60:00
--
-- Purpose:
--   Implements CPython's method slot system with full structural fidelity.
--   This migration creates separate tables for PySequenceMethods and
--   PyMappingMethods structures, exactly matching CPython's pointer chain:
--   PyTypeObject->tp_as_sequence->sq_length
--   PyTypeObject->tp_as_mapping->mp_length
--
-- CPython Structure:
--   typedef struct {
--       lenfunc sq_length;
--       binaryfunc sq_concat;
--       ssizeargfunc sq_repeat;
--       ssizeargfunc sq_item;
--       // ... more sequence methods
--   } PySequenceMethods;
--
--   typedef struct {
--       lenfunc mp_length;
--       binaryfunc mp_subscript;
--       objobjargproc mp_ass_subscript;
--       // ... more mapping methods
--   } PyMappingMethods;
--
--   typedef struct _typeobject {
--       // ...
--       PySequenceMethods *tp_as_sequence;
--       PyMappingMethods *tp_as_mapping;
--       // ...
--   } PyTypeObject;
--
-- This migration:
--   1. Creates py_sequence_methods table (PySequenceMethods structure)
--   2. Creates py_mapping_methods table (PyMappingMethods structure)
--   3. Adds tp_as_sequence and tp_as_mapping fields to py_type_object
--   4. Implements type-specific length calculation functions
--   5. Implements PyObject_Size() with proper pointer chain traversal
--   6. Creates method objects and links them to builtin types
--
-- ============================================================================

-- ============================================================================
-- Schema: PySequenceMethods / PyMappingMethods
-- ============================================================================
-- Tables py_sequence_methods and py_mapping_methods are created in
-- 20260114220000_python_object_schema.sql. tp_as_sequence and tp_as_mapping
-- are defined there on py_type_object. This migration populates slots and
-- implements type-specific length and PyObject_Size.

-- Remove the old flattening fields if they exist (from previous implementation)
DO $$
BEGIN
    ALTER TABLE public.py_type_object DROP COLUMN IF EXISTS tp_as_sequence_sq_length;
    ALTER TABLE public.py_type_object DROP COLUMN IF EXISTS tp_as_mapping_mp_length;
EXCEPTION
    WHEN undefined_column THEN
        NULL;
END $$;

-- ============================================================================
-- Type-Specific Length Calculation Functions
-- ============================================================================

-- py_unicode_sq_length: Calculate length of a string object
-- Implements CPython's PyUnicode_GET_LENGTH() behavior
CREATE OR REPLACE FUNCTION public.py_unicode_sq_length(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    length_value NUMERIC;
BEGIN
    -- Validate object exists and is a string
    IF NOT EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_unicode_sq_length called on non-string object');
        RETURN NULL;
    END IF;
    
    -- Get string length
    SELECT char_length(str_value) INTO length_value
    FROM public.py_unicode_object
    WHERE ob_base = obj_id;
    
    IF length_value IS NULL THEN
        PERFORM public.py_err_set_type_error('object of type ''str'' has no len()');
        RETURN NULL;
    END IF;
    
    RETURN length_value;
END;
$$ LANGUAGE plpgsql;

-- py_list_sq_length: Calculate length of a list object
-- Implements CPython's PyList_GET_SIZE() behavior
CREATE OR REPLACE FUNCTION public.py_list_sq_length(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    length_value NUMERIC;
BEGIN
    -- Validate object exists and is a list
    IF NOT EXISTS (SELECT 1 FROM public.py_list_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_list_sq_length called on non-list object');
        RETURN NULL;
    END IF;
    
    -- Get list length (array_length returns NULL for empty arrays)
    SELECT array_length(ob_item, 1) INTO length_value
    FROM public.py_list_object
    WHERE ob_base = obj_id;
    
    -- PostgreSQL's array_length returns NULL for empty arrays, but length is 0
    IF length_value IS NULL THEN
        length_value := 0;
    END IF;
    
    RETURN length_value;
END;
$$ LANGUAGE plpgsql;

-- py_tuple_sq_length: Calculate length of a tuple object
-- Implements CPython's PyTuple_GET_SIZE() behavior
CREATE OR REPLACE FUNCTION public.py_tuple_sq_length(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    length_value NUMERIC;
BEGIN
    -- Validate object exists and is a tuple
    IF NOT EXISTS (SELECT 1 FROM public.py_tuple_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_tuple_sq_length called on non-tuple object');
        RETURN NULL;
    END IF;
    
    -- Get tuple length (array_length returns NULL for empty arrays)
    SELECT array_length(ob_item, 1) INTO length_value
    FROM public.py_tuple_object
    WHERE ob_base = obj_id;
    
    -- PostgreSQL's array_length returns NULL for empty arrays, but length is 0
    IF length_value IS NULL THEN
        length_value := 0;
    END IF;
    
    RETURN length_value;
END;
$$ LANGUAGE plpgsql;

-- py_bytes_sq_length: Calculate length of a bytes object
-- Implements CPython's PyBytes_GET_SIZE() behavior. Table existence only; no tp_name.
CREATE OR REPLACE FUNCTION public.py_bytes_sq_length(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    length_value NUMERIC;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_bytes_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_bytes_sq_length called on non-bytes object');
        RETURN NULL;
    END IF;
    SELECT length(bytes_value) INTO length_value
    FROM public.py_bytes_object
    WHERE ob_base = obj_id;
    IF length_value IS NULL THEN
        length_value := 0;
    END IF;
    RETURN length_value;
END;
$$ LANGUAGE plpgsql;

-- py_bytes_sq_concat: bytes + bytes (CPython sq_concat). left/right both bytes; else TypeError.
CREATE OR REPLACE FUNCTION public.py_bytes_sq_concat(left_id uuid, right_id uuid)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    lv bytea;
    rv bytea;
    id_bytes_type uuid := '00000000-0000-4000-a000-000000000012';
    right_type_id uuid;
    right_tp_name text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_bytes_object WHERE ob_base = left_id) THEN
        PERFORM public.py_err_set_type_error('py_bytes_sq_concat left operand is not bytes');
        RETURN NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.py_bytes_object WHERE ob_base = right_id) THEN
        SELECT ob_type INTO right_type_id FROM public.py_object WHERE id = right_id;
        SELECT tp_name INTO right_tp_name FROM public.py_type_object WHERE ob_base = right_type_id;
        PERFORM public.py_err_set_type_error('can only concatenate bytes (not "' || COALESCE(right_tp_name, 'None') || '") to bytes');
        RETURN NULL;
    END IF;
    SELECT bytes_value INTO lv FROM public.py_bytes_object WHERE ob_base = left_id;
    SELECT bytes_value INTO rv FROM public.py_bytes_object WHERE ob_base = right_id;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_bytes_type);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (result_id, lv || rv);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- py_bytes_sq_repeat: bytes * n (CPython sq_repeat). seq is bytes; n <= 0 → empty bytes.
CREATE OR REPLACE FUNCTION public.py_bytes_sq_repeat(seq_id uuid, n integer)
RETURNS uuid AS $$
DECLARE
    result_id uuid;
    bval bytea;
    repeated bytea;
    i integer;
    id_bytes_type uuid := '00000000-0000-4000-a000-000000000012';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.py_bytes_object WHERE ob_base = seq_id) THEN
        PERFORM public.py_err_set_type_error('py_bytes_sq_repeat operand is not bytes');
        RETURN NULL;
    END IF;
    SELECT bytes_value INTO bval FROM public.py_bytes_object WHERE ob_base = seq_id;
    IF n <= 0 THEN
        repeated := E'\\x'::bytea;
    ELSE
        repeated := E'\\x'::bytea;
        FOR i IN 1..n LOOP
            repeated := repeated || bval;
        END LOOP;
    END IF;
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, id_bytes_type);
    INSERT INTO public.py_bytes_object (ob_base, bytes_value) VALUES (result_id, repeated);
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- py_dict_mp_length: Calculate length of a dict object
-- Implements CPython's PyDict_GET_SIZE() behavior
CREATE OR REPLACE FUNCTION public.py_dict_mp_length(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    length_value NUMERIC;
BEGIN
    -- Validate object exists and is a dict
    IF NOT EXISTS (SELECT 1 FROM public.py_dict_object WHERE ob_base = obj_id) THEN
        PERFORM public.py_err_set_type_error('py_dict_mp_length called on non-dict object');
        RETURN NULL;
    END IF;
    
    -- Count dictionary entries
    SELECT COUNT(*) INTO length_value
    FROM public.py_dict_entry
    WHERE dict_id = obj_id;
    
    RETURN length_value;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PyObject_Size Helper Function (CPython Structure Fidelity)
-- ============================================================================

-- py_object_size: Get the size/length of a Python object
-- Implements CPython's PyObject_Size() function with exact structural fidelity
--
-- CPython Implementation (Objects/abstract.c):
--   Py_ssize_t PyObject_Size(PyObject *o) {
--       PySequenceMethods *m = Py_TYPE(o)->tp_as_sequence;
--       if (m && m->sq_length) {
--           return m->sq_length(o);
--       }
--       return PyMapping_Size(o);
--   }
--
--   Py_ssize_t PyMapping_Size(PyObject *o) {
--       PyMappingMethods *m = Py_TYPE(o)->tp_as_mapping;
--       if (m && m->mp_length) {
--           return m->mp_length(o);
--       }
--       // error handling...
--   }
--
-- This function follows the exact same pointer chain traversal:
--   1. Get type object: Py_TYPE(o) -> py_object.ob_type
--   2. Check tp_as_sequence pointer: type->tp_as_sequence
--   3. If not NULL, check sq_length: sequence_methods->sq_length
--   4. If NULL, check tp_as_mapping pointer: type->tp_as_mapping
--   5. If not NULL, check mp_length: mapping_methods->mp_length
CREATE OR REPLACE FUNCTION public.py_object_size(obj_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    obj_type_id UUID;
    sequence_methods_id UUID;
    mapping_methods_id UUID;
    sq_length_func regproc;
    mp_length_func regproc;
    length_value NUMERIC;
    type_name TEXT;
BEGIN
    -- Get object type (Py_TYPE(o) in CPython)
    SELECT ob_type INTO obj_type_id
    FROM public.py_object
    WHERE id = obj_id;
    
    IF obj_type_id IS NULL THEN
        PERFORM public.py_err_set_type_error('object of type ''NoneType'' has no len()');
        RETURN NULL;
    END IF;
    
    -- Step 1: Check tp_as_sequence pointer (CPython: Py_TYPE(o)->tp_as_sequence)
    -- This matches CPython's exact behavior: check sequence slot first
    SELECT tp_as_sequence INTO sequence_methods_id
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;
    
    -- Step 2: If tp_as_sequence is not NULL, check sq_length
    -- (CPython: m && m->sq_length)
    IF sequence_methods_id IS NOT NULL THEN
        SELECT sq_length INTO sq_length_func
        FROM public.py_sequence_methods
        WHERE id = sequence_methods_id;
        
        -- Step 3: If sq_length is not NULL, call it
        -- (CPython: m->sq_length(o))
        IF sq_length_func IS NOT NULL THEN
            EXECUTE format('SELECT %I($1)', sq_length_func) USING obj_id INTO length_value;
            IF length_value IS NULL AND public.py_err_occurred() THEN RETURN NULL; END IF;
            RETURN length_value;
        END IF;
    END IF;
    
    -- Step 4: Fallback to mapping slot (CPython: PyMapping_Size(o))
    -- Check tp_as_mapping pointer (CPython: Py_TYPE(o)->tp_as_mapping)
    SELECT tp_as_mapping INTO mapping_methods_id
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;
    
    -- Step 5: If tp_as_mapping is not NULL, check mp_length
    -- (CPython: m && m->mp_length)
    IF mapping_methods_id IS NOT NULL THEN
        SELECT mp_length INTO mp_length_func
        FROM public.py_mapping_methods
        WHERE id = mapping_methods_id;
        
        -- Step 6: If mp_length is not NULL, call it
        -- (CPython: m->mp_length(o))
        IF mp_length_func IS NOT NULL THEN
            EXECUTE format('SELECT %I($1)', mp_length_func) USING obj_id INTO length_value;
            IF length_value IS NULL AND public.py_err_occurred() THEN RETURN NULL; END IF;
            RETURN length_value;
        END IF;
    END IF;
    
    -- No length method available - get type name for error message
    SELECT tp_name INTO type_name
    FROM public.py_type_object
    WHERE ob_base = obj_type_id;
    
    IF type_name IS NULL THEN
        type_name := 'unknown';
    END IF;
    
    PERFORM public.py_err_set_type_error('object of type ''' || type_name || ''' has no len()');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Create Method Objects and Link to Builtin Types
-- ============================================================================

DO $$
DECLARE
    -- Builtin type IDs (from bootstrap)
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_LIST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE UUID := '00000000-0000-4000-a000-000000000007';
    ID_BYTES_TYPE UUID := '00000000-0000-4000-a000-000000000012';
    
    -- Method objects IDs
    ID_STR_SEQUENCE_METHODS UUID := gen_random_uuid();
    ID_LIST_SEQUENCE_METHODS UUID := gen_random_uuid();
    ID_TUPLE_SEQUENCE_METHODS UUID := gen_random_uuid();
    ID_BYTES_SEQUENCE_METHODS UUID := gen_random_uuid();
    ID_DICT_MAPPING_METHODS UUID := gen_random_uuid();
BEGIN
    -- Create sequence methods object for str type
    -- This represents PyUnicode_Type.tp_as_sequence in CPython
    INSERT INTO public.py_sequence_methods (id, sq_length)
    VALUES (ID_STR_SEQUENCE_METHODS, 'py_unicode_sq_length'::regproc);
    
    -- Link str type to its sequence methods
    -- This sets PyUnicode_Type.tp_as_sequence = &str_sequence_methods
    UPDATE public.py_type_object 
    SET tp_as_sequence = ID_STR_SEQUENCE_METHODS
    WHERE ob_base = ID_STR_TYPE;
    
    -- Create sequence methods object for list type
    -- This represents PyList_Type.tp_as_sequence in CPython
    INSERT INTO public.py_sequence_methods (id, sq_length)
    VALUES (ID_LIST_SEQUENCE_METHODS, 'py_list_sq_length'::regproc);
    
    -- Link list type to its sequence methods
    UPDATE public.py_type_object 
    SET tp_as_sequence = ID_LIST_SEQUENCE_METHODS
    WHERE ob_base = ID_LIST_TYPE;
    
    -- Create sequence methods object for tuple type
    -- This represents PyTuple_Type.tp_as_sequence in CPython
    INSERT INTO public.py_sequence_methods (id, sq_length)
    VALUES (ID_TUPLE_SEQUENCE_METHODS, 'py_tuple_sq_length'::regproc);
    
    -- Link tuple type to its sequence methods
    UPDATE public.py_type_object 
    SET tp_as_sequence = ID_TUPLE_SEQUENCE_METHODS
    WHERE ob_base = ID_TUPLE_TYPE;
    
    -- Create sequence methods object for bytes type (sq_length, sq_concat, sq_repeat)
    INSERT INTO public.py_sequence_methods (id, sq_length, sq_concat, sq_repeat)
    VALUES (ID_BYTES_SEQUENCE_METHODS, 'py_bytes_sq_length'::regproc, 'py_bytes_sq_concat'::regproc, 'py_bytes_sq_repeat'::regproc);
    
    UPDATE public.py_type_object 
    SET tp_as_sequence = ID_BYTES_SEQUENCE_METHODS
    WHERE ob_base = ID_BYTES_TYPE;
    
    -- Create mapping methods object for dict type
    -- This represents PyDict_Type.tp_as_mapping in CPython
    INSERT INTO public.py_mapping_methods (id, mp_length)
    VALUES (ID_DICT_MAPPING_METHODS, 'py_dict_mp_length'::regproc);
    
    -- Link dict type to its mapping methods
    UPDATE public.py_type_object 
    SET tp_as_mapping = ID_DICT_MAPPING_METHODS
    WHERE ob_base = ID_DICT_TYPE;
END $$;
