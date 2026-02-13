-- ============================================================================
-- Migration: range() Type + Builtin (CPython 3.11)
-- Created: 2026-01-14 22:52:00
--
-- Purpose:
--   Implements the range type (py_range_object table), range_iterator type,
--   and the range() builtin function. range(stop) or range(start, stop[, step]).
--
-- Depends: 223000 (bootstrap), 224300 (exception_setters), 227100 (tp_iter_slot)
-- ============================================================================

-- ============================================================================
-- 1. Schema: py_range_object and py_range_iterator_object
-- ============================================================================
CREATE TABLE public.py_range_object (
    ob_base UUID PRIMARY KEY REFERENCES public.py_object(id) ON DELETE CASCADE,
    ob_start NUMERIC NOT NULL DEFAULT 0,
    ob_stop NUMERIC NOT NULL,
    ob_step NUMERIC NOT NULL DEFAULT 1
);

CREATE TABLE public.py_range_iterator_object (
    ob_base UUID PRIMARY KEY REFERENCES public.py_object(id) ON DELETE CASCADE,
    it_start NUMERIC NOT NULL,
    it_stop NUMERIC NOT NULL,
    it_step NUMERIC NOT NULL,
    it_index NUMERIC NOT NULL DEFAULT 0, -- current value = start + index * step
    it_len NUMERIC NOT NULL              -- precomputed length
);

ALTER TABLE public.py_range_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.py_range_iterator_object ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all py_range_object" ON public.py_range_object FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all py_range_iterator_object" ON public.py_range_iterator_object FOR ALL USING (true) WITH CHECK (true);

-- ============================================================================
-- 2. Bootstrap: range type (a000-0040) and range_iterator type (a000-0041)
-- ============================================================================
DO $$
DECLARE
    ID_TYPE_TYPE UUID := '00000000-0000-4000-a000-000000000002';
    ID_DICT_TYPE UUID := '00000000-0000-4000-a000-000000000006';
    ID_OBJECT_TYPE UUID := '00000000-0000-4000-a000-000000000001';

    ID_RANGE_TYPE UUID := '00000000-0000-4000-a000-000000000040';
    ID_RANGE_ITERATOR_TYPE UUID := '00000000-0000-4000-a000-000000000041';

    dict_range_id UUID := gen_random_uuid();
    dict_range_iter_id UUID := gen_random_uuid();
    bases_tuple_id UUID;
BEGIN
    -- Get shared (object,) tuple for tp_bases
    SELECT tp_bases INTO bases_tuple_id FROM public.py_type_object
    WHERE ob_base = ID_TYPE_TYPE LIMIT 1;

    -- Phase 1: py_object rows
    INSERT INTO public.py_object (id, ob_type) VALUES
        (ID_RANGE_TYPE, NULL),
        (ID_RANGE_ITERATOR_TYPE, NULL),
        (dict_range_id, NULL),
        (dict_range_iter_id, NULL);

    -- Phase 2: py_type_object rows
    INSERT INTO public.py_type_object (ob_base, tp_name) VALUES
        (ID_RANGE_TYPE, 'range'),
        (ID_RANGE_ITERATOR_TYPE, 'range_iterator');

    -- Phase 3: ob_type
    UPDATE public.py_object SET ob_type = ID_TYPE_TYPE
    WHERE id IN (ID_RANGE_TYPE, ID_RANGE_ITERATOR_TYPE);
    UPDATE public.py_object SET ob_type = ID_DICT_TYPE
    WHERE id IN (dict_range_id, dict_range_iter_id);

    -- Phase 4: dict objects
    INSERT INTO public.py_dict_object (ob_base) VALUES (dict_range_id), (dict_range_iter_id);

    -- Phase 5: tp_bases + tp_dict
    UPDATE public.py_type_object SET tp_bases = bases_tuple_id, tp_dict = dict_range_id
    WHERE ob_base = ID_RANGE_TYPE;
    UPDATE public.py_type_object SET tp_bases = bases_tuple_id, tp_dict = dict_range_iter_id
    WHERE ob_base = ID_RANGE_ITERATOR_TYPE;
END $$;

-- ============================================================================
-- 3. tp_iter for range → range_iterator
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_range_tp_iter(obj_id UUID)
RETURNS UUID AS $$
DECLARE
    ID_RANGE_ITERATOR_TYPE UUID := '00000000-0000-4000-a000-000000000041';
    v_start NUMERIC;
    v_stop NUMERIC;
    v_step NUMERIC;
    v_len NUMERIC;
    iter_id UUID;
BEGIN
    SELECT ob_start, ob_stop, ob_step INTO v_start, v_stop, v_step
    FROM public.py_range_object WHERE ob_base = obj_id;

    -- Compute length: max(0, ceil((stop - start) / step))
    IF v_step > 0 THEN
        v_len := GREATEST(0, ceil((v_stop - v_start)::numeric / v_step));
    ELSIF v_step < 0 THEN
        v_len := GREATEST(0, ceil((v_start - v_stop)::numeric / (-v_step)));
    ELSE
        PERFORM public.py_err_set_value_error('range() arg 3 must not be zero');
        RETURN NULL;
    END IF;

    iter_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (iter_id, ID_RANGE_ITERATOR_TYPE);
    INSERT INTO public.py_range_iterator_object (ob_base, it_start, it_stop, it_step, it_index, it_len)
    VALUES (iter_id, v_start, v_stop, v_step, 0, v_len);

    RETURN iter_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 4. tp_iternext for range_iterator
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_range_iterator_tp_iternext(iter_id UUID)
RETURNS UUID AS $$
DECLARE
    ID_INT_TYPE UUID := '00000000-0000-4000-a000-000000000004';
    v_start NUMERIC;
    v_step NUMERIC;
    v_index NUMERIC;
    v_len NUMERIC;
    v_value NUMERIC;
    result_id UUID;
