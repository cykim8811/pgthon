# STORE_ATTR / 속성 저장 설계 — CPython 고증·임시구현 없음

CPython의 **STORE_ATTR** opcode 및 **PyObject_SetAttr**에 해당하는 속성 저장을 Elytra에서 구현하기 위한 설계 문서다.  
**임시방편 금지**: `tp_name`/타입 이름 문자열로 분기하지 않고, **테이블 존재·tp_dict·디스크립터 프로토콜**만 사용한다.

---

## 1. CPython 고증 요약

### 1.1 STORE_ATTR opcode

| 항목 | CPython | Elytra 대응 |
|------|--------|-------------|
| **opcode** | STORE_ATTR (Python 3.10 기준 opcode **95**) | opcode 95 처리 |
| **operand** | name index → `co_names[namei]` (속성 이름 str) | `name_index` → co_names[name_index]로 이름 str id 획득 |
| **스택** | TOS = owner(객체), SECOND = value. 둘 다 pop 후 `setattr(owner, name, value)` 호출. | pop obj (TOS) → pop value (SECOND) → `py_object_setattr(obj_id, name_str_id, value_id)` |
| **실패** | AttributeError 등 | `py_err_set_attribute_error` 등 후 NULL/실패 반환·전파 |

- CPython ceval.c: `PyObject_SetAttr(owner, name, v)` 호출. 스택은 TOP=owner, SECOND=v 이므로 STACK_SHRINK(2) 후 호출.

### 1.2 PyObject_SetAttr / setattr(obj, name, value)

- **순서** (CPython): `type(obj).__setattr__(obj, name, value)` 의 일반 경로는 대략:
  1. **MRO에서 해당 이름의 data descriptor** (타입에 `__set__` 있는 것) 조회 → 있으면 `descriptor.__set__(obj, value)` 호출 후 종료.
  2. 그렇지 않으면 **인스턴스 `__dict__`** 에 저장: `obj.__dict__[name] = value`. (인스턴스에 `__dict__`가 없거나 읽기 전용이면 에러.)

- **Elytra 범위** (의도적 축소 포함):
  - **타입·bases**: LOAD_ATTR과 동일하게 **단순 tp_bases 순회**만 사용 (MRO/C3 미사용).
  - **디스크립터**: 타입(또는 bases)의 tp_dict에서 name으로 조회한 값이 **`__set__`** 를 가지면 `descriptor.__set__(obj, value)` 호출. (인자 2개: self, value; CPython은 `__set__(self, obj, value)`.)
  - **인스턴스 __dict__**: descriptor가 없으면 `py_instance_object.in_dict`에 `py_dict_set_item(in_dict, name_str_id, value_id)`. 인스턴스에 `py_instance_object` 행이 없거나 `in_dict`가 NULL이면 **최초 저장 시 빈 dict 생성 후 in_dict로 설정** (CPython의 “인스턴스에 __dict__ 있음”에 대응).
  - **타입 판별**: `py_type_object`·`py_instance_object`·`tp_dict`·`py_dict_get_item`만 사용. `tp_name` 비교 금지.

### 1.3 디스크립터 프로토콜 (쓰기)

- `descriptor.__set__(self, obj, value)`  
  - CPython: 인자 3개 (self, obj, value).  
  - Elytra: `py_object_call(__set__id, [descriptor_id, obj_id, value_id], NULL)` 로 호출.
- “`__set__`가 있다”의 판별: **타입(또는 bases)의 tp_dict에서 name으로 조회한 값(descriptor)** 의 타입에 대해, 그 타입의 `tp_dict`에 `"__set__"` 키로 뭔가 들어있는지로만 판단. (타입 이름 분기 금지.)

### 1.4 실패 시

- descriptor가 없고 인스턴스 __dict__도 쓸 수 없으면(예: 해당 객체가 인스턴스가 아니고 타입도 descriptor 없음) → **AttributeError**.
- Elytra: 기존 `py_err_set_attribute_error(message)` 사용.

---

## 2. 현재 Elytra 상태

| 항목 | 상태 |
|------|------|
| `py_instance_object(ob_base, in_dict)` | ✅ 220000에 정의 |
| `py_dict_set_item` | ✅ 235000에서 hash·동등성 기반 |
| `lookup_in_type_and_bases` | ✅ 235000 (Phase 2 LOAD_ATTR) |
| `py_object_call` | ✅ 존재 |
| `py_str_from_text` | ✅ (예: `"__set__"` str 생성 가능) |
| **py_object_setattr** | ❌ 없음 |
| **STORE_ATTR(95)** | ❌ 없음 |

- **결론**: 기존 스키마·함수만 사용하고, `py_object_setattr`, `py_opcode_STORE_ATTR` 추가, eval_frame·예외 디스패치에 95 분기 추가.

