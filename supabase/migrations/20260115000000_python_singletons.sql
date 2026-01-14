-- Migration: Python Singletons (None, True, False)
-- Created at: 2026-01-15 00:00:00

DO $$
DECLARE
    -- Type IDs (from previous bootstrap)
    ID_TYP_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_TUP_TYPE UUID := '00000000-0000-4000-a000-000000000007';

    -- New Type IDs
    ID_NONE_TYPE UUID := '00000000-0000-4000-a000-000000000009';
    ID_BOOL_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    
    -- Singleton Instance IDs
    ID_NONE_OBJ  UUID := '00000000-0000-4000-b000-000000000001';
    ID_TRUE_OBJ  UUID := '00000000-0000-4000-b000-000000000002';
    ID_FALSE_OBJ UUID := '00000000-0000-4000-b000-000000000003';

    -- Base Object IDs for types and instances
    B_NONE_T UUID := gen_random_uuid();
    B_BOOL_T UUID := gen_random_uuid();
    B_NONE   UUID := gen_random_uuid();
    B_TRUE   UUID := gen_random_uuid();
    B_FALSE  UUID := gen_random_uuid();

    -- Helper Tuples for tp_bases
    B_TUP_INT_ONLY UUID := gen_random_uuid();
    ID_TUP_INT_ONLY UUID := gen_random_uuid();
    B_TUP_OBJ_ONLY UUID := gen_random_uuid();
    ID_TUP_OBJ_ONLY UUID := gen_random_uuid();
BEGIN
    -------------------------------------------------------
    -- 1. Create Base Objects
    -------------------------------------------------------
    INSERT INTO public.py_object (id, ob_type, address) VALUES 
    (B_NONE_T, ID_TYP_TYPE, 0x200), 
    (B_BOOL_T, ID_TYP_TYPE, 0x210),
    (B_NONE,   NULL, 0x300), -- None
    (B_TRUE,   NULL, 0x310), -- True
    (B_FALSE,  NULL, 0x320), -- False
    (B_TUP_INT_ONLY, ID_TUP_TYPE, 0x888),
    (B_TUP_OBJ_ONLY, ID_TUP_TYPE, 0x889);

    -------------------------------------------------------
    -- 2. Create Types (NoneType, bool)
    -------------------------------------------------------
    -- NoneType inherits from object
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item, ob_size) 
    VALUES (ID_TUP_OBJ_ONLY, B_TUP_OBJ_ONLY, ARRAY[(SELECT ob_base FROM public.py_type_object WHERE id = ID_OBJ_TYPE)], 1);

    INSERT INTO public.py_type_object (id, ob_base, tp_name, tp_bases) 
    VALUES (ID_NONE_TYPE, B_NONE_T, 'NoneType', ID_TUP_OBJ_ONLY);

    -- bool inherits from int
    INSERT INTO public.py_tuple_object (id, ob_base, ob_item, ob_size) 
    VALUES (ID_TUP_INT_ONLY, B_TUP_INT_ONLY, ARRAY[(SELECT ob_base FROM public.py_type_object WHERE id = ID_INT_TYPE)], 1);

    INSERT INTO public.py_type_object (id, ob_base, tp_name, tp_bases) 
    VALUES (ID_BOOL_TYPE, B_BOOL_T, 'bool', ID_TUP_INT_ONLY);

    -------------------------------------------------------
    -- 3. Create Singleton Instances
    -------------------------------------------------------
    -- None (NoneType instance)
    UPDATE public.py_object SET ob_type = ID_NONE_TYPE WHERE id = B_NONE;
    -- None 갞체는 실제로는 value가 없지만, py_instance_object나 다른 전용 테이블이 필요할 수 있습니다.
    -- 여기선 py_object 자체로 존재를 나타냅니다.

    -- True & False (bool instance)
    UPDATE public.py_object SET ob_type = ID_BOOL_TYPE WHERE id IN (B_TRUE, B_FALSE);
    
    -- bool 객체는 int를 상속받으므로 py_long_object에 값이 있어야 합니다.
    INSERT INTO public.py_long_object (id, ob_base, long_value) VALUES 
    (ID_TRUE_OBJ, B_TRUE, 1),
    (ID_FALSE_OBJ, B_FALSE, 0);

END $$;
