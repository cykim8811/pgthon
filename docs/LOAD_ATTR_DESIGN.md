# LOAD_ATTR / 속성 조회 설계 — CPython 고증·임시구현 없음

CPython의 **LOAD_ATTR** opcode 및 **PyObject_GetAttr**에 해당하는 속성 조회를 Elytra에서 구현하기 위한 설계 문서다.  
**임시방편 금지**: `tp_name`/타입 이름 문자열로 분기하지 않고, **테이블 존재·tp_dict·슬롯·디스크립터 프로토콜**만 사용한다.

---

## 1. CPython 고증 요약

### 1.1 LOAD_ATTR opcode

| 항목 | CPython | Elytra 대응 |
|------|--------|-------------|
| **opcode** | LOAD_ATTR (Python 3.10 기준 opcode 106) | opcode 106 처리 |
| **operand** | name index → `co_names[namei]` (속성 이름 str) | `name_index` → co_names[name_index]로 이름 str id 획득 |
| **스택** | TOS가 객체. TOS를 `getattr(TOS, name)` 결과로 **교체**. | pop obj → `py_object_getattr(obj, name_str_id)` → push 결과 |
| **실패** | AttributeError | `py_err_set_attribute_error` 후 NULL 반환·전파 |

- Python 3.12+에서는 operand에 “method load” 비트가 있으나, **Phase 1은 3.10 스타일**: operand = `co_names` 인덱스만 사용.

### 1.2 PyObject_GetAttr / getattr(obj, name)

- **순서**: CPython은 `type(obj).__getattribute__(obj, name)` → 실패 시 `type(obj).__getattr__(obj, name)`.
- **일반 경로**: 인스턴스 `__dict__` → 타입 및 MRO의 `tp_dict`에서 name 조회 → 발견 시 **디스크립터**: `__get__` 있으면 `descriptor.__get__(obj, type)` 호출 후 그 결과 반환.
- **Elytra Phase 1 범위**:
  - **타입 쪽만**: `type(obj).tp_dict`에서 name으로 조회. (인스턴스 `__dict__`·MRO 순회는 Phase 2 이후.)
  - **디스크립터**: 조회 결과가 `__get__`를 가지면(해당 타입의 `tp_dict["__get__"]` 존재) `__get__(obj, type)` 호출, 아니면 조회값 그대로 반환.
  - **타입 판별**: `tp_dict`·`py_dict_get_item`·테이블 존재만 사용. `tp_name` 문자열 비교 금지.

### 1.3 디스크립터 프로토콜

- `descriptor.__get__(self, obj, type=None)`  
  - obj = 속성 접근 대상 객체, type = `type(obj)`.  
  - Elytra: `py_object_call(__get__id, [descriptor_id, obj_id, type_id], NULL)`로 호출. (인자 순서·개수는 CPython과 동일.)
- “`__get__`가 있다”의 판별: **속성으로 나온 값의 타입**에 대해, 그 타입의 `tp_dict`에 `"__get__"` 키로 뭔가 들어있는지로만 판단. (타입 이름 분기 금지.)

### 1.4 AttributeError

- 속성을 찾지 못하면 CPython은 **AttributeError**를 설정.
- Elytra: **AttributeError** 예외 타입·인스턴스·`py_err_set_attribute_error(message)` 를 추가하고, 조회 실패 시 이 setter만 사용. (임시로 TypeError 등으로 대체하지 않음.)

---

## 2. 현재 Elytra 상태

| 항목 | 상태 |
|------|------|
| `py_type_object.tp_dict` | ✅ 220000·223000에 정의·부트스트랩됨 |
| `py_dict_get_item` (키 = str id) | ✅ 235000에서 hash·동등성 기반 조회 |
| `py_object_call` (호출 가능 객체) | ✅ tp_call·CALL_FUNCTION 등으로 존재 |
| `py_str_from_text` | ✅ 24300에서 정의 (예: `"__get__"` str 생성 가능) |
| **AttributeError** 타입·setter | ❌ 없음 (24100·24300에 추가 필요) |
| **py_object_getattr** | ❌ 없음 |
| **LOAD_ATTR(106)** | ❌ 없음 |

- **결론**: 스키마는 그대로 두고, AttributeError 부트스트랩·setter, `py_object_getattr`, `py_opcode_LOAD_ATTR`, eval_frame·예외 디스패치에 106 분기만 추가하면 됨.

---

## 3. 구현 설계 (임시방편 없음)

### 3.1 AttributeError 부트스트랩·setter

- **24100** (exception schema): AttributeError 타입 UUID(예: `00000000-0000-4000-a000-000000000027`, 기존 022–026 다음)·tp_bases·tp_dict·py_base_exception_object 부트스트랩 추가. (기존 TypeError, NameError와 동일 패턴.)
- **24300** (exception setters): `py_err_set_attribute_error(p_message text)` 추가. 내부에서 `py_str_from_text(p_message)` 등으로 메시지 str 생성 후 `py_err_set_object(AttributeError_type_id, inst_id)` 호출.
- **타입 판별**: 고정 UUID 상수만 사용. `tp_name` 조회는 setter 내부에서도 **분기 로직에 사용하지 않음**.