---

## 3. 구현 설계 (임시방편 없음)

### 3.1 py_object_setattr(obj_id uuid, name_str_id uuid, value_id uuid) RETURNS boolean (또는 void / 정수 성공 실패)

- **1)** `obj_id`의 `ob_type` → type_id. type_id에 해당하는 `py_type_object` 행이 없으면 에러.
- **2)** 타입·bases에서 name **조회** (디스크립터 여부 확인용): `lookup_in_type_and_bases`와 동일한 순서로 type_id의 tp_dict, 그 다음 tp_bases DFS. **조회만** 하고, 찾은 항목이 **`__set__`** 를 가지면 descriptor로 처리.
- **3)** 타입(또는 bases)의 tp_dict에서 `name_str_id`로 조회 → `attr_id`.  
  - `attr_id`의 타입에 `"__set__"` 이 있으면: `py_object_call(__set__id, [attr_id, obj_id, value_id], NULL)` 호출. 성공 시 TRUE 반환, 실패(예외 설정) 시 FALSE/NULL 반환.  
  - `__set__` 이 없으면 4로.
- **4)** 인스턴스 __dict__ 경로: `py_instance_object`에서 `ob_base = obj_id`인 행 조회.  
  - **4a)** 행이 없음: 새 dict 객체 생성, `py_instance_object(ob_base=obj_id, in_dict=new_dict_id)` INSERT. `py_dict_set_item(new_dict_id, name_str_id, value_id)` 호출. 성공 시 TRUE 반환.  
  - **4b)** 행이 있으나 `in_dict` IS NULL: 새 dict 생성, 해당 행의 `in_dict` UPDATE. `py_dict_set_item(in_dict, name_str_id, value_id)` 호출. 성공 시 TRUE 반환.  
  - **4c)** 행이 있고 `in_dict` NOT NULL: `py_dict_set_item(in_dict, name_str_id, value_id)` 호출. 성공 시 TRUE 반환.  
- **5)** 2에서 타입·bases에 name이 없고, 4에서 인스턴스가 아님(예: 내장 타입 인스턴스가 아닌 경우): `py_instance_object`에 행이 없으면 “인스턴스가 아님”으로 간주하고 4a로 가서 **인스턴스 행+dict 생성**을 하면, “모든 객체에 __dict__ 부여”가 되어 CPython과 다름. 따라서 **객체가 “인스턴스”인지** 구분 필요.  
  - **정의**: `py_instance_object`에 `ob_base = obj_id`인 행이 **이미 있는** 객체만 “인스턴스”로 본다. 행이 없으면 “인스턴스가 아님” → descriptor도 없으면 AttributeError.  
  - 즉, 2→3에서 descriptor 없고, 4에서 `py_instance_object` 행이 없으면 → `py_err_set_attribute_error` 후 FALSE 반환.  
  - 행이 있으면 4a/4b/4c대로 처리.

- **요약 순서**:
  1. type_id = ob_type(obj_id). type_id가 py_type_object에 없으면 에러.
  2. type_id와 tp_bases로 **타입·bases에서 name 조회** (lookup_in_type_and_bases와 동일 로직으로 “어디선가 name을 찾음” + 그 값의 타입에 `__set__` 있는지 확인).  
     - 찾은 값에 `__set__` 있으면 → `__set__(descriptor, obj, value)` 호출 후 반환.  
  3. 타입·bases에 name 없거나, 있지만 `__set__` 없음 → 인스턴스 __dict__ 경로.  
     - `py_instance_object`에 obj_id 행 **있음** → in_dict 확보(없으면 새 dict 생성·할당), `py_dict_set_item(in_dict, name, value)`.  
     - `py_instance_object`에 obj_id 행 **없음** → AttributeError 설정 후 실패.

- **타입/테이블 판별**: `py_object`·`py_type_object`·`py_instance_object`·`tp_dict`·`tp_bases`·`py_dict_get_item`만 사용. `tp_name` 비교 금지.

### 3.2 py_opcode_STORE_ATTR(frame_id uuid, name_index integer)

- **1)** frame 유효성·name_index ≥ 0 검사.
- **2)** frame의 `f_code` → code_obj_id, code의 `co_names` → co_names_id, `co_names[name_index]` → name_str_id (tuple 1-based 인덱스).
- **3)** `obj_id := py_stack_pop(frame_id)`, `value_id := py_stack_pop(frame_id)` (스택: TOS=owner, SECOND=value 이므로 owner 먼저 pop, 그 다음 value pop).
- **4)** `py_object_setattr(obj_id, name_str_id, value_id)` 호출. 실패(예외 설정) 시 그대로 반환.
- **instruction 크기**: 2바이트. `py_get_opcode_size` 수정 없음(95 ≥ 90).

