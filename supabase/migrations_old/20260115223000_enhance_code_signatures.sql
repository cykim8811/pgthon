-- Migration: Enhance co_code with readable signatures
-- Created at: 2026-01-15 22:30:00

DO $$
DECLARE
    -- Type IDs to identify which type a method belongs to
    ID_OBJ_TYPE UUID := '00000000-0000-4000-a000-000000000001';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_LST_TYPE UUID := '00000000-0000-4000-a000-000000000005';
    ID_DCT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_TYP_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    
    -- Helper variable to store dict_id
    V_DICT_ID UUID;
BEGIN

    -- Helper logic: We need to find the code objects linked to specific types' tp_dict
    -- Since SQL updates with joins can be verbose, we'll do it per type group.

    -------------------------------------------------------
    -- 1. Object Methods
    -------------------------------------------------------
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_OBJ_TYPE;
    
    UPDATE public.py_code_object 
    SET co_code = 'object.' || co_name || '(self, ...) -> Native<slot_wrapper>'
    WHERE id IN (
        SELECT func_code FROM public.py_function_object 
        WHERE ob_base IN (
            SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID
        )
    );

    -------------------------------------------------------
    -- 2. List Methods
    -------------------------------------------------------
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_LST_TYPE;

    -- Update list methods generally
    UPDATE public.py_code_object 
    SET co_code = 'list.' || co_name || '(self, ...) -> Native<PyList_Method>'
    WHERE id IN (
        SELECT func_code FROM public.py_function_object 
        WHERE ob_base IN (
            SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID
        )
    );
    
    -- Specific updates for clarity
    UPDATE public.py_code_object SET co_code = 'list.append(self, object) -> None' WHERE co_name = 'append' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    UPDATE public.py_code_object SET co_code = 'list.pop(self, index=-1) -> item' WHERE co_name = 'pop' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    UPDATE public.py_code_object SET co_code = 'list.extend(self, iterable) -> None' WHERE co_name = 'extend' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    UPDATE public.py_code_object SET co_code = 'list.__getitem__(self, index) -> item' WHERE co_name = '__getitem__' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    UPDATE public.py_code_object SET co_code = 'list.__setitem__(self, index, value) -> None' WHERE co_name = '__setitem__' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    UPDATE public.py_code_object SET co_code = 'list.__len__(self) -> int' WHERE co_name = '__len__' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));


    -------------------------------------------------------
    -- 3. Dict Methods
    -------------------------------------------------------
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_DCT_TYPE;

    UPDATE public.py_code_object 
    SET co_code = 'dict.' || co_name || '(self, ...) -> Native<PyDict_Method>'
    WHERE id IN (
        SELECT func_code FROM public.py_function_object 
        WHERE ob_base IN (
            SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID
        )
    );

    -- Specific updates
    UPDATE public.py_code_object SET co_code = 'dict.keys(self) -> dict_keys' WHERE co_name = 'keys' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    UPDATE public.py_code_object SET co_code = 'dict.values(self) -> dict_values' WHERE co_name = 'values' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    UPDATE public.py_code_object SET co_code = 'dict.items(self) -> dict_items' WHERE co_name = 'items' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    UPDATE public.py_code_object SET co_code = 'dict.get(self, key, default=None) -> value' WHERE co_name = 'get' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    UPDATE public.py_code_object SET co_code = 'dict.__getitem__(self, key) -> value' WHERE co_name = '__getitem__' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    UPDATE public.py_code_object SET co_code = 'dict.__setitem__(self, key, value) -> None' WHERE co_name = '__setitem__' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    UPDATE public.py_code_object SET co_code = 'dict.__delitem__(self, key) -> None' WHERE co_name = '__delitem__' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));
    
    -------------------------------------------------------
    -- 4. Int Methods
    -------------------------------------------------------
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_INT_TYPE;

    UPDATE public.py_code_object 
    SET co_code = 'int.' || co_name || '(self, other) -> int'
    WHERE id IN (
        SELECT func_code FROM public.py_function_object 
        WHERE ob_base IN (
            SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID
        )
    );
    
    -------------------------------------------------------
    -- 5. Type Methods
    -------------------------------------------------------
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_TYP_TYPE;

    UPDATE public.py_code_object 
    SET co_code = 'type.' || co_name || '(cls, ...) -> Native<type_slot>'
    WHERE id IN (
        SELECT func_code FROM public.py_function_object 
        WHERE ob_base IN (
            SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID
        )
    );

    UPDATE public.py_code_object SET co_code = 'type.__call__(cls, *args, **kwargs) -> object' WHERE co_name = '__call__' AND id IN (SELECT func_code FROM public.py_function_object WHERE ob_base IN (SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID));

    -------------------------------------------------------
    -- 6. String Methods
    -------------------------------------------------------
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_STR_TYPE;
    
    UPDATE public.py_code_object 
    SET co_code = 'str.' || co_name || '(self, ...) -> str'
    WHERE id IN (
        SELECT func_code FROM public.py_function_object 
        WHERE ob_base IN (
            SELECT me_value FROM public.py_dict_entry WHERE dict_id = V_DICT_ID
        )
    );

END $$;
