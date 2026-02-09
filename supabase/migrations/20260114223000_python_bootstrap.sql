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
--   - str, bytes, int, float, list, dict, tuple: Core builtin types
--   - NoneType: The type of None
--   - builtin_function_or_method: The type of C builtin functions
--   - module: The type of module objects
--   - None: The singleton None object
--   - True, False: The bool singletons (tp_richcompare return values, etc.)
--   - NotImplemented: The singleton for "comparison not implemented"
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
    ID_BYTES_TYPE  UUID := '00000000-0000-4000-a000-000000000012';
    ID_INT_TYPE    UUID := '00000000-0000-4000-a000-000000000004';
    ID_FLOAT_TYPE  UUID := '00000000-0000-4000-a000-000000000009';
    ID_LIST_TYPE   UUID := '00000000-0000-4000-a000-000000000005';
    ID_DICT_TYPE   UUID := '00000000-0000-4000-a000-000000000006';
    ID_TUPLE_TYPE  UUID := '00000000-0000-4000-a000-000000000007';
    ID_NONE_TYPE   UUID := '00000000-0000-4000-a000-000000000008';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    ID_MODULE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_BOOL_TYPE   UUID := '00000000-0000-4000-a000-000000000013';
    ID_NOT_IMPLEMENTED_TYPE UUID := '00000000-0000-4000-a000-000000000014';
    ID_NULL_TYPE   UUID := '00000000-0000-4000-a000-000000000015';
    ID_SLICE_TYPE  UUID := '00000000-0000-4000-a000-000000000016';
    ID_FUNCTION_TYPE UUID := '00000000-0000-4000-a000-000000000017';
    ID_SET_TYPE    UUID := '00000000-0000-4000-a000-000000000018';
    ID_LIST_ITERATOR_TYPE UUID := '00000000-0000-4000-a000-000000000031';
    ID_TUPLE_ITERATOR_TYPE UUID := '00000000-0000-4000-a000-000000000032';
    ID_DICT_KEYITERATOR_TYPE UUID := '00000000-0000-4000-a000-000000000033';
    ID_STR_ITERATOR_TYPE UUID := '00000000-0000-4000-a000-000000000034';

    -- Singleton IDs
    ID_NONE_OBJ   UUID := '00000000-0000-4000-b000-000000000001';
    ID_TRUE_OBJ   UUID := '00000000-0000-4000-b000-000000000010';
    ID_FALSE_OBJ  UUID := '00000000-0000-4000-b000-000000000011';
    ID_NOT_IMPLEMENTED_OBJ UUID := '00000000-0000-4000-b000-000000000012';
    ID_NULL_OBJ    UUID := '00000000-0000-4000-b000-000000000030';
    
    -- Module IDs (b000-002); b000-003, 004 etc. are used by builtin_functions for len, abs, etc.
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
    ID_DICT_BOOL_TYPE   UUID := gen_random_uuid();
    ID_DICT_NOT_IMPLEMENTED_TYPE UUID := gen_random_uuid();
    ID_DICT_NULL_TYPE   UUID := gen_random_uuid();
    ID_DICT_SLICE_TYPE  UUID := gen_random_uuid();
    ID_DICT_FUNCTION_TYPE UUID := gen_random_uuid();
    ID_DICT_SET_TYPE UUID := gen_random_uuid();
    ID_DICT_LIST_ITERATOR_TYPE UUID := gen_random_uuid();
    ID_DICT_TUPLE_ITERATOR_TYPE UUID := gen_random_uuid();
    ID_DICT_DICT_KEYITERATOR_TYPE UUID := gen_random_uuid();
    ID_DICT_STR_ITERATOR_TYPE UUID := gen_random_uuid();

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
    (ID_BYTES_TYPE,  NULL),      -- bytes type
    (ID_INT_TYPE,    NULL),      -- int type
    (ID_FLOAT_TYPE,  NULL),      -- float type
    (ID_LIST_TYPE,   NULL),      -- list type
    (ID_DICT_TYPE,   NULL),      -- dict type
    (ID_TUPLE_TYPE,  NULL),      -- tuple type
    (ID_NONE_TYPE,   NULL),      -- NoneType
    (ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, NULL), -- builtin_function_or_method type
    (ID_MODULE_TYPE, NULL),      -- module type
    (ID_NONE_OBJ,    NULL),      -- None singleton
    (ID_TRUE_OBJ,    NULL),      -- True singleton
    (ID_FALSE_OBJ,   NULL),      -- False singleton
    (ID_NOT_IMPLEMENTED_OBJ, NULL), -- NotImplemented singleton
    (ID_BOOL_TYPE,   NULL),      -- bool type
    (ID_NOT_IMPLEMENTED_TYPE, NULL), -- NotImplementedType
    (ID_NULL_TYPE,   NULL),      -- null type (PUSH_NULL stack placeholder)
    (ID_NULL_OBJ,    NULL),      -- null singleton (PUSH_NULL)
    (ID_SLICE_TYPE,  NULL),      -- slice type
    (ID_FUNCTION_TYPE, NULL),    -- function type
    (ID_SET_TYPE, NULL),         -- set type
    (ID_LIST_ITERATOR_TYPE, NULL),  -- list_iterator type
    (ID_TUPLE_ITERATOR_TYPE, NULL), -- tuple_iterator type
    (ID_DICT_KEYITERATOR_TYPE, NULL), -- dict_keyiterator type
    (ID_STR_ITERATOR_TYPE, NULL),   -- str_iterator type
    (ID_DICT_SLICE_TYPE, NULL),  -- dict for slice type
    (ID_DICT_FUNCTION_TYPE, NULL), -- dict for function type
    (ID_DICT_SET_TYPE, NULL),    -- dict for set type
    (ID_DICT_LIST_ITERATOR_TYPE, NULL), -- dict for list_iterator type
    (ID_DICT_TUPLE_ITERATOR_TYPE, NULL), -- dict for tuple_iterator type
    (ID_DICT_DICT_KEYITERATOR_TYPE, NULL), -- dict for dict_keyiterator type
    (ID_DICT_STR_ITERATOR_TYPE, NULL), -- dict for str_iterator type
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
    (ID_DICT_BOOL_TYPE, NULL),   -- dict for bool type
    (ID_DICT_NOT_IMPLEMENTED_TYPE, NULL), -- dict for NotImplementedType
    (ID_DICT_NULL_TYPE, NULL),   -- dict for null type
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
    (ID_BYTES_TYPE,  'bytes'),
    (ID_INT_TYPE,    'int'),
    (ID_FLOAT_TYPE,  'float'),
    (ID_LIST_TYPE,   'list'),
    (ID_DICT_TYPE,   'dict'),
    (ID_TUPLE_TYPE,  'tuple'),
    (ID_NONE_TYPE,   'NoneType'),
    (ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, 'builtin_function_or_method'),
    (ID_MODULE_TYPE, 'module'),
    (ID_BOOL_TYPE, 'bool'),
    (ID_NOT_IMPLEMENTED_TYPE, 'NotImplementedType'),
    (ID_NULL_TYPE, 'null'),
    (ID_SLICE_TYPE, 'slice'),
    (ID_FUNCTION_TYPE, 'function'),
    (ID_SET_TYPE, 'set'),
    (ID_LIST_ITERATOR_TYPE, 'list_iterator'),
    (ID_TUPLE_ITERATOR_TYPE, 'tuple_iterator'),
    (ID_DICT_KEYITERATOR_TYPE, 'dict_keyiterator'),
    (ID_STR_ITERATOR_TYPE, 'str_iterator');

    -------------------------------------------------------
    -- Phase 3: Resolve Circular References
    --    Now that type objects exist, we can set ob_type on all PyObjects.
    --    All type objects have 'type' as their ob_type (including 'type' itself).
    -------------------------------------------------------
    -- All types have 'type' as their ob_type
    UPDATE public.py_object SET ob_type = ID_TYPE_TYPE 
    WHERE id IN (ID_OBJECT_TYPE, ID_TYPE_TYPE, ID_STR_TYPE, ID_BYTES_TYPE, ID_INT_TYPE, ID_FLOAT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, ID_MODULE_TYPE, ID_BOOL_TYPE, ID_NOT_IMPLEMENTED_TYPE, ID_NULL_TYPE, ID_SLICE_TYPE, ID_FUNCTION_TYPE, ID_SET_TYPE, ID_LIST_ITERATOR_TYPE, ID_TUPLE_ITERATOR_TYPE, ID_DICT_KEYITERATOR_TYPE, ID_STR_ITERATOR_TYPE);
    
    -- None instance is a NoneType
    UPDATE public.py_object SET ob_type = ID_NONE_TYPE WHERE id = ID_NONE_OBJ;
    
    -- True, False are bool
    UPDATE public.py_object SET ob_type = ID_BOOL_TYPE WHERE id IN (ID_TRUE_OBJ, ID_FALSE_OBJ);
    
    -- NotImplemented is NotImplementedType
    UPDATE public.py_object SET ob_type = ID_NOT_IMPLEMENTED_TYPE WHERE id = ID_NOT_IMPLEMENTED_OBJ;
    
    -- null singleton is null type (PUSH_NULL stack placeholder)
    UPDATE public.py_object SET ob_type = ID_NULL_TYPE WHERE id = ID_NULL_OBJ;
    
    -- __builtins__ module is a module type
    UPDATE public.py_object SET ob_type = ID_MODULE_TYPE WHERE id = ID_BUILTINS_MODULE;
    
    -- tp_bases tuple is a tuple object
    UPDATE public.py_object SET ob_type = ID_TUPLE_TYPE WHERE id = ID_TUPLE_BASES_OBJECT;
    
    -- All dict objects have 'dict' as their ob_type
    UPDATE public.py_object SET ob_type = ID_DICT_TYPE 
    WHERE id IN (ID_DICT_OBJECT_TYPE, ID_DICT_TYPE_TYPE, ID_DICT_STR_TYPE, ID_DICT_INT_TYPE,
                 ID_DICT_FLOAT_TYPE, ID_DICT_LIST_TYPE, ID_DICT_DICT_TYPE, ID_DICT_TUPLE_TYPE, ID_DICT_NONE_TYPE,
                 ID_DICT_BUILTIN_FUNCTION_OR_METHOD_TYPE, ID_DICT_MODULE_TYPE, ID_DICT_BOOL_TYPE, ID_DICT_NOT_IMPLEMENTED_TYPE, ID_DICT_NULL_TYPE, ID_DICT_SLICE_TYPE, ID_DICT_FUNCTION_TYPE, ID_DICT_SET_TYPE,
                 ID_DICT_LIST_ITERATOR_TYPE, ID_DICT_TUPLE_ITERATOR_TYPE, ID_DICT_DICT_KEYITERATOR_TYPE, ID_DICT_STR_ITERATOR_TYPE,
                 ID_DICT_BUILTINS_MODULE);
    
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
    (ID_DICT_BOOL_TYPE),   -- dict for bool type
    (ID_DICT_NOT_IMPLEMENTED_TYPE), -- dict for NotImplementedType
    (ID_DICT_NULL_TYPE),   -- dict for null type
    (ID_DICT_SLICE_TYPE),  -- dict for slice type
    (ID_DICT_FUNCTION_TYPE), -- dict for function type
    (ID_DICT_SET_TYPE), -- dict for set type
    (ID_DICT_LIST_ITERATOR_TYPE), -- dict for list_iterator type
    (ID_DICT_TUPLE_ITERATOR_TYPE), -- dict for tuple_iterator type
    (ID_DICT_DICT_KEYITERATOR_TYPE), -- dict for dict_keyiterator type
    (ID_DICT_STR_ITERATOR_TYPE), -- dict for str_iterator type
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
    WHERE ob_base IN (ID_STR_TYPE, ID_INT_TYPE, ID_FLOAT_TYPE, ID_LIST_TYPE, ID_DICT_TYPE, ID_TUPLE_TYPE, ID_NONE_TYPE, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE, ID_MODULE_TYPE, ID_BOOL_TYPE, ID_NOT_IMPLEMENTED_TYPE, ID_NULL_TYPE, ID_SLICE_TYPE, ID_FUNCTION_TYPE, ID_SET_TYPE, ID_LIST_ITERATOR_TYPE, ID_TUPLE_ITERATOR_TYPE, ID_DICT_KEYITERATOR_TYPE, ID_STR_ITERATOR_TYPE);

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
    UPDATE public.py_type_object SET tp_dict = ID_DICT_BOOL_TYPE WHERE ob_base = ID_BOOL_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_NOT_IMPLEMENTED_TYPE WHERE ob_base = ID_NOT_IMPLEMENTED_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_NULL_TYPE WHERE ob_base = ID_NULL_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_SLICE_TYPE WHERE ob_base = ID_SLICE_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_FUNCTION_TYPE WHERE ob_base = ID_FUNCTION_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_SET_TYPE WHERE ob_base = ID_SET_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_LIST_ITERATOR_TYPE WHERE ob_base = ID_LIST_ITERATOR_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_TUPLE_ITERATOR_TYPE WHERE ob_base = ID_TUPLE_ITERATOR_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_DICT_KEYITERATOR_TYPE WHERE ob_base = ID_DICT_KEYITERATOR_TYPE;
    UPDATE public.py_type_object SET tp_dict = ID_DICT_STR_ITERATOR_TYPE WHERE ob_base = ID_STR_ITERATOR_TYPE;

    -- Create None Instance
    -- None is a special singleton object in CPython, represented as a PyObject
    -- with type NoneType. Following the same pattern as other builtin objects,
    -- we use a dedicated table (py_none_object) for consistency.
    -- py_none_object implements CPython's Py_None singleton
    INSERT INTO public.py_none_object (ob_base)
    VALUES (ID_NONE_OBJ);

    -- Create True and False (CPython's Py_True / Py_False)
    -- Used as tp_richcompare return values and elsewhere. Same pattern as other singletons.
    INSERT INTO public.py_bool_object (ob_base, bool_value)
    VALUES (ID_TRUE_OBJ, true),
           (ID_FALSE_OBJ, false);

    -- Create NotImplemented (CPython's Py_NotImplemented)
    -- Returned by tp_richcompare when a type does not implement a comparison.
    INSERT INTO public.py_not_implemented_object (ob_base)
    VALUES (ID_NOT_IMPLEMENTED_OBJ);

    -- Create null singleton (CPython 3.11 PUSH_NULL stack placeholder)
    -- Used by PUSH_NULL(2) for bound method / method call protocol. Not exposed to Python.
    INSERT INTO public.py_null_object (ob_base)
    VALUES (ID_NULL_OBJ);

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
