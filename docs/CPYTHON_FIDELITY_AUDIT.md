# CPython 고증 검토 (Fidelity Audit)

Elytra 마이그레이션 구현이 CPython의 의미·구조와 얼마나 맞는지, 코드·설계 문서만 기준으로 점검한 결과입니다.  
(CPython 소스 검색 없이, 공개된 CPython 의미론·문서·프로젝트 내 주석을 기준으로 작성했습니다.)

---

## 1. 잘 맞는 부분 (고증 유지)

### 1.1 객체·타입 모델

| 항목 | CPython | Elytra | 비고 |
|------|---------|--------|------|
| 모든 객체가 PyObject | `PyObject` 공통 헤더, `ob_type`으로 타입 참조 | `py_object.id` + `ob_type` (uuid) | 정체성·참조를 단일 ID로 통일 ✅ |
| 타입도 객체 | `PyTypeObject` extends `PyObject` | `py_type_object.ob_base` = `py_object.id` (공유 PK) | ✅ |
| 상속 표현 | `tp_bases` (tuple of type*) | `tp_bases` → tuple 객체 id | ✅ |
| 타입별 __dict__ | `tp_dict` | `tp_dict` → dict 객체 id | ✅ |

### 1.2 타입 슬롯 사용 방식

| 항목 | CPython | Elytra | 비고 |
|------|---------|--------|------|
| 호출 가능 여부 | `Py_TYPE(obj)->tp_call` 존재 여부 | `py_type_object.tp_call` 조회 후 호출 | tp_call NULL → TypeError ✅ |
| 해시 가능 여부 | `Py_TYPE(obj)->tp_hash` 존재 여부 | `py_object_hash` 가 `tp_hash` 슬롯 호출 | tp_hash NULL → unhashable TypeError ✅ |
| 비교 | `tp_richcompare`, 반환 Py_True/Py_False/Py_NotImplemented | `tp_richcompare`, True/False/NotImplemented 객체 id | ✅ |
| 비교 op 상수 | Py_LT=0, Py_LE=1, Py_EQ=2, Py_NE=3, Py_GT=4, Py_GE=5 | 236000·237000에서 동일 정수 사용 | ✅ |
| len() 경로 | `PyObject_Size` → sq_length 우선, 없으면 mp_length | `py_object_size` 동일 순서 (sequence → mapping) | ✅ |

### 1.3 Dict lookup

| 항목 | CPython | Elytra | 비고 |
|------|---------|--------|------|
| 키 후보 좁히기 | entry->me_hash 활용 | `py_dict_entry.me_hash`, `(dict_id, me_hash)` 조회 | ✅ |
| 키 동등성 | `PyObject_RichCompareBool(me_key, key, Py_EQ)` | `py_object_richcompare_eq` (tp_richcompare 경유) | 236000부터 타입 이름 분기 없음 ✅ |
| NotImplemented 시 | 역방향 비교 시도 | `py_object_richcompare(b,a,Py_EQ)` 한 번 더 시도 | ✅ |
| insert 시 hash 저장 | `STORE_HASH(ep, hash)` | `INSERT ... me_hash = py_object_hash(key_id)` | ✅ |

### 1.4 VM·Frame·Opcode

| 항목 | CPython | Elytra | 비고 |
|------|---------|--------|------|
| 스택 기반 실행 | `f_valuestack` push/pop | `f_valuestack uuid[]` + `py_stack_push`/`py_stack_pop` | ✅ |
| f_lasti | 바이트 오프셋 | `f_lasti = i` (바이트 오프셋) | ✅ |
| RETURN_VALUE | 스택에서 pop한 값 반환 후 루프 종료 | 동일 | ✅ |
| instruction 크기 | 2바이트 (opcode 1 + operand 1) 기본 | `py_get_opcode_size` 기본 2 | ✅ |
| LOAD_CONST(100) | co_consts[arg] → stack | `co_consts` tuple `ob_item[arg+1]` → push | ✅ |
| LOAD_NAME(101) | locals → globals → builtins | `py_dict_get_item(f_locals)` → `f_globals` → `f_builtins` | ✅ |
| STORE_NAME(90) | stack pop → f_locals[name] | `py_dict_set_item(f_locals, name_str_id, value)` | ✅ |
| CALL_FUNCTION(141) | 호출 시 tp_call 경유 | `py_object_call(func_id, args)`만 사용, tp_call에 위임 | ✅ |

