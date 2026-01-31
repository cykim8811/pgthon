-- ============================================================================
-- Migration: Jump Phase 1 — py_object_istrue (PyObject_IsTrue)
-- Created: 2026-01-14 24:03:00
--
-- Purpose:
--   CPython PyObject_IsTrue: truth testing for POP_JUMP_IF_FALSE 등.
--   __bool__/__len__ 슬롯 없이, 싱글톤·테이블 존재로만 판별. tp_name 분기 금지.
--
-- Design: docs/JUMP_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- Singleton IDs (must match bootstrap 20260114223000)
-- True:  00000000-0000-4000-b000-000000000010
-- False: 00000000-0000-4000-b000-000000000011
-- None:  00000000-0000-4000-b000-000000000001
-- NotImplemented: 00000000-0000-4000-b000-000000000012

CREATE OR REPLACE FUNCTION public.py_object_istrue(obj_id uuid)
RETURNS boolean AS $$
DECLARE
    id_true  uuid := '00000000-0000-4000-b000-000000000010';
    id_false uuid := '00000000-0000-4000-b000-000000000011';
    id_none  uuid := '00000000-0000-4000-b000-000000000001';
    id_ni    uuid := '00000000-0000-4000-b000-000000000012';
    n numeric;
    fval double precision;
    s text;
    arr uuid[];
    cnt numeric;
BEGIN
    IF obj_id IS NULL THEN
        RETURN false;
    END IF;

    -- Singletons
    IF obj_id = id_true THEN
        RETURN true;
    END IF;
    IF obj_id IN (id_false, id_none, id_ni) THEN
        RETURN false;
    END IF;

    -- int: 0 -> false
    IF EXISTS (SELECT 1 FROM public.py_long_object WHERE ob_base = obj_id) THEN
        SELECT long_value INTO n FROM public.py_long_object WHERE ob_base = obj_id;
        RETURN (n IS NOT NULL AND n <> 0);
    END IF;

    -- str: '' -> false
    IF EXISTS (SELECT 1 FROM public.py_unicode_object WHERE ob_base = obj_id) THEN
        SELECT str_value INTO s FROM public.py_unicode_object WHERE ob_base = obj_id;
        RETURN (s IS NOT NULL AND s <> '');
    END IF;

    -- float: 0.0 -> false
    IF EXISTS (SELECT 1 FROM public.py_float_object WHERE ob_base = obj_id) THEN
        SELECT ob_fval INTO fval FROM public.py_float_object WHERE ob_base = obj_id;
        RETURN (fval IS NOT NULL AND fval <> 0);
    END IF;

    -- list: length 0 -> false
    IF EXISTS (SELECT 1 FROM public.py_list_object WHERE ob_base = obj_id) THEN
        SELECT ob_item INTO arr FROM public.py_list_object WHERE ob_base = obj_id;
        RETURN (arr IS NOT NULL AND array_length(arr, 1) IS NOT NULL AND array_length(arr, 1) > 0);
    END IF;

    -- tuple: length 0 -> false
    IF EXISTS (SELECT 1 FROM public.py_tuple_object WHERE ob_base = obj_id) THEN
        SELECT ob_item INTO arr FROM public.py_tuple_object WHERE ob_base = obj_id;
        RETURN (arr IS NOT NULL AND array_length(arr, 1) IS NOT NULL AND array_length(arr, 1) > 0);
    END IF;

    -- dict: length 0 -> false
    IF EXISTS (SELECT 1 FROM public.py_dict_object WHERE ob_base = obj_id) THEN
        cnt := public.py_dict_mp_length(obj_id);
        RETURN (cnt IS NOT NULL AND cnt > 0);
    END IF;

    -- Default: object exists -> true (CPython: no __bool__/__len__ -> true)
    RETURN true;
END;
$$ LANGUAGE plpgsql;