BEGIN
    SELECT it_start, it_step, it_index, it_len INTO v_start, v_step, v_index, v_len
    FROM public.py_range_iterator_object WHERE ob_base = iter_id;

    IF v_index >= v_len THEN
        PERFORM public.py_err_set_stop_iteration();
        RETURN NULL;
    END IF;

    v_value := v_start + v_index * v_step;

    -- Create int object for the value
    result_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (result_id, ID_INT_TYPE);
    INSERT INTO public.py_long_object (ob_base, long_value) VALUES (result_id, v_value);

    -- Advance index
    UPDATE public.py_range_iterator_object SET it_index = v_index + 1 WHERE ob_base = iter_id;

    RETURN result_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. Register tp_iter / tp_iternext
-- ============================================================================
UPDATE public.py_type_object SET tp_iter = 'py_range_tp_iter'::regproc
WHERE ob_base = '00000000-0000-4000-a000-000000000040'; -- range

UPDATE public.py_type_object SET tp_iternext = 'py_range_iterator_tp_iternext'::regproc
WHERE ob_base = '00000000-0000-4000-a000-000000000041'; -- range_iterator

-- ============================================================================
-- 6. py_builtin_range: range(stop) or range(start, stop[, step])
-- METH_VARARGS (0x0001)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.py_builtin_range(
    func_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    ID_RANGE_TYPE UUID := '00000000-0000-4000-a000-000000000040';
    v_nargs INTEGER;
    v_start NUMERIC := 0;
    v_stop NUMERIC;
    v_step NUMERIC := 1;
    v_range_id UUID;
BEGIN
    v_nargs := COALESCE(array_length(args, 1), 0);

    IF v_nargs = 1 THEN
        -- range(stop)
        SELECT long_value INTO v_stop FROM public.py_long_object WHERE ob_base = args[1];
        IF v_stop IS NULL THEN
            PERFORM public.py_err_set_type_error('range() integer expected');
            RETURN NULL;
        END IF;
    ELSIF v_nargs = 2 THEN
        -- range(start, stop)
        SELECT long_value INTO v_start FROM public.py_long_object WHERE ob_base = args[1];
        SELECT long_value INTO v_stop FROM public.py_long_object WHERE ob_base = args[2];
        IF v_start IS NULL OR v_stop IS NULL THEN
            PERFORM public.py_err_set_type_error('range() integer expected');
            RETURN NULL;
        END IF;
    ELSIF v_nargs = 3 THEN
        -- range(start, stop, step)
        SELECT long_value INTO v_start FROM public.py_long_object WHERE ob_base = args[1];
        SELECT long_value INTO v_stop FROM public.py_long_object WHERE ob_base = args[2];
        SELECT long_value INTO v_step FROM public.py_long_object WHERE ob_base = args[3];
        IF v_start IS NULL OR v_stop IS NULL OR v_step IS NULL THEN
            PERFORM public.py_err_set_type_error('range() integer expected');
            RETURN NULL;
        END IF;
        IF v_step = 0 THEN
            PERFORM public.py_err_set_value_error('range() arg 3 must not be zero');
            RETURN NULL;
        END IF;
    ELSE
        PERFORM public.py_err_set_type_error('range expected 1 to 3 arguments, got ' || v_nargs);
        RETURN NULL;
    END IF;

    v_range_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (v_range_id, ID_RANGE_TYPE);
    INSERT INTO public.py_range_object (ob_base, ob_start, ob_stop, ob_step)
    VALUES (v_range_id, v_start, v_stop, v_step);

    RETURN v_range_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 7. Register range in __builtins__
-- ============================================================================
DO $$
DECLARE
    ID_RANGE_FUNCTION UUID := '00000000-0000-4000-b000-000000000006';
    ID_BUILTINS_MODULE UUID := '00000000-0000-4000-b000-000000000002';
    ID_BUILTIN_FUNCTION_OR_METHOD_TYPE UUID := '00000000-0000-4000-a000-000000000010';
    ID_STR_TYPE UUID := '00000000-0000-4000-a000-000000000003';

    builtins_dict_id UUID;
    str_name_id UUID;
    str_doc_id UUID;
BEGIN
    SELECT md_dict INTO builtins_dict_id
    FROM public.py_module_object WHERE ob_base = ID_BUILTINS_MODULE;

    str_name_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_name_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_name_id, 'range');

    str_doc_id := gen_random_uuid();
    INSERT INTO public.py_object (id, ob_type) VALUES (str_doc_id, ID_STR_TYPE);
    INSERT INTO public.py_unicode_object (ob_base, str_value) VALUES (str_doc_id, 'range(stop) -> range object');

    INSERT INTO public.py_object (id, ob_type) VALUES (ID_RANGE_FUNCTION, ID_BUILTIN_FUNCTION_OR_METHOD_TYPE);
    INSERT INTO public.py_cfunction_object (ob_base, m_ml_name, m_ml_flags, m_ml_doc, m_self, m_module, m_ml_meth)
    VALUES (ID_RANGE_FUNCTION, str_name_id, 1, str_doc_id, NULL, ID_BUILTINS_MODULE, 'py_builtin_range'::regproc);

    PERFORM public.py_dict_set_item(builtins_dict_id, str_name_id, ID_RANGE_FUNCTION);
END $$;