### 3.3 eval_frame·예외 디스패치

- **232000** `ceval_eval_frame.sql`: CASE에 `WHEN 95 THEN PERFORM py_opcode_STORE_ATTR(frame_id, arg);` 추가.
- **41000** `ceval_exception_dispatch.sql`: 동일 CASE에 95 추가.
- **41100** `python_exception_setters.sql`: 동일 CASE에 95 추가.

---

## 4. 타입·bases에서 “name으로 조회 + __set__ 여부” 로직

- LOAD_ATTR의 `lookup_in_type_and_bases`는 “값을 찾아서 반환(디스크립터면 __get__ 호출)”이다.  
- STORE_ATTR에서는 “이름으로 찾은 항목이 **__set__** 를 가지면 **그 descriptor로 __set__(obj, value)** 호출”이면 된다.  
- 따라서 **동일한 DFS**(type_id의 tp_dict, 그 다음 tp_bases 순서대로)로 name을 조회하되,  
  - 찾은 `attr_id`에 대해: attr_id의 타입의 tp_dict에 `"__set__"` 이 있으면 → `py_object_call(__set__id, [attr_id, obj_id, value_id], NULL)` 호출 후 성공/실패 반환.  
  - 없으면 “인스턴스 __dict__” 경로로 넘어감.  
- “이름으로 조회”는 기존 `lookup_in_type_and_bases`와 같은 순서를 쓰되, **반환값**은 쓰지 않고 “그 attr에 __set__ 있나”만 보면 되므로, **별도 함수** `lookup_descriptor_for_setattr(type_id, name_str_id)` 를 두어 “type과 bases를 DFS로 돌려 name으로 찾은 attr_id와 그 타입에 __set__ 있는지”를 반환하거나,  
- 또는 `lookup_in_type_and_bases`를 “디스크립터 __get__ 호출 없이 attr_id만 반환”하는 모드로 확장하는 대신, **STORE_ATTR 전용**으로 “type+bases에서 name 조회 → attr_id 반환”하는 함수 하나를 두는 편이 단순하다.  
- **제안**: `lookup_attr_in_type_and_bases(type_id, name_str_id)` — type_id의 tp_dict에서 name 조회, 없으면 tp_bases 순서대로 재귀. **찾은 attr_id만 반환** (__get__ 호출 없음). STORE_ATTR 쪽에서는 이 함수로 attr_id를 얻고, attr_id의 타입에 `__set__` 이 있으면 `__set__(attr_id, obj_id, value_id)` 호출.  
- 기존 `lookup_in_type_and_bases`는 “값 반환”용(디스크립터면 __get__ 호출)이므로, “attr_id만 조회”하는 함수를 새로 두거나, `lookup_in_type_and_bases` 내부 로직(타입+bases DFS로 tp_dict에서 name 조회)을 공유하는 방식이 좋다.  
- **단순화**: `lookup_attr_in_type_and_bases(type_id, name_str_id) RETURNS uuid` — type과 bases를 DFS로 돌려 **name으로 찾은 첫 번째 attr_id**를 반환 (없으면 NULL). STORE_ATTR: 이걸 호출해 attr_id를 얻고, attr_id가 NOT NULL이면 해당 attr의 타입에 `__set__` 있는지 확인; 있으면 `__set__(attr, obj, value)` 호출. 없으면(또는 attr_id가 NULL이면) 인스턴스 __dict__ 경로.

---

## 5. 임시방편 금지 체크리스트

- [ ] 타입/객체 판별: **테이블 존재·ob_type·tp_dict·tp_bases·py_instance_object·py_dict_get_item**만 사용. `tp_name = '...'` 분기 금지.
- [ ] `"__set__"` 사용: **py_str_from_text('__set__')** 또는 상수 str id만 사용.
- [ ] AttributeError: 전용 setter만 사용.
- [ ] 스키마: **기존 테이블·컬럼만 사용**. 인스턴스 __dict__는 기존 `py_instance_object.in_dict`; 최초 저장 시 새 dict 객체 생성·INSERT/UPDATE만 함.

---

## 6. 마이그레이션 배치 (기존 파일 수정 원칙)

- **원칙**: 새 마이그레이션 파일을 만들지 않고 **기존 마이그레이션을 코드처럼 수정**.
- **수정 대상**:
  - **235000** `tp_hash_slot.sql`: `lookup_attr_in_type_and_bases` (또는 기존 lookup 재사용), `py_object_setattr`, `py_opcode_STORE_ATTR` 정의.
  - **232000** `ceval_eval_frame.sql`: CASE에 95 추가.
  - **41000** `ceval_exception_dispatch.sql`: CASE에 95 추가.
  - **41100** `python_exception_setters.sql`: CASE에 95 추가.
