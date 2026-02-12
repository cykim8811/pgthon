# DELETE_ATTR / 속성 삭제 설계 — CPython 고증·임시구현 없음

CPython의 **DELETE_ATTR** opcode 및 **PyObject_DelAttr**에 해당하는 속성 삭제를 Pgthon에서 구현하기 위한 설계 문서다.  
**임시방편 금지**: `tp_name`/타입 이름 문자열로 분기하지 않고, **테이블 존재·tp_dict·디스크립터 프로토콜**만 사용한다.

---

## 1. CPython 고증 요약

### 1.1 DELETE_ATTR opcode

| 항목 | CPython | Pgthon 대응 |
|------|--------|-------------|
| **opcode** | DELETE_ATTR (Python 3.10 기준 opcode **97**) | opcode 97 처리 |
| **operand** | name index → `co_names[namei]` | `name_index` → co_names[name_index]로 이름 str id 획득 |
| **스택** | TOS = owner. pop 후 `delattr(owner, name)` 호출. | pop obj (TOS) → `py_object_delattr(obj_id, name_str_id)` |
| **실패** | AttributeError 등 | `py_err_set_attribute_error` 등 후 전파 |

- CPython ceval.c: 스택에서 owner만 pop, `PyObject_DelAttr(owner, name)` 호출.

### 1.2 PyObject_DelAttr / delattr(obj, name)

- **일반 경로**: `type(obj).__delattr__(obj, name)`.
- **object.__delattr__(self, name)** (인스턴스):  
  1. 타입(및 MRO)에서 해당 이름의 **data descriptor** (__set__ 또는 __delete__ 있는 것) 조회.  
  2. **있고 __delete__가 있으면** → `descriptor.__delete__(self)` 호출 후 종료.  
  3. **있지만 __delete__가 없으면** (data descriptor가 삭제 미지원) → **AttributeError**.  
  4. 없으면 **인스턴스 __dict__** 에서 해당 키 삭제. 키가 없으면 AttributeError.
- **type.__delattr__(cls, name)** (클래스):  
  1. 메타클래스(타입의 타입) MRO에서 해당 이름의 data descriptor 조회.  
  2. __delete__ 있으면 `descriptor.__delete__(cls)` 호출 후 종료.  
  3. 없으면 **클래스 __dict__** (Pgthon: `tp_dict`)에서 해당 키 삭제. 키가 없으면 AttributeError.

즉, **descriptor에 __delete__가 있으면 그걸 호출**, 없으면 **__dict__에서 키 삭제**이며, 삭제할 항목이 없으면 AttributeError.

### 1.3 디스크립터 프로토콜 (삭제)

- `descriptor.__delete__(self, obj)`  
  - CPython: 인자 2개 (self, obj).  
  - Pgthon: `py_object_call(__delete__id, [descriptor_id, obj_id], NULL)` 로 호출.
- “**__delete__가 있다**”의 판별: 타입(또는 bases)의 tp_dict에서 name으로 조회한 값(descriptor)의 **타입**에 대해, 그 타입의 `tp_dict`에 `"__delete__"` 키로 뭔가 들어있는지로만 판단. (타입 이름 분기 금지.)
- Data descriptor(__set__ 있음)인데 **__delete__가 없으면** 삭제 시 AttributeError (CPython: 해당 descriptor가 삭제를 허용하지 않음).

### 1.4 Pgthon 범위 (의도적 축소)

- **MRO 미사용**: LOAD_ATTR/STORE_ATTR과 동일하게 **tp_bases DFS**만 사용 (lookup_attr_in_type_and_bases).
- **타입/인스턴스 판별**: `py_type_object` / `py_instance_object` 테이블 존재만 사용. `tp_name` 비교 금지.
- **클래스 속성 삭제**: `del C.x` → obj가 타입이면 해당 타입의 `tp_dict`에서 name 항목 삭제 (descriptor __delete__ 처리 후).

---

## 2. 현재 Pgthon 상태

| 항목 | 상태 |
|------|------|
| `py_dict_set_item` / `py_dict_get_item` | ✅ 235000 |
| **py_dict_del_item** | ❌ 없음. 구현 필요. |
| `lookup_attr_in_type_and_bases` | ✅ 235000 |
| `py_object_setattr` (타입 경로·인스턴스 경로) | ✅ 235000 |
| **py_object_delattr** | ❌ 없음. 구현 필요. |
| **py_opcode_DELETE_ATTR** | ❌ 없음. |
| **eval_frame opcode 97** | ❌ 없음. |

