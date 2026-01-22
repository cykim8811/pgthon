-- ============================================================================
-- Migration: CPython Builtin Types Bootstrap
-- Created: 2026-01-14 22:30:00
--
-- Purpose:
--   Creates the initial "world" of CPython objects - the builtin types and
--   singletons that form the foundation of the Python object model.
--
--   This is analogous to CPython's runtime initialization, where global type
--   objects (PyType_Type, PyBaseObject_Type, etc.) and singletons (Py_None)
--   are created and wired together.
--
--   The bootstrap process handles the circular dependency between 'type' and
--   'object' by using a 2-phase approach:
--     1. Create PyObject rows with ob_type = NULL
--     2. Create PyTypeObject rows (extending those PyObjects)
--     3. Update PyObject.ob_type to point to the type objects
--
-- Builtin Types Created:
--   - object: The base class of all classes
--   - type: The type of all types (metaclass)
--   - str, int, list, dict, tuple: Core builtin types
--   - NoneType: The type of None
--   - None: The singleton None object
--
-- Note: These IDs are fixed UUIDs to ensure they can be referenced reliably
-- across the system. They represent the "global symbols" of CPython.
-- ============================================================================

DO $$
DECLARE
    -- Core Type IDs (fixed UUIDs for builtin types)
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TYPE_TYPE   UUID := '00000000-0000-4000-a000-000000000002';
    ID_STR_TYPE    UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_LIST_TYPE   UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_NONE_TYPE   UUID := '00000000-0000-4000-a000-000000000008';

    -- Singleton IDs
    ID_NONE_OBJ   UUID := '00000000-0000-4000-b000-000000000001';

    -- Helper Objects (Tuples for tp_bases)
    -- This tuple contains only 'object', used as tp_bases for most builtin types
    ID_TUPLE_OBJECT_ONLY UUID := gen_random_uuid();
BEGIN
    -------------------------------------------------------
    -- Phase 1: Create base PyObjects (without ob_type)
    --    NOTE: In Elytra, every object's identity is PyObject.id.
    --    We create these with ob_type = NULL to break the circular dependency
    --    between 'type' and 'object'.
    -------------------------------------------------------
    -- py_object implements CPython's PyObject
    INSERT INTO public.py_object (id, ob_type) VALUES 
    (ID_OBJECT_TYPE, NULL),      -- object type
    (ID_TYPE_TYPE,   NULL),      -- type type
    (ID_STR_TYPE,    NULL),      -- str type
    (ID_INT_TYPE,    NULL),      -- int type
    (ID_LIST_TYPE,   NULL),      -- list type
    (ID_DICT_TYPE,   NULL),      -- dict type
    (ID_TUPLE_TYPE,  NULL),      -- tuple type
    (ID_NONE_TYPE,   NULL),      -- NoneType
    (ID_NONE_OBJ,    NULL),      -- None singleton
    (ID_TUPLE_OBJECT_ONLY, NULL); -- Helper tuple for tp_bases

    -------------------------------------------------------
    -- Phase 2: Create Core PyTypeObjects
    --    NOTE: Shared-PK inheritance: PyTypeObject.ob_base == PyObject.id
    --    Each type object extends the PyObject created in Phase 1.
    -------------------------------------------------------
    -- py_type_object implements CPython's PyTypeObject
    INSERT INTO public.py_type_object (ob_base, tp_name) VALUES
    (ID_OBJECT_TYPE, 'object'),
    (ID_TYPE_TYPE,   'type'),
    (ID_STR_TYPE,    'str'),
    (ID_INT_TYPE,    'int'),
    (ID_LIST_TYPE,   'list'),
    (ID_DICT_TYPE,   'dict'),
    (ID_TUPLE_TYPE,  'tuple'),
    (ID_NONE_TYPE,   'NoneType');

    -------------------------------------------------------
    -- Phase 3: Resolve Circular References
    --    Now that type objects exist, we can set ob_type on all PyObjects.
    --    All type objects have 'type' as their ob_type (including 'type' itself).
    -------------------------------------------------------
    -- All types have 'type' as their ob_type
    UPDATE public.py_object SET ob_type = ID_TYPE_TYPE 
    WHERE id IN (ID_OBJECT_TYPE, ID_TYPE_TYPE, ID_STR_TYPE, ID_INT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE);
    
    -- None instance is a NoneType
    UPDATE public.py_object SET ob_type = ID_NONE_TYPE WHERE id = ID_NONE_OBJ;

    -------------------------------------------------------
    -- Phase 4: Create Helper Objects
    --    Create the tuple that will be used as tp_bases for most types.
    --    This tuple contains only 'object', representing single inheritance.
    -------------------------------------------------------
    -- Tuple containing only 'object' type for tp_bases
    -- NOTE: PyTupleObject.ob_base == PyObject.id
    -- py_tuple_object implements CPython's PyTupleObject
    INSERT INTO public.py_tuple_object (ob_base, ob_item)
    VALUES (ID_TUPLE_OBJECT_ONLY, ARRAY[ID_OBJECT_TYPE]);

    -------------------------------------------------------
    -- Phase 5: Set Inheritance Structure and Singletons
    --    Configure tp_bases (inheritance) for all builtin types.
    --    Most types inherit from 'object' only (single inheritance).
    -------------------------------------------------------
    -- object has no base class (tp_bases remains NULL)
    -- type inherits from object
    UPDATE public.py_type_object SET tp_bases = ID_TUPLE_OBJECT_ONLY WHERE ob_base = ID_TYPE_TYPE;
    -- All other builtin types inherit from object
    UPDATE public.py_type_object SET tp_bases = ID_TUPLE_OBJECT_ONLY 
    WHERE ob_base IN (ID_STR_TYPE, ID_INT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE);

    -- Create None Instance
    -- None is represented as a PyInstanceObject (though it's technically a singleton,
    -- not a user-defined class instance, this representation is sufficient for now).
    -- py_instance_object implements CPython's PyInstanceObject
    INSERT INTO public.py_instance_object (ob_base, in_dict)
    VALUES (ID_NONE_OBJ, NULL);

END $$;