### 3.2 py_object_getattr(obj_id uuid, name_str_id uuid) RETURNS uuid

- **1)** `obj_id`의 `ob_type` → type_id. type_id에 해당하는 `py_type_object` 행이 없으면 에러.
- **2)** type_id의 `tp_dict` → dict_id. NULL이면 AttributeError 설정 후 NULL 반환.
- **3)** `py_dict_get_item(dict_id, name_str_id)` → attr_id. NULL이면 AttributeError 설정 후 NULL 반환.
- **4)** 디스크립터 처리: attr_id의 타입 = attr_type_id. attr_type_id의 `tp_dict`에서 `"__get__"` 키로 조회.  
  - `__get__` str id는 **py_str_from_text('__get__')** 로 생성하거나, 한 번 생성해 상수로 둠. (분기 로직에 tp_name 사용 금지.)  
  - `get_id := py_dict_get_item(attr_type_tp_dict, __get__str_id)`.  
  - get_id가 NOT NULL이면: `py_object_call(get_id, [attr_id, obj_id, type_id], NULL)` → result_id. result_id 반환.  
  - get_id가 NULL이면: attr_id 그대로 반환.
- **5)** 호출 실패(예외 설정됨) 시 NULL 반환. 호출 성공 시 해당 값 반환.
- **타입/테이블 판별**: `py_object`·`py_type_object`·`py_dict_get_item`만 사용. `tp_name` 비교 금지.

### 3.3 py_opcode_LOAD_ATTR(frame_id uuid, name_index integer)

- **1)** frame 유효성·name_index ≥ 0 검사.
- **2)** frame의 `f_code` → code_obj_id, code의 `co_names` → co_names_id, `co_names[name_index]` → name_str_id (tuple 1-based 인덱스).
- **3)** `py_stack_pop(frame_id)` → obj_id.
- **4)** `result_id := py_object_getattr(obj_id, name_str_id)`.
- **5)** result_id가 NULL이면 이미 예외가 설정되어 있으므로 그대로 반환(호출자가 예외 처리).
- **6)** `py_stack_push(frame_id, result_id)`.
- **instruction 크기**: 2바이트. `py_get_opcode_size` 수정 없음(106 ≥ 90).

### 3.4 eval_frame·예외 디스패치

- **232000** `ceval_eval_frame.sql`: CASE에 `WHEN 106 THEN PERFORM py_opcode_LOAD_ATTR(frame_id, arg);` 추가.
- **41000** `ceval_exception_dispatch.sql`: 동일 CASE에 106 추가.
- **41100** `python_exception_setters.sql`: 동일 CASE에 106 추가.

---

## 4. 임시방편 금지 체크리스트

- [ ] 타입/객체 판별: **테이블 존재·ob_type·tp_dict·py_dict_get_item**만 사용. `tp_name = '...'` 분기 금지.
- [ ] `"__get__"` 사용: **py_str_from_text('__get__')** 또는 부트스트랩/상수 str id만 사용. 이름으로 분기할 때 타입 이름 문자열 비교 금지.
- [ ] AttributeError: **전용 타입·setter**로 설정. TypeError 등으로 대체하지 않음.
- [ ] 스키마: **기존 테이블·컬럼만 사용**. 인스턴스 `__dict__`·MRO는 Phase 2에서 설계·추가.

---

## 5. 작업 ID·의존관계·실행 순서

### 5.1 작업 ID 정의

| ID | 작업 | 산출물 |
|----|------|--------|
| **A** | AttributeError 타입·tp_dict·부트스트랩 | 24100 수정 |
| **B** | py_err_set_attribute_error 추가 | 24300 수정 |
| **C** | py_object_getattr(obj_id, name_str_id) 정의 | 기존 마이그레이션(예: 236000 또는 235000) 수정 |
| **D** | py_opcode_LOAD_ATTR(frame_id, name_index) 정의 | 기존 opcode 마이그레이션(233000) 수정 |
| **E** | py_eval_frame에 106 분기 추가 | 232000 수정 |
| **F** | ceval_exception_dispatch에 106 분기 추가 | 41000 수정 |
| **G** | python_exception_setters에 106 분기 추가 | 41100 수정 |
| **H** | LOAD_ATTR 통합 테스트 | supabase/tests/, run_tests.sh |

### 5.2 의존관계

```
A ──→ B   (setter는 AttributeError 타입 존재 후)

B ──→ C   (py_object_getattr에서 AttributeError setter 사용)

C ──→ D   (py_opcode_LOAD_ATTR에서 py_object_getattr 사용)

D ──┐
    ├──→ E, F, G   (eval_frame·예외 디스패치에서 106 호출)
E ──┼──→ H   (테스트는 E,F,G 반영 후)
F ──┘
G ──┘
```

