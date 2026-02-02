# Bound Method 설계 — CPython 고증·임시구현 없음

CPython의 **bound method** 동작(인스턴스에서 메서드 속성 조회 시 `obj.method` → 호출 가능한 bound method 객체, `obj.method()` 시 `self`가 자동 전달)을 Elytra에서 구현하기 위한 설계 문서다.  
**임시방편 금지**: `tp_name`/타입 이름 문자열로 분기하지 않고, **테이블 존재·tp_dict·tp_call·디스크립터 프로토콜**만 사용한다.

---

## 1. CPython 고증 요약

### 1.1 Bound Method가 나오는 경로

- **속성 조회**: `getattr(instance, "method")` 시, `"method"`가 타입(또는 MRO)의 `tp_dict`에 있고 그 값이 **디스크립터**(`__get__` 보유)이면 `descriptor.__get__(method, instance, type)`이 호출된다.
- **함수는 디스크립터**: CPython에서 함수 객체는 `__get__`를 갖는다. `function.__get__(self, obj, type=None)` 호출 시:
  - **obj is not None** (인스턴스에서 조회): `PyMethod_New(self, obj)` → **bound method** 반환. bound method 호출 시 `func(instance, *args, **kwargs)`로 전달된다.
  - **obj is None** (클래스에서 조회): 함수 자체를 그대로 반환한다. (Python 3에서는 unbound method 객체 없음.)

### 1.2 PyMethodObject / types.MethodType

- **구조**: `im_func`(호출 가능 객체), `im_self`(바인딩된 인스턴스, NULL이면 unbound), `im_class`(정의된 클래스).
- **호출**: bound method를 호출하면 CPython은 `im_func(im_self, *args, **kwargs)`를 실행한다. 즉 인자 앞에 `im_self`를 붙여서 `im_func`의 `tp_call`을 호출한다.

### 1.3 Elytra에서 이미 있는 것

- **py_method_object** 테이블: `ob_base`, `im_func`, `im_self`, `im_class` — 이미 스키마 존재 (224000).
- **LOAD_ATTR / lookup_in_type_and_bases**: 타입·bases에서 name 조회 후, 조회된 값의 타입에 `__get__`가 있으면 `__get__(attr, obj, type)` 호출 후 그 결과를 반환. **따라서** `builtin_function_or_method` 타입의 `tp_dict`에 `"__get__"`만 넣어 주면, 인스턴스에서 해당 타입의 속성을 꺼낼 때 자동으로 그 `__get__`가 호출된다.
- **py_object_call**: `tp_call` 슬롯으로 디스패치. bound method의 **타입**에 `tp_call`을 등록하면, bound method를 호출할 때 그 함수가 실행된다.

### 1.4 Elytra에서 추가할 것 (요약)

| 항목 | 내용 |
|------|------|
| **method 타입** | bound method 객체의 타입(PyTypeObject). 인스턴스는 `py_method_object` 행. 고정 UUID로 부트스트랩 또는 단일 마이그레이션에서 생성. |
| **method 타입의 tp_call** | `py_method_tp_call(method_obj_id, args, kwargs_id)`: `py_method_object`에서 `im_func`, `im_self` 조회 → `new_args = [im_self] || args` → `py_object_call(im_func, new_args, kwargs_id)` 반환. |
| **builtin_function_or_method의 __get__** | `(func_id, obj_id, type_id)` 인자로 호출되는 callable. `obj_id IS NULL`이면 `func_id` 그대로 반환. 아니면 새 `py_method_object` 생성(ob_type = method 타입, im_func=func_id, im_self=obj_id, im_class=type_id) 후 그 id 반환. |
| **타입 판별** | `py_object`, `py_type_object`, `py_method_object`, `py_dict_get_item`, 테이블 존재만 사용. `tp_name` 비교 금지. |

---

## 2. 현재 Elytra 상태

| 항목 | 상태 |
|------|------|
| `py_method_object(ob_base, im_func, im_self, im_class)` | ✅ 224000에 정의 |
| `lookup_in_type_and_bases` (타입+bases, 발견 시 `__get__` 호출) | ✅ 235000 |
| `py_object_getattr` (인스턴스 __dict__ → 타입+bases, 디스크립터 __get__ 호출) | ✅ 235000 |
| `py_object_call` (tp_call 디스패치) | ✅ 234000 |
| **method 타입** (PyTypeObject for method objects) | ❌ 없음 |
| **method 타입의 tp_call** | ❌ 없음 |
| **builtin_function_or_method 타입의 tp_dict["__get__"]** | ❌ 없음 (현재 해당 tp_dict에 __get__ 미등록) |