### 1.5 int hash 고증

| 항목 | CPython | Elytra (235000) | 비고 |
|------|---------|------------------|------|
| hash(-1) | -2 (에러 반환 -1과 구분) | `IF int_val = -1 THEN hash_value := -2` | ✅ |
| 작은 정수 | 값 그대로 등 | BIGINT 범위 내는 값 그대로 | ✅ |
| 큰 정수 | 일종의 modular reduction | `int_val % 2147483647` | 알고리즘은 CPython과 완전 동일하지는 않을 수 있음, "해시 가능 + 정수 semantics" 수준에서는 일치 |

### 1.6 Builtin·타입 슬롯 등록

| 항목 | CPython | Elytra | 비고 |
|------|---------|--------|------|
| PyCFunction_Type.tp_call | PyCFunction_Call | `tp_call = 'py_call_cfunction'::regproc` | ✅ |
| len() 구현 경로 | PyObject_Size | `py_object_size` (sq_length/mp_length 슬롯) | ✅ |
| METH_O 호출 규칙 | m_ml_flags & METH_O 시 인자 1개 | `py_call_cfunction`에서 `(ml_flags & 8) != 0` 시 인자 1개 | ✅ |

---

## 2. 의도적 축소·차이 (Minimal 원칙에 부합할 수 있음)

| 항목 | CPython | Elytra | 판단 |
|------|---------|--------|------|
| kwargs | `PyObject_Call(obj,args,kwargs)` | `py_object_call(obj_id, args)` 만 지원, kwargs 없음 | Minimal. 주석에 "나중에 kwargs 지원 가능" 명시 ✅ |
| dict 물리 구조 | dk_indices, perturb/probe 등 | 별도 구현 없음, hash+equality 의미만 유지 (DICT_LOOKUP_DESIGN §4) | 설계에서 "의미만 고증"으로 명시 ✅ |
| str hash 알고리즘 | SipHash 등 (버전별 상이) | `hashtext()` | "같은 문자열이면 같은 해시" 만족, 비트 단위 동일성은 불요 ✅ |
| tuple/bytes/float/bool/None hash | 모두 hashable, 각자 tp_hash 또는 상속 | **tp_hash 등록은 str, int만** (235000) | 아래 "고증 격차" 항으로 이동 권장 |

---

## 3. 고증 격차 또는 원칙 위반 가능성

### 3.1 abs()에 대한 타입 이름 분기 — ✅ 해결됨

- **CPython**: `builtin_abs` → `PyNumber_Absolute(obj)` → **tp_as_number->nb_absolute** 슬롯.
- **Elytra**: 235500에서 `py_number_methods`·`tp_as_number` 도입, `py_builtin_abs`는 `py_object_absolute`(슬롯 경유)만 호출. tp_name 분기 제거됨.

### 3.2 Hashable 타입 확장 — ✅ 해결됨

- **CPython**: tuple, bytes, float, bool, None은 (조건부 포함) hashable.  
  - tuple: 원소가 모두 hashable이면 hashable.  
  - bool: hash(True)==1, hash(False)==0.  
  - None: hashable.
- **Elytra**: 235800 `tp_hash_extended`에서 **bytes, float, bool, NoneType, tuple**에 tp_hash 등록.  
  - 타입별 함수: `py_bytes_hash`, `py_float_hash`, `py_bool_hash`, `py_none_hash`, `py_tuple_hash`.  
  - tuple은 원소마다 `py_object_hash` 호출로 "원소가 unhashable이면 TypeError" 의미 유지.  
  - 판별은 구체 테이블 존재 여부만 사용, tp_name 분기 없음.  
  - 계획: docs/CHANGE_2_TP_HASH_EXTENDED_PLAN.md.

