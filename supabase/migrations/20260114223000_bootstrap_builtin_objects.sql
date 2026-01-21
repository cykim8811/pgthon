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

    -- Singletons
    ID_NONE_OBJ   UUID := '00000000-0000-4000-b000-000000000001';

    -- Helper Objects (Tuples for tp_bases)
    ID_TUPLE_OBJECT_ONLY UUID := gen_random_uuid();
BEGIN
    -------------------------------------------------------
    -- 1. Create base PyObjects first (without ob_type)
    --    NOTE: In Elytra, every object's identity is PyObject.id.
    -------------------------------------------------------
    INSERT INTO public."PyObject" (id, ob_type) VALUES 
    (ID_OBJECT_TYPE, NULL), 
    (ID_TYPE_TYPE,   NULL),
    (ID_STR_TYPE,    NULL),
    (ID_INT_TYPE,    NULL),
    (ID_LIST_TYPE,   NULL),
    (ID_DICT_TYPE,   NULL),
    (ID_TUPLE_TYPE,  NULL),
    (ID_NONE_TYPE,   NULL),
    (ID_NONE_OBJ,    NULL),
    (ID_TUPLE_OBJECT_ONLY, NULL);

    -------------------------------------------------------
    -- 2. Create Core PyTypeObjects
    --    NOTE: Shared-PK inheritance: PyTypeObject.ob_base == PyObject.id
    -------------------------------------------------------
    INSERT INTO public."PyTypeObject" (ob_base, tp_name) VALUES
    (ID_OBJECT_TYPE, 'object'),
    (ID_TYPE_TYPE,   'type'),
    (ID_STR_TYPE,    'str'),
    (ID_INT_TYPE,    'int'),
    (ID_LIST_TYPE,   'list'),
    (ID_DICT_TYPE,   'dict'),
    (ID_TUPLE_TYPE,  'tuple'),
    (ID_NONE_TYPE,   'NoneType');

    -------------------------------------------------------
    -- 3. Update PyObjects to point to their types (Circular Reference Fix)
    -------------------------------------------------------
    -- All types have 'type' as their ob_type
    UPDATE public."PyObject" SET ob_type = ID_TYPE_TYPE 
    WHERE id IN (ID_OBJECT_TYPE, ID_TYPE_TYPE, ID_STR_TYPE, ID_INT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE);
    
    -- None instance is a NoneType
    UPDATE public."PyObject" SET ob_type = ID_NONE_TYPE WHERE id = ID_NONE_OBJ;

    -------------------------------------------------------
    -- 4. Create Helper Objects (Empty bases or object bases)
    -------------------------------------------------------
    -- Tuple containing only 'object' type for tp_bases
    -- NOTE: PyTupleObject.ob_base == PyObject.id
    INSERT INTO public."PyTupleObject" (ob_base, ob_item)
    VALUES (ID_TUPLE_OBJECT_ONLY, ARRAY[ID_OBJECT_TYPE]);

    -------------------------------------------------------
    -- 5. Set tp_bases and singletons
    -------------------------------------------------------
    -- object has no base class
    -- type inherit from object
    UPDATE public."PyTypeObject" SET tp_bases = ID_TUPLE_OBJECT_ONLY WHERE ob_base = ID_TYPE_TYPE;
    UPDATE public."PyTypeObject" SET tp_bases = ID_TUPLE_OBJECT_ONLY WHERE ob_base IN (ID_STR_TYPE, ID_INT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE);

    -- Create None Instance in its own table if needed
    -- For now, PyObject entry is enough to represent existence, but let's add a PyInstanceObject placeholder
    INSERT INTO public."PyInstanceObject" (ob_base, in_dict)
    VALUES (ID_NONE_OBJ, NULL);

END $$;