- **결론**: method 타입 생성·tp_call 등록, 그리고 builtin_function_or_method의 `__get__` 구현(및 tp_dict 등록)만 하면 된다. LOAD_ATTR/속성 조회 경로는 수정할 필요 없음.

---

## 3. 구현 설계 (임시방편 없음)

### 3.1 method 타입 생성

- **위치**: 기존 부트스트랩에 “method 타입”을 넣지 않고, **한 번에 method 타입 + tp_call + __get__** 을 넣는 단일 마이그레이션이 유리. (부트스트랩은 이미 복잡하므로, 235000 이후 마이그레이션에서 처리 권장.)
- **내용**:
  - `py_object` 1행: id = method 타입용 고정 UUID (예: `00000000-0000-4000-a000-000000000030` 등 미사용 구간), ob_type = type 타입 id.
  - `py_type_object` 1행: ob_base = 위 id, tp_name = `'method'`(또는 `'builtin_method'` 등), tp_bases = (object,) 튜플 id, tp_dict = 빈 dict 또는 최소 dict id.
  - method 타입의 **tp_call** 컬럼에 `py_method_tp_call` 등록.

### 3.2 py_method_tp_call(method_obj_id uuid, args uuid[], kwargs_id uuid) RETURNS uuid

- **1)** `method_obj_id`에 해당하는 `py_method_object` 행이 있는지 확인. 없으면 TypeError(not callable 등) 설정 후 NULL 반환.
- **2)** 해당 행에서 `im_func`, `im_self` 조회. `im_self`가 NULL이면( unbound ) 동작은 선택: CPython 3에서는 보통 bound 만 사용하므로, 여기서는 bound 만 지원해도 됨. 필요 시 unbound 호출 시 TypeError.
- **3)** `new_args := array_prepend(im_self, args)`.
- **4)** `return py_object_call(im_func, new_args, kwargs_id)`.
- **타입 판별**: `py_method_object` 테이블 존재·행 조회만 사용. `tp_name` 비교 금지.

### 3.3 builtin_function_or_method의 __get__ 구현

- **시맨틱**: CPython의 `PyCFunction_Type.tp_descr_get` 또는 함수의 `__get__`와 동일. 인자 3개: (descriptor_self, obj, type).
- **호출 경로**: 이미 `lookup_in_type_and_bases`에서 attr 타입의 tp_dict에 `"__get__"`가 있으면 `py_object_call(get_id, ARRAY[attr_id, obj_id, type_id], NULL)` 호출. 따라서 **attr_id = builtin 함수 객체**, **obj_id = getattr의 첫 인자(인스턴스 또는 NULL)**, **type_id = type(obj)**.
- **동작**:
  - `obj_id IS NULL` → 클래스에서 조회한 경우. `func_id`(attr_id) 그대로 반환.
  - `obj_id IS NOT NULL` → 인스턴스에서 조회. 새 bound method 생성: `py_object` 1행(ob_type = method 타입 id), `py_method_object` 1행(ob_base = 새 id, im_func = attr_id, im_self = obj_id, im_class = type_id). 이 id 반환.
- **구현 형태**: METH_VARARGS builtin `py_builtin_function_descriptor_get(func_obj_id, args)`로 구현 가능. `args = [attr_id, obj_id, type_id]`. 내부에서 위 로직 수행. 이 builtin을 **builtin_function_or_method 타입의 tp_dict**에 `"__get__"` 키로 넣는다. (해당 타입의 tp_dict는 부트스트랩에서 이미 생성되어 있으므로, 마이그레이션에서 `py_dict_set_item(tp_dict_id, py_str_from_text('__get__'), builtin_id)` 한 번 호출하면 됨.)

### 3.4 임시방편 금지 체크리스트

- [ ] 타입/객체 판별: **테이블 존재·ob_type·py_method_object·py_dict_get_item**만 사용. `tp_name = '...'` 분기 금지.
- [ ] `"__get__"` 사용: **py_str_from_text('__get__')** 또는 상수 str id만 사용.
- [ ] method 타입 UUID: 고정 UUID 상수로 한 곳에서만 참조. 다른 타입과 충돌하지 않는 구간 사용.

---

## 4. 작업 ID·의존관계·실행 순서

### 4.1 작업 ID 정의

