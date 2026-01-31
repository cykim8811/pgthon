-- ============================================================================
-- Migration: COMPARE_OP Phase 1 — py_object_richcompare reflected op (CPython 고증)
-- Created: 2026-01-14 24:00:00
--
-- Purpose:
--   CPython PyObject_RichCompare: NotImplemented 시 other 쪽 tp_richcompare를
--   reflected op으로 시도한다. LT↔GT, LE↔GE, EQ/NE는 인자만 스왑.
--
-- Design: docs/COMPARE_OP_IMPLEMENTATION_PLAN.md
-- ============================================================================

CREATE OR REPLACE FUNCTION public.py_object_richcompare(
    self_id uuid, other_id uuid, op integer)
RETURNS uuid AS $$
DECLARE
    type_id uuid;
    other_type_id uuid;
    rcf regproc;
    res uuid;
    not_impl uuid := '00000000-0000-4000-b000-000000000012';
    reflected_op integer;
BEGIN
    -- 1) left(self_id)의 tp_richcompare(self_id, other_id, op) 시도
    SELECT ob_type INTO type_id FROM public.py_object WHERE id = self_id;
    IF type_id IS NULL THEN
        RETURN not_impl;
    END IF;
    SELECT tp_richcompare INTO rcf
    FROM public.py_type_object WHERE ob_base = type_id;
    IF rcf IS NULL THEN
        -- left에 슬롯 없음 → reflected 시도
        NULL;
    ELSE
        EXECUTE format('SELECT %I($1::uuid, $2::uuid, $3::integer)', rcf::text)
        USING self_id, other_id, op INTO res;
        IF res IS DISTINCT FROM not_impl THEN
            RETURN res;
        END IF;
    END IF;

    -- 2) NotImplemented → reflected op: other의 tp_richcompare(other_id, self_id, reflected_op)
    SELECT ob_type INTO other_type_id FROM public.py_object WHERE id = other_id;
    IF other_type_id IS NULL THEN
        RETURN not_impl;
    END IF;
    SELECT tp_richcompare INTO rcf
    FROM public.py_type_object WHERE ob_base = other_type_id;
    IF rcf IS NULL THEN
        RETURN not_impl;
    END IF;

    IF op IN (0, 1, 4, 5) THEN
        -- Py_LT(0)↔Py_GT(4), Py_LE(1)↔Py_GE(5)
        reflected_op := CASE op WHEN 0 THEN 4 WHEN 1 THEN 5 WHEN 4 THEN 0 WHEN 5 THEN 1 ELSE op END;
        EXECUTE format('SELECT %I($1::uuid, $2::uuid, $3::integer)', rcf::text)
        USING other_id, self_id, reflected_op INTO res;
    ELSE
        -- Py_EQ(2), Py_NE(3): 인자만 스왑, op 동일
        EXECUTE format('SELECT %I($1::uuid, $2::uuid, $3::integer)', rcf::text)
        USING other_id, self_id, op INTO res;
    END IF;

    RETURN res;
END;
$$ LANGUAGE plpgsql;