- **233000** 은 opcode 정의만 두고, STORE_ATTR 핸들러는 235000에 두는 것이 LOAD_ATTR과 일관됨 (235000에 py_opcode_LOAD_ATTR이 있으므로 py_opcode_STORE_ATTR도 235000).

---

## 7. 작업 ID·의존관계·실행 순서

### 7.1 작업 ID (세부)

| ID | 작업 | 산출물 |
|----|------|--------|
| **S1** | lookup_attr_in_type_and_bases(type_id, name_str_id) 함수 추가 (타입+bases DFS로 name 조회, attr_id만 반환) | 235000 수정 |
| **S2** | py_object_setattr(obj_id, name_str_id, value_id) 정의 (descriptor __set__ 우선, 없으면 인스턴스 __dict__) | 235000 수정 |
| **S3** | py_opcode_STORE_ATTR(frame_id, name_index) 정의 | 235000 수정 |
| **S4** | py_eval_frame에 95 분기 추가 | 232000 수정 |
| **S5** | ceval_exception_dispatch에 95 분기 추가 | 41000 수정 |
| **S6** | python_exception_setters에 95 분기 추가 | 41100 수정 |
| **S7** | STORE_ATTR 통합 테스트 (obj.x = value, LOAD_ATTR로 확인; descriptor __set__; 미허용 대상 시 AttributeError) | supabase/tests/, run_tests.sh |

### 7.2 의존 관계

```
S1 (lookup_attr_in_type_and_bases)
  └─→ S2 (py_object_setattr 가 S1 사용)
        └─→ S3 (py_opcode_STORE_ATTR 가 py_object_setattr 사용)
              └─→ S4, S5, S6 (eval_frame·예외 디스패치에 95 분기)
                    └─→ S7 (통합 테스트)
```

- **S1**: 기존 `lookup_in_type_and_bases`와 동일한 DFS(타입 tp_dict → tp_bases 순서)로 **name으로 attr_id만** 반환. (__get__ 호출 없음.)
- **S2**: S1 호출 → attr_id. attr_id가 NOT NULL이고 해당 타입에 `__set__` 있으면 `py_object_call(__set__id, [attr_id, obj_id, value_id], NULL)`. 아니면 py_instance_object 조회 → in_dict 확보(없으면 새 dict 생성·할당), py_dict_set_item. 인스턴스 행 없고 descriptor도 없으면 AttributeError.
- **S3**: 스택에서 value, obj 순으로 pop, name_str_id 획득, py_object_setattr 호출.
- **S4, S5, S6**: CASE에 95 추가.
- **S7**: 바이트코드로 obj.x = value 실행 후 LOAD_ATTR로 obj.x 조회해 value와 일치 확인; descriptor 있으면 __set__ 호출 확인; 인스턴스 아닌 객체에 저장 시 AttributeError 확인.

### 7.3 실행 순서 (가장 먼저 실행할 것부터)

| 순서 | 작업 | 선행 | 비고 |
|------|------|------|------|
| **1** | **S1** lookup_attr_in_type_and_bases 추가 | 없음 | 235000, 타입+bases DFS로 name → attr_id |
| **2** | **S2** py_object_setattr 정의 | S1 | 235000, __set__ 우선 후 인스턴스 __dict__ |
| **3** | **S3** py_opcode_STORE_ATTR 정의 | S2 | 235000 |
| **4** | **S4** py_eval_frame에 95 분기 | S3 | 232000 |
| **5** | **S5** ceval_exception_dispatch에 95 분기 | S3 | 41000 |
| **6** | **S6** python_exception_setters에 95 분기 | S3 | 41100 |
| **7** | **S7** STORE_ATTR 통합 테스트 | S4,S5,S6 | 테스트 파일 추가, run_tests.sh Phase 44 등록 |

---

## 8. 요약

| 단계 | 내용 | 산출물 |
|------|------|--------|
| 1 | lookup_attr_in_type_and_bases (타입+bases에서 name → attr_id) | 235000 |
| 2 | py_object_setattr (descriptor __set__ 우선, else 인스턴스 __dict__) | 235000 |
| 3 | py_opcode_STORE_ATTR, eval_frame·예외 95 분기 | 235000, 232000, 41000, 41100 |
| 4 | 테스트: obj.x = value, LOAD_ATTR 검증, AttributeError | supabase/tests/, run_tests.sh |

**CPython 고증**: STORE_ATTR(95) = setattr(TOS, co_names[namei], SECOND), 타입·bases에서 data descriptor(__set__) 우선, 없으면 인스턴스 __dict__ 저장, 실패 시 AttributeError.  
**임시구현 없음**: tp_name 분기 없이, 테이블·tp_dict·tp_bases·py_dict_get_item·py_object_call·py_instance_object만 사용.