### 3.3 py_object_equals_key의 tp_name 분기 (역할 축소됨)

- 235000의 `py_object_equals_key`는 **tp_name으로 str/int 구분** 후 값 비교.
- 236000에서 `py_dict_get_item` / `py_dict_set_item`는 **py_object_richcompare_eq**만 사용하도록 바뀜.

따라서 **dict 키 동등성**은 이미 슬롯(tp_richcompare) 기반으로 이전된 상태이고, `py_object_equals_key`는 dict 경로에서는 쓰이지 않습니다.  
다만 동일 함수가 다른 경로(테스트·레거시 호출)에서 남아 있다면, 그 경로는 여전히 tp_name 분기에 의존한다고 보는 게 맞습니다.  
"dict는 오직 py_object_richcompare_eq"라고 설계가 정리되어 있으므로, 고증상의 문제는 dict 쪽이 아니라 **py_object_equals_key를 쓰는 다른 코드가 있다면** 그쪽에만 해당합니다.

### 3.4 int hash "큰 정수" — 알려진 차이

- **CPython**: `PyLong` 해시는 큰 정수에 대해 정해진 reduction 규칙을 사용합니다.
- **Elytra**: BIGINT 범위 밖이면 `int_val % 2147483647` 등으로 **단순화**해 두었습니다.

→ 해시값이 CPython과 비트 단위로 같을 필요는 설계에 없으나, **알려진 차이**로 둡니다.

### 3.5 tp_call 시그니처 — 반영 완료 + 알려진 차이

- **CPython**: `ternaryfunc tp_call(PyObject *callable, PyObject *args, PyObject *kwargs)`.
- **Elytra**: 234500에서 **tp_call 시그니처를 (obj_id, args, kwargs_id) 3인자 규약**으로 반영했습니다.  
  - `py_call_cfunction(obj_id, args, kwargs_id DEFAULT NULL)`, `py_object_call(obj_id, args, kwargs_id DEFAULT NULL)`  
  - tp_call 슬롯 함수는 항상 3인자로 호출되며, METH_O/NOARGS/VARARGS에서 kwargs가 넘어오면 `TypeError: 'name'() takes no keyword arguments` 반환.

**알려진 차이**: kwargs를 **실제로 넘겨서 쓰는** bytecode(CALL_FUNCTION_KW 등)는 아직 없습니다.  
CALL_FUNCTION은 `py_object_call(..., NULL)`만 사용하며, "kwargs를 쓰는 호출"은 미구현 상태로 둡니다.

---

## 4. 정리

- **객체/타입 모델, 타입 슬롯(tp_call/tp_hash/tp_richcompare) 사용 방식, dict lookup의 hash+동등성, VM·frame·기본 opcode 의미**는 CPython 고증에 잘 맞게 구현되어 있습니다.
- **의도적 축소**(dict 내부 구조 단순화, str hash 알고리즘 차이)는 Minimal·설계 문서와 양립 가능합니다.
- **고증·원칙 관련 조치 현황**:
  1. **abs()** — 235500에서 **nb_absolute** 슬롯 경유로 전환 완료. 타입 이름 분기 제거됨.
  2. **hashable 범위** — 235800에서 tuple/bytes/float/bool/None에 tp_hash 등록 완료. CPython과 동일 범위로 확장됨.
  3. **tp_call 시그니처** — 234500에서 (obj_id, args, kwargs_id) 3인자 규약 반영 완료.  
     **알려진 차이**로만 남긴 항목: **int 큰 정수 해시 공식 단순화**(§3.4), **kwargs를 넘기는 bytecode(CALL_FUNCTION_KW 등) 미구현**(§3.5).

이 문서는 추후 CPython 버전을 참조한 구체적 대조가 이뤄질 때, 같은 포맷으로 "고증 유지 / 의도적 축소 / 격차"를 업데이트하는 데 쓰면 됩니다.