| ID | 작업 | 산출물 |
|----|------|--------|
| **M1** | method 타입 생성 (py_object + py_type_object, tp_bases, tp_dict) | 235000 또는 새 마이그레이션(기존 수정 원칙에 따라 235000 수정 권장) |
| **M2** | py_method_tp_call(method_obj_id, args, kwargs_id) 정의 | M1과 동일 마이그레이션 |
| **M3** | method 타입에 tp_call = py_method_tp_call 등록 | M2 직후, 동일 마이그레이션 |
| **M4** | py_builtin_function_descriptor_get(func_obj_id, args) 정의 (METH_VARARGS) | 235000 (이미 METH_VARARGS·py_dict_set_item 있음) |
| **M5** | __get__ builtin 객체 생성 및 builtin_function_or_method의 tp_dict에 등록 | 235000, M4 직후 |
| **M6** | Bound Method 통합 테스트: 인스턴스에서 메서드 조회 → bound method, 호출 시 self 전달 | supabase/tests/, run_tests.sh Phase 45 |

### 4.2 의존 관계

- **M1** → **M2**: method 타입이 있어야 tp_call 함수에서 “method 타입 id”를 상수로 참조 가능(새 인스턴스 생성은 M4에서 사용).
- **M2** → **M3**: tp_call 함수가 있어야 tp_call 슬롯에 등록 가능.
- **M1** → **M4**: py_builtin_function_descriptor_get에서 bound method 생성 시 ob_type = method 타입 id 필요.
- **M4** → **M5**: __get__ builtin 객체가 있어야 tp_dict에 넣을 수 있음.
- **M3, M5** → **M6**: method 타입 tp_call과 __get__ 등록이 끝나야, 테스트에서 LOAD_ATTR → bound method → CALL_FUNCTION 전체 경로 검증 가능.

### 4.3 실행 순서 (가장 먼저 실행할 것부터)

| 순서 | 작업 | 선행 | 비고 |
|------|------|------|------|
| 1 | **M1** method 타입 생성 | 없음 | 235000: py_object + py_type_object, tp_bases=(object,), tp_dict=빈 dict |
| 2 | **M2** py_method_tp_call 정의 | M1 | 235000: im_func, im_self 조회 → array_prepend(im_self, args) → py_object_call(im_func, new_args, kwargs_id) |
| 3 | **M3** method 타입에 tp_call 등록 | M2 | 235000: UPDATE py_type_object SET tp_call = 'py_method_tp_call' WHERE ob_base = method_type_id |
| 4 | **M4** py_builtin_function_descriptor_get 정의 | M1 | 235000: obj_id NULL이면 func_id 반환, 아니면 py_method_object 행 생성 후 id 반환 (ob_type = method_type_id) |
| 5 | **M5** __get__ builtin 생성 및 builtin_function_or_method tp_dict에 등록 | M4 | 235000: PyCFunction 행 생성(METH_VARARGS), py_dict_set_item(tp_dict, "__get__", builtin_id) |
| 6 | **M6** Bound Method 통합 테스트 | M3, M5 | 테스트 파일 추가, run_tests.sh Phase 45 |

### 4.4 마이그레이션 배치

- **원칙**: 기존 마이그레이션을 코드처럼 관리. 새 migration 파일 생성보다 **기존 235000 (tp_hash_slot.sql) 수정**으로 진행.
- **235000에 넣을 내용**:
  - method 타입용 고정 UUID, py_object 1행, py_type_object 1행 (tp_bases, tp_dict는 기존 object 타입의 tp_bases 재사용, tp_dict는 빈 dict 새로 생성).
  - `py_method_tp_call` 함수 정의.
  - method 타입의 tp_call 컬럼 UPDATE.
  - `py_builtin_function_descriptor_get` 함수 정의 (METH_VARARGS).
  - __get__ builtin용 PyCFunction 객체 생성(고정 UUID), builtin_function_or_method의 tp_dict에 `"__get__"` 키로 등록.

### 4.5 테스트 (M6) 요약

- 타입 T에 tp_dict["f"] = len (또는 다른 builtin) 설정. T 인스턴스 obj 생성.
- 바이트코드: LOAD_CONST(obj), LOAD_ATTR("f") → 스택에 bound method 1개.
- 바이트코드: LOAD_CONST(인자), CALL_FUNCTION(1) → bound method 호출. len(obj, 인자)가 아니라 **len(인자)** 가 호출되도록 하려면, 실제로는 “인자 1개 받는 builtin”을 쓰거나, “obj를 첫 인자로 받는 가상 메서드”를 두고 그게 호출되는지 확인.
- 더 단순한 검증: LOAD_ATTR("f") 결과가 **py_method_object** 행을 갖는지, im_self = obj, im_func = len 인지 확인. 그 다음 CALL_FUNCTION(0) 또는 CALL_FUNCTION(1)로 호출했을 때 예외 없이 호출되는지·반환값이 기대와 맞는지 확인.

---

## 5. 요약

