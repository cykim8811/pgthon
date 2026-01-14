-- Migration: Bootstrap Core Python Objects (type, object, etc.)
-- Created at: 2026-01-14 22:30:00

DO $$
DECLARE
    -- Core IDs
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYPE_TYPE   UUID := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE    UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE   UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_NONE_TYPE   UUID := '00000000-0000-4000-a000-000000000008';

    -- Base PyObject IDs (matching the type object's ob_base)
    BASE_OBJECT UUID := gen_random_uuid();
    BASE_TYPE   UUID := gen_random_uuid();
    BASE_STR    UUID := gen_random_uuid();
    BASE_INT    UUID := gen_random_uuid();
    BASE_LIST   UUID := gen_random_uuid();
    BASE_DICT   UUID := gen_random_uuid();
    BASE_TUPLE  UUID := gen_random_uuid();
    BASE_NONE_T UUID := gen_random_uuid();

    -- Singletons
    ID_NONE_OBJ   UUID := '00000000-0000-4000-b000-000000000001';
    BASE_NONE_OBJ UUID := gen_random_uuid();

    -- Helper Objects (Tuples for tp_bases)
    ID_TUPLE_OBJECT_ONLY UUID := gen_random_uuid();
    BASE_TUPLE_OBJECT_ONLY UUID := gen_random_uuid();
BEGIN
    -------------------------------------------------------
    -- 1. Create Base PyObjects first (without ob_type)
    -------------------------------------------------------
    INSERT INTO public."PyObject" (id, ob_type) VALUES 
    (BASE_OBJECT, NULL), 
    (BASE_TYPE,   NULL),
    (BASE_STR,    NULL),
    (BASE_INT,    NULL),
    (BASE_LIST,   NULL),
    (BASE_DICT,   NULL),
    (BASE_TUPLE,  NULL),
    (BASE_NONE_T, NULL),
    (BASE_NONE_OBJ, NULL),
    (BASE_TUPLE_OBJECT_ONLY, NULL);

    -------------------------------------------------------
    -- 2. Create Core PyTypeObjects
    -------------------------------------------------------
    INSERT INTO public."PyTypeObject" (id, ob_base, tp_name) VALUES
    (ID_OBJECT_TYPE, BASE_OBJECT, 'object'),
    (ID_TYPE_TYPE,   BASE_TYPE,   'type'),
    (ID_STR_TYPE,    BASE_STR,    'str'),
    (ID_INT_TYPE,    BASE_INT,    'int'),
    (ID_LIST_TYPE,   BASE_LIST,   'list'),
    (ID_DICT_TYPE,   BASE_DICT,   'dict'),
    (ID_TUPLE_TYPE,  BASE_TUPLE,  'tuple'),
    (ID_NONE_TYPE,   BASE_NONE_T, 'NoneType');

    -------------------------------------------------------
    -- 3. Update PyObjects to point to their types (Circular Reference Fix)
    -------------------------------------------------------
    -- All types have 'type' as their ob_type
    UPDATE public."PyObject" SET ob_type = ID_TYPE_TYPE 
    WHERE id IN (BASE_OBJECT, BASE_TYPE, BASE_STR, BASE_INT, BASE_LIST, BASE_DICT, BASE_TUPLE, BASE_NONE_T, BASE_TUPLE_OBJECT_ONLY);
    
    -- None instance is a NoneType
    UPDATE public."PyObject" SET ob_type = ID_NONE_TYPE WHERE id = BASE_NONE_OBJ;

    -------------------------------------------------------
    -- 4. Create Helper Objects (Empty bases or object bases)
    -------------------------------------------------------
    -- Tuple containing only 'object' type for tp_bases
    INSERT INTO public."PyTupleObject" (id, ob_base, ob_item)
    VALUES (ID_TUPLE_OBJECT_ONLY, BASE_TUPLE_OBJECT_ONLY, ARRAY[BASE_OBJECT]);

    -------------------------------------------------------
    -- 5. Set tp_bases and singletons
    -------------------------------------------------------
    -- object has no base class
    -- type inherit from object
    UPDATE public."PyTypeObject" SET tp_bases = ID_TUPLE_OBJECT_ONLY WHERE id = ID_TYPE_TYPE;
    UPDATE public."PyTypeObject" SET tp_bases = ID_TUPLE_OBJECT_ONLY WHERE id IN (ID_STR_TYPE, ID_INT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE);

    -- Create None Instance in its own table if needed
    -- For now, PyObject entry is enough to represent existence, but let's add a PyInstanceObject placeholder
    INSERT INTO public."PyInstanceObject" (id, ob_base, in_dict)
    VALUES (ID_NONE_OBJ, BASE_NONE_OBJ, NULL);

END $$;
