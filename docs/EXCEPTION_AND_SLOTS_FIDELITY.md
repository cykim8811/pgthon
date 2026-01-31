# 검토 대상 항목의 CPython 고증 정리

예외 처리·슬롯·dict·tuple 관련 “검토해볼만한 부분”에 대해, **CPython 고증을 지킬 때 수정이 필요한지, 유지해도 되는지**를 정리한다.

---

## 1. 슬롯 내부의 “TypeError”용 RAISE EXCEPTION

**현재:** `py_unicode_hash`, `py_long_hash`, `py_bytes_hash` 등에서 “non-string object”, “non-integer object” 등으로 **PL/pgSQL RAISE EXCEPTION** 사용.

**CPython:** 슬롯 함수(tp_hash, nb_add 등)는 “해당 타입으로 이미 디스패치된 뒤” 호출된다. 그럼에도 잘못된 타입이 들어오면(버그/불변식 위반) CPython은 **Python 예외**를 설정한다. 즉 `PyErr_Format(PyExc_TypeError, ...)` 후 -1/NULL 반환. 별도의 “C abort”나 비-Python 오류 경로를 두지 않는다.

**고증 결론:**  
- **수정하는 것이 맞다.**  
- TypeError는 설계 원칙대로 **`py_err_set_type_error` + exception table unwinding** 한 경로로 통일하는 것이 CPython과 일치한다.  

**조치 완료:**  
- tp_hash 슬롯 함수 8곳(`py_unicode_hash`, `py_long_hash`, `py_bytes_hash`, `py_float_hash`, `py_bool_hash`, `py_none_hash`, `py_tuple_hash` 및 `py_long_hash` 내 “integer object has no value”)에서 `RAISE EXCEPTION 'TypeError: ...'` 대신 `PERFORM py_err_set_type_error('...'); RETURN NULL;` 로 변경함.  
- 호출자 `py_object_hash`는 슬롯 반환값을 그대로 반환하므로, 슬롯이 NULL을 반환하면 NULL이 전파되고, dict 등은 이미 `h IS NULL AND py_err_occurred()` 로 처리함.

---

## 2. py_object_equals_key (tp_name으로 str/int만 분기) — **제거 완료**

**과거:** `py_object_equals_key(a_id, b_id)`가 `tp_name`으로 str/int만 처리. dict는 이미 `py_object_richcompare_eq`만 사용 중이었음.

**조치:** `py_object_equals_key` 함수를 235000에서 제거함. dict 키 동등성은 `py_object_richcompare_eq`(tp_richcompare)만 사용. 테스트 18은 `py_object_richcompare_eq`로 동일 시나리오 검증하도록 수정함.

---

## 3. tuple 타입을 tp_name = 'tuple'로 조회

**현재:** `py_tuple_from_3`, `py_tuple_from_1` 등에서  
`SELECT ob_base INTO tuple_type_id FROM public.py_type_object WHERE tp_name = 'tuple' LIMIT 1` 로 tuple 타입을 얻음.

**CPython:** tuple 타입은 **정적 전역 `PyTuple_Type`**(&PyTuple_Type). 이름으로 런타임 조회하지 않는다. PyTuple_New() 등은 이 타입 객체를 직접 참조한다.

**고증 결론:**  
- **수정하는 것이 맞다.**  
- 부트스트랩에 이미 tuple 타입 고정 UUID가 있다(`20260114223000_python_bootstrap.sql`의 `ID_TUPLE_TYPE := '00000000-0000-4000-a000-000000000007'`).  
- **권장:** `py_tuple_from_3` / `py_tuple_from_1` 등에서 `tp_name = 'tuple'` 조회를 제거하고, tuple 타입 UUID 상수(`'00000000-0000-4000-a000-000000000007'`)를 사용하도록 변경.  
- 효과: tp_name 문자열에 대한 의존 제거, CPython의 “타입 객체를 상수로 참조”하는 방식과 맞춤.

---

## 요약 표

| 항목 | CPython 관점 | 결론 | 우선순위 |
|------|----------------|------|----------|
| 슬롯 내부 TypeError를 RAISE EXCEPTION | TypeError는 PyErr_* 한 경로 | **수정 완료** (tp_hash 슬롯 8곳) | — |
| py_object_equals_key (tp_name 분기) | 키 동등성은 RichCompareBool만 사용 | **제거 완료** | — |
| tuple 타입 tp_name 조회 | PyTuple_Type 상수 참조 | **수정:** 부트스트랩 tuple UUID 상수 사용 | 중간 (의존성·고증) |

이 문서는 “검토해볼만한 부분”에 대한 **고증 기준 정리**만 담는다. 실제 수정은 별도 작업으로 진행하면 된다.