| 단계 | 내용 | 산출물 |
|------|------|--------|
| 1 | method 타입 생성 (py_object + py_type_object) | 235000 |
| 2 | py_method_tp_call 정의 및 method 타입에 tp_call 등록 | 235000 |
| 3 | py_builtin_function_descriptor_get 정의, __get__ builtin 생성·tp_dict 등록 | 235000 |
| 4 | Bound Method 통합 테스트 | supabase/tests/, run_tests.sh Phase 45 |

**CPython 고증**: 인스턴스에서 함수 속성 조회 시 해당 함수의 `__get__(func, obj, type)` 호출 → bound method 반환. bound method 호출 시 `im_func(im_self, *args, **kwargs)`.  
**임시구현 없음**: tp_name 분기 없이, 테이블·tp_dict·tp_call·py_method_object·py_dict_set_item·py_object_call만 사용.

---

## 6. 세부 작업 분해 및 의존 관계 (실행 순서)

아래는 **가장 먼저 실행해야 하는 것**부터 번호를 매긴 세부 작업 목록이다. 각 항목은 선행 작업이 완료된 뒤에만 실행 가능하다.

### 6.1 세부 작업 목록

| # | 작업 ID | 세부 내용 | 선행 | 산출물/위치 |
|--|--------|-----------|------|-------------|
| 1 | **M1-a** | method 타입용 고정 UUID 확정 (기존 타입 UUID와 충돌 없음) | 없음 | 상수 정의 |
| 2 | **M1-b** | method 타입용 빈 dict 생성 (py_object + py_dict_object) | 없음 | 235000 |
| 3 | **M1-c** | method 타입용 py_object 1행 INSERT (ob_type = type 타입 id) | M1-a | 235000 |
| 4 | **M1-d** | method 타입용 py_type_object 1행 INSERT (tp_name, tp_bases=(object,), tp_dict=M1-b) | M1-b, M1-c | 235000 |
| 5 | **M2-a** | py_method_tp_call(method_obj_id, args, kwargs_id) 함수 정의 (im_func, im_self 조회 → array_prepend(im_self, args) → py_object_call(im_func, new_args, kwargs_id)) | M1-d | 235000 |
| 6 | **M3-a** | method 타입의 tp_call 컬럼에 'py_method_tp_call'::regproc UPDATE | M2-a | 235000 |
| 7 | **M4-a** | py_builtin_function_descriptor_get(func_obj_id, args) 함수 정의: args = [attr_id, obj_id, type_id]; obj_id IS NULL이면 attr_id 반환, 아니면 새 py_object + py_method_object INSERT (ob_type = method 타입 id), 그 id 반환 | M1-d | 235000 |
| 8 | **M5-a** | __get__ builtin용 PyCFunction 객체 생성 (METH_VARARGS, m_ml_meth = py_builtin_function_descriptor_get), 고정 UUID 사용 | M4-a | 235000 |
| 9 | **M5-b** | builtin_function_or_method 타입의 tp_dict 조회 후 py_dict_set_item(tp_dict_id, py_str_from_text('__get__'), M5-a의 builtin id) | M5-a | 235000 |
| 10 | **M6-a** | Bound Method 통합 테스트 파일 생성 (supabase/tests/45_bound_method_integration.sql) | M3-a, M5-b | supabase/tests/ |
| 11 | **M6-b** | run_tests.sh에 Phase 45로 45_bound_method_integration.sql 등록 | M6-a | run_tests.sh |

### 6.2 의존 관계 다이어그램 (선행 → 후행)

```
M1-a ──┬──→ M1-c ──→ M1-d ──┬──→ M2-a ──→ M3-a ──┬──→ M6-a ──→ M6-b
       │                    │                    │
M1-b ──┴──→ M1-d            │                    │
                            ├──→ M4-a ──→ M5-a ──→ M5-b ──┘
                            │
                            └──→ M4-a (method 타입 id 참조)
```

### 6.3 가장 먼저 실행할 순서 (체크리스트)

1. **M1-a** · **M1-b**: UUID 상수 확정, method 타입용 빈 dict 생성.
2. **M1-c** · **M1-d**: method 타입 py_object + py_type_object INSERT.
3. **M2-a**: py_method_tp_call 정의.
4. **M3-a**: method 타입에 tp_call 등록.
5. **M4-a**: py_builtin_function_descriptor_get 정의.
6. **M5-a** · **M5-b**: __get__ builtin 객체 생성 및 builtin_function_or_method의 tp_dict에 등록.
7. **M6-a** · **M6-b**: 통합 테스트 파일 작성 및 run_tests.sh Phase 45 등록.
