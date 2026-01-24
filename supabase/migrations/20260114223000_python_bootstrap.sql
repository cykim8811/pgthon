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
--   - str, int, float, list, dict, tuple: Core builtin types
--   - NoneType: The type of None
--   - builtin_function_or_method: The type of C builtin functions
--   - None: The singleton None object
--   - __builtins__: The builtins module (contains builtin functions)
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
    ID_FLOAT_TYPE  UUID := '00000000-0000-4000-a000-000000000009';
    ID_LIST_TYPE   UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_NONE_TYPE   UUID := '00000000-0000-4000-a000-000000000008';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    ID_MODULE_TYPE UUID := '00000000-0000-4000-a000-000000000011';

    -- Singleton IDs
    ID_NONE_OBJ   UUID := '00000000-0000-4000-b000-000000000001';
    
    -- Module IDs
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';

    -- tp_bases Tuple: (object,)
    -- This tuple contains only the 'object' type. It is used as tp_bases for
    -- most builtin types that inherit from 'object' only (single inheritance).
    -- Multiple types share this same tuple object for their tp_bases field.
    ID_TUPLE_BASES_OBJECT UUID := gen_random_uuid();

    -- tp_dict Dict Objects: Each type object has its own dict for type attributes
    -- In CPython, each type object maintains a separate __dict__ for its attributes.
    -- These dict objects are created during bootstrap and linked to their respective types.
    ID_DICT_OBJECT_TYPE UUID := gen_random_uuid();
    ID_DICT_TYPE_TYPE   UUID := gen_random_uuid();
    ID_DICT_STR_TYPE    UUID := gen_random_uuid();
    ID_DICT_INT_TYPE    UUID := gen_random_uuid();
    ID_DICT_FLOAT_TYPE  UUID := gen_random_uuid();
    ID_DICT_LIST_TYPE   UUID := gen_random_uuid();
    ID_DICT_DICT_TYPE   UUID := gen_random_uuid();
    ID_DICT_TUPLE_TYPE  UUID := gen_random_uuid();
    ID_DICT_NONE_TYPE   UUID := gen_random_uuid();
    ID_DICT_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := gen_random_uuid();
    ID_DICT_MODULE_TYPE UUID := gen_random_uuid();
    
    -- Module dict: __builtins__ module's namespace dictionary
    ID_DICT_BUILTINS_MODULE UUID := gen_random_uuid();
    
    -- String objects for module names and function names
    ID_STR_BUILTINS_MODULE_NAME UUID := gen_random_uuid();
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
    (ID_FLOAT_TYPE,  NULL),      -- float type
    (ID_LIST_TYPE,   NULL),      -- list type
    (ID_DICT_TYPE,   NULL),      -- dict type
    (ID_TUPLE_TYPE,  NULL),      -- tuple type
    (ID_NONE_TYPE,   NULL),      -- NoneType
    (ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, NULL), -- builtin_function_or_method type
    (ID_MODULE_TYPE, NULL),      -- module type
    (ID_NONE_OBJ,    NULL),      -- None singleton
    (ID_BUILTINS_MODULE, NULL),  -- __builtins__ module
    (ID_TUPLE_BASES_OBJECT, NULL), -- tp_bases tuple: (object,)
    -- Each type object has its own dict for type attributes (tp_dict)
    (ID_DICT_OBJECT_TYPE, NULL), -- dict for object type
    (ID_DICT_TYPE_TYPE,   NULL), -- dict for type type
    (ID_DICT_STR_TYPE,    NULL), -- dict for str type
    (ID_DICT_INT_TYPE,    NULL), -- dict for int type
    (ID_DICT_FLOAT_TYPE,  NULL), -- dict for float type
    (ID_DICT_LIST_TYPE,   NULL), -- dict for list type
    (ID_DICT_DICT_TYPE,   NULL), -- dict for dict type
    (ID_DICT_TUPLE_TYPE,  NULL), -- dict for tuple type
    (ID_DICT_NONE_TYPE,   NULL), -- dict for NoneType
    (ID_DICT_BUILTIN_FUNCTION_OR_METHOD_TYPE, NULL), -- dict for builtin_function_or_method type
    (ID_DICT_MODULE_TYPE, NULL), -- dict for module type
    -- Module dicts
    (ID_DICT_BUILTINS_MODULE, NULL), -- dict for __builtins__ module
    -- String objects
    (ID_STR_BUILTINS_MODULE_NAME, NULL); -- string "builtins"

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
    (ID_FLOAT_TYPE,  'float'),
    (ID_LIST_TYPE,   'list'),
    (ID_DICT_TYPE,   'dict'),
    (ID_TUPLE_TYPE,  'tuple'),
    (ID_NONE_TYPE,   'NoneType'),
    (ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, 'builtin_function_or_method'),
    (ID_MODULE_TYPE, 'module');

    -------------------------------------------------------
    -- Phase 3: Resolve Circular References
    --    Now that type objects exist, we can set ob_type on all PyObjects.
    --    All type objects have 'type' as their ob_type (including 'type' itself).
    -------------------------------------------------------
    -- All types have 'type' as their ob_type
    UPDATE public.py_object SET ob_type = ID_TYPE_TYPE 
    WHERE id IN (ID_OBJECT_TYPE, ID_TYPE_TYPE, ID_STR_TYPE, ID_INT_TYPE, ID_FLOAT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, ID_MODULE_TYPE);
    
    -- None instance is a NoneType
    UPDATE public.py_object SET ob_type = ID_NONE_TYPE WHERE id = ID_NONE_OBJ;
    
    -- __builtins__ module is a module type
    UPDATE public.py_object SET ob_type = ID_MODULE_TYPE WHERE id = ID_BUILTINS_MODULE;
    
    -- tp_bases tuple is a tuple object
    UPDATE public.py_object SET ob_type = ID_TUPLE_TYPE WHERE id = ID_TUPLE_BASES_OBJECT;
    
    -- All dict objects have 'dict' as their ob_type
    UPDATE public.py_object SET ob_type = ID_DICT_TYPE 
    WHERE id IN (ID_DICT_OBJECT_TYPE, ID_DICT_TYPE_TYPE, ID_DICT_STR_TYPE, ID_DICT_INT_TYPE, 
                 ID_DICT_FLOAT_TYPE, ID_DICT_LIST_TYPE, ID_DICT_DICT_TYPE, ID_DICT_TUPLE_TYPE, ID_DICT_NONE_TYPE,
                 ID_DICT_BUILTIN_FUNCTION_OR_METHOD_TYPE, ID_DICT_MODULE_TYPE, ID_DICT_BUILTINS_MODULE);
    
    -- String objects have 'str' as their ob_type
    UPDATE public.py_object SET ob_type = ID_STR_TYPE WHERE id = ID_STR_BUILTINS_MODULE_NAME;

    -------------------------------------------------------
    -- Phase 4: Create tp_bases Tuple and tp_dict Dict Objects
    --    Create the tuple (object,) that will be used as tp_bases for most
    --    builtin types. Since most types inherit from 'object' only (single
    --    inheritance), they all share this same tuple object.
    --    Also create dict objects for each type's tp_dict field.
    -------------------------------------------------------
    -- Create tuple containing only 'object' type: (object,)
    -- NOTE: PyTupleObject.ob_base == PyObject.id
    -- py_tuple_object implements CPython's PyTupleObject
    INSERT INTO public.py_tuple_object (ob_base, ob_item)
    VALUES (ID_TUPLE_BASES_OBJECT, ARRAY[ID_OBJECT_TYPE]);

    -- Create dict objects for each type's tp_dict
    -- In CPython, each type object has its own __dict__ for storing type attributes.
    -- py_dict_object implements CPython's PyDictObject
    INSERT INTO public.py_dict_object (ob_base) VALUES
    (ID_DICT_OBJECT_TYPE), -- dict for object type
    (ID_DICT_TYPE_TYPE),   -- dict for type type
    (ID_DICT_STR_TYPE),    -- dict for str type
    (ID_DICT_INT_TYPE),    -- dict for int type
    (ID_DICT_FLOAT_TYPE),  -- dict for float type
    (ID_DICT_LIST_TYPE),   -- dict for list type
    (ID_DICT_DICT_TYPE),   -- dict for dict type
    (ID_DICT_TUPLE_TYPE),  -- dict for tuple type
    (ID_DICT_NONE_TYPE),   -- dict for NoneType
    (ID_DICT_BUILTIN_FUNCTION_OR_METHOD_TYPE), -- dict for builtin_function_or_method type
    (ID_DICT_MODULE_TYPE), -- dict for module type
    (ID_DICT_BUILTINS_MODULE); -- dict for __builtins__ module
    
    -- Create string object for module name
    -- py_unicode_object implements CPython's PyUnicodeObject
    INSERT INTO public.py_unicode_object (ob_base, str_value)
    VALUES (ID_STR_BUILTINS_MODULE_NAME, 'builtins');

    -------------------------------------------------------
    -- Phase 5: Set Inheritance Structure, tp_dict, and Singletons
    --    Configure tp_bases (inheritance) and tp_dict for all builtin types.
    --    Most types inherit from 'object' only, so they all reference the
    --    same tp_bases tuple (ID_TUPLE_BASES_OBJECT) created in Phase 4.
    --    Each type gets its own dict object for type attributes.
    -------------------------------------------------------
    -- object has no base class (tp_bases remains NULL)
    -- type inherits from object
    UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_OBJECT WHERE ob_base = ID_TYPE_TYPE;
    -- All other builtin types inherit from object (they share the same tp_bases tuple)
    UPDATE public.py_type_object SET tp_bases = ID_TUPLE_BASES_OBJECT 
    WHERE ob_base IN (ID_STR_TYPE, ID_INT_TYPE, ID_FLOAT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, ID_MODULE_TYPE);

    -- Set tp_dict for each type object
    -- Each type object has its own dict for storing type attributes (methods, class variables, etc.)
    UPDATE public.py_type_object SET tp_dict = ID_DICT_OBJECT_TYPE WHERE ob_base = ID_OBJECT_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_TYPE_TYPE WHERE ob_base = ID_TYPE_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_STR_TYPE WHERE ob_base = ID_STR_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_INT_TYPE WHERE ob_base = ID_INT_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_FLOAT_TYPE WHERE ob_base = ID_FLOAT_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_LIST_TYPE WHERE ob_base = ID_LIST_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_DICT_TYPE WHERE ob_base = ID_DICT_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_TUPLE_TYPE WHERE ob_base = ID_TUPLE_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_NONE_TYPE WHERE ob_base = ID_NONE_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_BUILTIN_FUNCTION_OR_METHOD_TYPE WHERE ob_base = ID_BUILTIN_FUNCTION_OR_METHOD_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_MODULE_TYPE WHERE ob_base = ID_MODULE_TYPE;

    -- Create None Instance
    -- None is a special singleton object in CPython, represented as a PyObject
    -- with type NoneType. Following the same pattern as other builtin objects,
    -- we use a dedicated table (py_none_object) for consistency.
    -- py_none_object implements CPython's Py_None singleton
    INSERT INTO public.py_none_object (ob_base)
    VALUES (ID_NONE_OBJ);

    -------------------------------------------------------
    -- Phase 6: Create __builtins__ Module
    --    Create the builtins module object that contains all builtin functions.
    --    This module's __dict__ will be populated with builtin functions in later
    --    migrations or at runtime.
    -------------------------------------------------------
    -- Create __builtins__ module object
    -- py_module_object implements CPython's PyModuleObject
    INSERT INTO public.py_module_object (ob_base, md_dict, md_name)
    VALUES (ID_BUILTINS_MODULE, ID_DICT_BUILTINS_MODULE, ID_STR_BUILTINS_MODULE_NAME);

END $$;