- **결론**: `py_dict_del_item` 추가 후 `py_object_delattr` 구현, opcode 97 및 eval_frame 분기 추가.

---

## 3. 구현 설계 (임시방편 없음)

### 3.1 py_dict_del_item(dict_id UUID, key_id UUID) RETURNS BOOLEAN

- **역할**: dict에서 key에 해당하는 항목을 삭제. CPython의 `PyDict_DelItem` / `dict.__delitem__`에 대응.
- **동작**:  
  - `me_hash = py_object_hash(key_id)`.  
  - `py_dict_entry`에서 `dict_id = dict_id AND me_hash = h AND py_object_richcompare_eq(me_key, key_id)` 인 행을 찾아 **DELETE**.  
  - 해당 행이 **있었으면 TRUE**, 없었으면 FALSE 반환. (호출부에서 AttributeError 설정에 사용.)
- **배치**: `20260114235000_tp_hash_slot.sql` — `py_dict_set_item` 바로 다음에 정의.
- **임시방편 금지**: 기존 `py_dict_get_item`/`py_dict_set_item`과 동일하게 hash·richcompare_eq만 사용. 타입 이름 분기 없음.

### 3.2 py_object_delattr(obj_id UUID, name_str_id UUID) RETURNS VOID

- **순서** (STORE_ATTR와 대칭, CPython PyObject_GenericSetAttr delete 경로):

1. **유효성**: `obj_id`가 `py_object`에 없으면 에러. `ob_type` → type_id. type_id에 해당하는 `py_type_object` 행이 없으면 에러.
2. **디스크립터 조회**: `attr_id := lookup_attr_in_type_and_bases(type_id, name_str_id)`.
   - **attr_id IS NOT NULL** 이고, attr_id의 타입의 tp_dict에 **`__delete__`** 가 있으면  
     → `py_object_call(__delete__id, [attr_id, obj_id], NULL)` 호출 후 **RETURN**. (예외 시 그대로 전파.)
   - **attr_id IS NOT NULL** 이고, attr_id의 타입의 tp_dict에 **`__set__`** 는 있는데 **`__delete__`** 는 없으면  
     → data descriptor가 삭제 미지원 → `py_err_set_attribute_error` 후 RETURN.
   - 그 외(attr_id가 NULL이거나, __set__/__delete__ 둘 다 없음) → 3으로.
3. **타입 객체 경로**: `EXISTS (SELECT 1 FROM py_type_object WHERE ob_base = obj_id)` 이면  
   - 해당 행의 `tp_dict` 조회. NULL이면 AttributeError 후 RETURN.  
   - `py_dict_del_item(tp_dict_id, name_str_id)` 호출. **반환값이 FALSE**이면(키가 없었음) AttributeError 후 RETURN.  
   - RETURN.
4. **인스턴스 __dict__ 경로**: `py_instance_object`에서 `ob_base = obj_id` 행 조회.  
   - **NOT FOUND** → AttributeError 후 RETURN.  
   - in_dict가 NULL이면 AttributeError 후 RETURN.  
   - `py_dict_del_item(in_dict_id, name_str_id)` 호출. **반환값이 FALSE**이면 AttributeError 후 RETURN.  
   - RETURN.

- **타입/인스턴스 구분**: 테이블 존재만 사용. `tp_name` / ob_type 비교 금지.
- **배치**: `20260114235000_tp_hash_slot.sql` — `py_object_setattr` 다음에 정의.

### 3.3 py_opcode_DELETE_ATTR(frame_id UUID, name_index INTEGER) RETURNS VOID

- **1)** frame 유효성, name_index ≥ 0 검사.
- **2)** frame의 f_code → code_obj_id, co_names → co_names_id, `co_names[name_index]` → name_str_id.
- **3)** `obj_id := py_stack_pop(frame_id)` (스택: TOS = owner만 있음).
- **4)** `py_object_delattr(obj_id, name_str_id)` 호출. 실패 시 그대로 반환(예외 상태 유지).
- **instruction 크기**: 2바이트.
- **배치**: 새 파일 `20260114240317_opcode_delete_attr.sql` (opcode 블록).

### 3.4 eval_frame·예외 디스패치

- **241100** `ceval_eval_frame.sql`: CASE에 `WHEN 97 THEN PERFORM public.py_opcode_DELETE_ATTR(frame_id, arg);` 추가.

---

## 4. 임시방편 금지 체크리스트