- **A**: 선행 없음.
- **B**: A에 의존.
- **C**: B에 의존. (그리고 `py_dict_get_item`, `py_object_call`, `py_str_from_text` 등은 이미 존재.)
- **D**: C에 의존.
- **E, F, G**: D에 의존.
- **H**: E, F, G 반영 후 실행.

### 5.3 실행 순서 (가장 먼저 할 일부터)

| 순위 | 작업 | 선행 | 비고 |
|------|------|------|------|
| **1** | **A** AttributeError 부트스트랩 | 없음 | 24100에 타입·tp_dict·예외 인스턴스 패턴 추가 |
| **2** | **B** py_err_set_attribute_error | A | 24300에 setter 추가 |
| **3** | **C** py_object_getattr 정의 | B | 타입 tp_dict 조회 + __get__ 디스크립터 호출 |
| **4** | **D** py_opcode_LOAD_ATTR 정의 | C | 233000 또는 opcode 담당 마이그레이션에 추가 |
| **5** | **E** py_eval_frame에 106 추가 | D | 232000 CASE |
| **6** | **F** ceval_exception_dispatch에 106 추가 | D | 41000 CASE |
| **7** | **G** python_exception_setters에 106 추가 | D | 41100 CASE |
| **8** | **H** 통합 테스트 | E, F, G | 바이트코드 obj.attr, 없을 때 AttributeError 등 |

---

## 6. 마이그레이션 배치 (기존 파일 수정 원칙)

- **원칙**: 새 마이그레이션 파일을 만들지 않고 **기존 마이그레이션을 코드처럼 수정**.
- **수정 대상**:
  - **24100** `exception_schema.sql`: AttributeError 타입·dict·부트스트랩.
  - **24300** `exception_setters.sql`: `py_err_set_attribute_error`.
  - **236000** `tp_richcompare_slot.sql` 또는 **235000** `tp_hash_slot.sql`: `py_object_getattr` (dict·call 의존성 있는 쪽에 가깝게; 235000에 이미 py_dict_get_item·LOAD_NAME 등이 있으므로 **235000** 또는 **233000** 중 하나. 233000은 opcode 위주이므로 **py_object_getattr는 235000 또는 236000**에 두고, **py_opcode_LOAD_ATTR만 233000**에 두는 것이 자연스러움.)
  - **233000** `ceval_opcodes_basic.sql`: `py_opcode_LOAD_ATTR`.
  - **232000, 41000, 41100**: CASE에 106 추가.

---

## 7. Phase 2 (본 설계 외, 참고)

- **인스턴스 __dict__**: 객체별 속성 저장. 스키마에 `py_object` 확장 또는 별도 테이블 필요.
- **MRO 순회**: `tp_bases` 따라 부모 타입의 `tp_dict` 순서대로 조회.
- **STORE_ATTR / DELETE_ATTR**: 속성 쓰기·삭제 opcode.

---

## 8. 가장 먼저 실행할 작업 요약

| 순서 | 작업 ID | 할 일 |
|------|---------|--------|
| 1 | A | 24100에 AttributeError 타입·tp_dict·부트스트랩 추가 |
| 2 | B | 24300에 `py_err_set_attribute_error(p_message text)` 추가 |
| 3 | C | 235000(또는 236000)에 `py_object_getattr(obj_id, name_str_id)` 정의 (tp_dict 조회 + __get__ 디스크립터) |
| 4 | D | 233000에 `py_opcode_LOAD_ATTR(frame_id, name_index)` 정의 |
| 5 | E | 232000의 CASE에 `WHEN 106 THEN PERFORM py_opcode_LOAD_ATTR(frame_id, arg);` 추가 |
| 6 | F | 41000의 CASE에 106 분기 추가 |
| 7 | G | 41100의 CASE에 106 분기 추가 |
| 8 | H | LOAD_ATTR 통합 테스트 파일 추가 및 run_tests.sh Phase 42 등록 |

의존 관계: **A → B → C → D → E,F,G → H**.

---

## 9. 요약

| 단계 | 내용 | 산출물 |
|------|------|--------|
| 1 | AttributeError + py_err_set_attribute_error | 24100, 24300 |
| 2 | py_object_getattr (tp_dict + descriptor __get__) | 235000 또는 236000 |
| 3 | py_opcode_LOAD_ATTR, eval_frame·예외 106 분기 | 233000, 232000, 41000, 41100 |
| 4 | 테스트: obj.attr, AttributeError | supabase/tests/, run_tests.sh |

**CPython 고증**: LOAD_ATTR(106) = getattr(TOS, co_names[namei]), 타입 tp_dict 조회, 디스크립터 __get__(obj, type) 호출, 실패 시 AttributeError.  
**임시구현 없음**: tp_name 분기·타입 이름 비교 없이, 테이블·tp_dict·py_dict_get_item·py_object_call만 사용.
