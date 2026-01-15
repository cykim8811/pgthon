-- Migration: Add missing int methods (bitwise, division, etc.)
-- Created at: 2026-01-15 23:00:00

DO $$
DECLARE
    -- Type ID for Int
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    ID_FNC_TYPE UUID := '00000000-0000-4000-a000-000000000008';
    ID_CODE_TYPE UUID := '00000000-0000-4000-a000-000000000011';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

    -- Type Dictionary
    V_DICT_ID UUID;
    
    -- Variables for loop
    V_METH_NAME TEXT;
    V_ARG_COUNT INTEGER;
    V_SIGNATURE TEXT;
    
    V_FUNC_OBJ UUID;
    V_FUNC_BASE UUID;
    V_CODE_OBJ UUID;
    V_CODE_BASE UUID;
    V_KEY_BASE UUID;

BEGIN
    -- 1. Find the dictionary for 'int' type
    SELECT tp_dict INTO V_DICT_ID FROM public.py_type_object WHERE id = ID_INT_TYPE;
    
    -------------------------------------------------------
    -- 2. Define Methods to Add
    -------------------------------------------------------
    CREATE TEMP TABLE temp_int_methods (
        method_name TEXT,
        arg_count INTEGER,
        signature TEXT
    ) ON COMMIT DROP;

    INSERT INTO temp_int_methods VALUES 
    -- Arithmetic (Division & Modulo)
    ('__truediv__', 2, 'int.__truediv__(self, other) -> float'), -- /
    ('__floordiv__', 2, 'int.__floordiv__(self, other) -> int'), -- //
    ('__mod__', 2, 'int.__mod__(self, other) -> int'), -- %
    ('__divmod__', 2, 'int.__divmod__(self, other) -> tuple'), -- divmod()
    ('__pow__', 3, 'int.__pow__(self, other, mod=None) -> int'), -- **

    -- Bitwise Operations
    ('__and__', 2, 'int.__and__(self, other) -> int'), -- &
    ('__or__', 2, 'int.__or__(self, other) -> int'), -- |
    ('__xor__', 2, 'int.__xor__(self, other) -> int'), -- ^
    ('__lshift__', 2, 'int.__lshift__(self, other) -> int'), -- <<
    ('__rshift__', 2, 'int.__rshift__(self, other) -> int'), -- >>
    ('__invert__', 1, 'int.__invert__(self) -> int'), -- ~

    -- Unary Operations
    ('__neg__', 1, 'int.__neg__(self) -> int'), -- -x
    ('__pos__', 1, 'int.__pos__(self) -> int'), -- +x
    ('__abs__', 1, 'int.__abs__(self) -> int'), -- abs(x)

    -- Conversions & Representation
    ('__int__', 1, 'int.__int__(self) -> int'),
    ('__float__', 1, 'int.__float__(self) -> float'),
    ('__str__', 1, 'int.__str__(self) -> str'),
    ('__repr__', 1, 'int.__repr__(self) -> str'),
    ('__bool__', 1, 'int.__bool__(self) -> bool'),
    ('__hash__', 1, 'int.__hash__(self) -> int'),
    
    -- Additional
    ('bit_length', 1, 'int.bit_length(self) -> int'),
    ('to_bytes', 1, 'int.to_bytes(self, length, byteorder, *, signed=False) -> bytes'),
    ('from_bytes', 1, 'int.from_bytes(bytes, byteorder, *, signed=False) -> int'); -- classmethod usually

    -------------------------------------------------------
    -- 3. Loop and Create
    -------------------------------------------------------
    FOR V_METH_NAME, V_ARG_COUNT, V_SIGNATURE IN SELECT method_name, arg_count, signature FROM temp_int_methods LOOP
        
        -- Generate IDs
        V_FUNC_OBJ := gen_random_uuid();
        V_FUNC_BASE := gen_random_uuid();
        V_CODE_OBJ := gen_random_uuid();
        V_CODE_BASE := gen_random_uuid();
        V_KEY_BASE := gen_random_uuid();

        -- 1. Create Key String Object (Method Name)
        INSERT INTO public.py_object (id, ob_type) VALUES (V_KEY_BASE, ID_STR_TYPE);
        INSERT INTO public.py_unicode_object (id, ob_base, str_value) VALUES (gen_random_uuid(), V_KEY_BASE, V_METH_NAME);

        -- 2. Create Code Object with Signature
        INSERT INTO public.py_object (id, ob_type) VALUES (V_CODE_BASE, ID_CODE_TYPE);
        INSERT INTO public.py_code_object (id, ob_base, co_name, co_filename, co_argcount, co_code) 
        VALUES (V_CODE_OBJ, V_CODE_BASE, V_METH_NAME, '<slot wrapper ' || V_METH_NAME || '>', V_ARG_COUNT, V_SIGNATURE);

        -- 3. Create Function Object
        INSERT INTO public.py_object (id, ob_type) VALUES (V_FUNC_BASE, ID_FNC_TYPE);
        INSERT INTO public.py_function_object (id, ob_base, func_name, func_code, func_globals)
        VALUES (V_FUNC_OBJ, V_FUNC_BASE, V_METH_NAME, V_CODE_OBJ, NULL);

        -- 4. Link to Dict
        INSERT INTO public.py_dict_entry (id, dict_id, me_key, me_value) 
        VALUES (gen_random_uuid(), V_DICT_ID, V_KEY_BASE, V_FUNC_BASE);
        
        -- Update usage count
        UPDATE public.py_dict_object SET ma_used = ma_used + 1 WHERE id = V_DICT_ID;
        
    END LOOP;

END $$;