- [ ] 타입 여부: **`EXISTS (SELECT 1 FROM py_type_object WHERE ob_base = obj_id)`** 만 사용.
- [ ] 인스턴스 여부: **`py_instance_object`에서 ob_base = obj_id** 행 존재만 사용.
- [ ] 디스크립터: attr의 타입 tp_dict에 **`"__delete__"`** / **`"__set__"`** 키 존재로만 판단. 타입 이름 분기 금지.
- [ ] 스키마: **기존 테이블·컬럼만 사용**. 새 테이블/컬럼 추가 없음. `py_dict_entry` 행 DELETE만 추가.

---

## 5. 작업 ID·의존관계·실행 순서

### 5.1 작업 ID (세부)

| ID | 작업 | 산출물 |
|----|------|--------|
| **D1** | `py_dict_del_item(dict_id, key_id)` 추가 — hash·richcompare로 항목 찾아 DELETE, 있으면 TRUE 없으면 FALSE 반환 | 235000 수정 |
| **D2** | `py_object_delattr(obj_id, name_str_id)` 추가 — descriptor __delete__ 우선, 타입 경로(tp_dict 삭제), 인스턴스 경로(in_dict 삭제) | 235000 수정 |
| **D3** | `py_opcode_DELETE_ATTR(frame_id, name_index)` 정의 — stack pop owner, py_object_delattr 호출 | 새 파일 240317 |
| **D4** | `py_eval_frame`에 opcode 97 분기 추가 | 241100 수정 |
| **D5** | DELETE_ATTR 통합 테스트: del obj.x 후 getattr → AttributeError; del C.x 후 getattr(C,"x") → AttributeError; descriptor __delete__ 호출 시나리오 | supabase/tests/, run_tests.sh |

### 5.2 의존 관계

```
D1 (py_dict_del_item)
  └─→ D2 (py_object_delattr: 타입/인스턴스 __dict__ 삭제에 D1 사용)
        └─→ D3 (py_opcode_DELETE_ATTR)
              └─→ D4 (eval_frame 97 분기)
                    └─→ D5 (통합 테스트)
```

- **D1** 선행: D2에서 tp_dict / in_dict 항목 삭제 시 `py_dict_del_item` 필요.
- **D2** 선행: D3, D5에서 `py_object_delattr` 호출.
- **D3** 선행: D4는 opcode 97에서 D3 호출.
- **D4** 선행: D5는 bytecode로 DELETE_ATTR 실행하려면 eval_frame에 97이 연결돼 있어야 함.

### 5.3 실행 순서 (가장 먼저 실행할 것부터)

| 순서 | 작업 | 선행 | 비고 |
|------|------|------|------|
| **1** | **D1** py_dict_del_item 구현 | 없음 | 235000: py_dict_set_item 다음에 추가. DELETE ... WHERE dict_id AND me_hash AND eq, FOUND 여부 반환. |
| **2** | **D2** py_object_delattr 구현 | D1 | 235000: descriptor __delete__ → 타입 경로(tp_dict del) → 인스턴스 경로(in_dict del). |
| **3** | **D3** py_opcode_DELETE_ATTR 정의 | D2 | 새 migration 20260114240317_opcode_delete_attr.sql. |
| **4** | **D4** eval_frame에 97 분기 | D3 | 241100: WHEN 97 THEN PERFORM py_opcode_DELETE_ATTR(frame_id, arg). |
| **5** | **D5** 통합 테스트 | D4 | 새 테스트 파일(예: 48_delete_attr_integration.sql), run_tests.sh Phase 48 등록. |

---

## 6. 요약

| 단계 | 내용 | 산출물 |
|------|------|--------|
| 1 | py_dict_del_item 추가 (키 삭제, 존재 여부 반환) | 235000 |
| 2 | py_object_delattr 추가 (__delete__ 우선, 타입 tp_dict / 인스턴스 in_dict 삭제) | 235000 |
| 3 | py_opcode_DELETE_ATTR (stack pop owner, delattr) | 240317 |
| 4 | py_eval_frame opcode 97 연결 | 241100 |
| 5 | 통합 테스트 | supabase/tests/, run_tests.sh |

**CPython 고증**: PyObject_DelAttr / type.__delattr__ — MRO에서 data descriptor의 __delete__ 우선, 없으면 __dict__에서 키 삭제. Data descriptor에 __delete__ 없으면 AttributeError.  
**Pgthon**: MRO 대신 tp_bases DFS만 사용(lookup_attr_in_type_and_bases). 타입/인스턴스는 테이블 존재로만 판별.  
**임시구현 없음**: tp_name·타입 이름 비교 금지. 테이블·tp_dict·디스크립터 프로토콜만 사용.
