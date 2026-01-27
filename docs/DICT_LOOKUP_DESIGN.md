# Dict Lookup Hash 기반 구현 계획

CPython의 dict lookup을 hash 기반으로 구현하기 위한 설계·구현 계획이다.  
**임시방편 없이**, CPython의 의미론(키는 hash로 후보를 좁히고, 동등성으로 확정)에 맞게 단계적으로 구현한다.

---

## 1. CPython 쪽에서 할 일 정리

### 1.1 lookup 흐름 (PyDict_GetItem)

- `PyDict_GetItem(op, key)` → `_PyObject_HashFast(key)` 로 hash 계산
- `_Py_dict_lookup(mp, key, hash, &value)` 호출
- `do_lookup` 내부:
  - `i = (size_t)hash & mask` 로 초기 인덱스
  - probing: `perturb >>= PERTURB_SHIFT`, `i = mask & (i*5 + perturb + 1)`
  - 각 슬롯에서 `ix >= 0` 이면 `check_lookup`(예: `compare_generic`) 호출:
    - `ep->me_key == key` 이면 즉시 1 (찾음)
    - `ep->me_hash == hash` 이면 `PyObject_RichCompareBool(ep->me_key, key, Py_EQ)` 로 비교
    - 그 외 0이면 다음 probe
  - `DKIX_EMPTY` 면 없음

### 1.2 insert 시 me_hash 저장

- `insert_combined_dict` (generic key):
  - `find_empty_slot(mp->ma_keys, hash)` 로 빈 슬롯 찾기
  - `PyDictKeyEntry *ep = &DK_ENTRIES(...)[dk_nentries]`
  - `STORE_KEY(ep, key); STORE_VALUE(ep, value);` 와 함께 **`STORE_HASH(ep, hash)`** 호출

즉, **엔트리에는 항상 `me_hash`가 들어가 있고**, lookup은 hash로 후보를 줄인 뒤 **키 동등성(PyObject_RichCompareBool(·, ·, Py_EQ))** 으로 최종 확정한다.

### 1.3 키 동등성

- CPython: `PyObject_RichCompareBool(a, b, Py_EQ)` → 타입의 `tp_richcompare` 또는 기본 비교 사용.
- Elytra 1단계: 지원 타입(str, int 등)에 대해 **타입별 값 비교** (str→`str_value`, int→`long_value`).
- Elytra 2단계(추후): `tp_richcompare` 슬롯 기반 `py_object_richcompare_eq(a_id, b_id)` 로 통일. 구체적인 파일·함수 배치는 **[§7](#7-2단계-tp_richcompare-기반-키-동등성-추후)** 참고.

---

## 2. Elytra 현재 상태와 문제

### 2.1 스키마

- `py_dict_entry`: `(id, dict_id, me_key, me_value)` 만 있음. **`me_hash` 없음**.
- CPython의 `PyDictKeyEntry.me_hash` 에 해당하는 컬럼이 없어, hash 기반 lookup을 할 수 없다.

### 2.2 LOAD_NAME (임시 구현)

- `WHERE de.dict_id = f_locals_id AND de.me_key IN (SELECT ob_base FROM py_unicode_object WHERE str_value = name_str)` 형태.
- 문자열 **내용**으로만 찾고, hash를 쓰지 않으며, 키가 str이 아닌 경우 등은 고려되지 않음.

### 2.3 STORE_NAME (임시 구현)

- `WHERE dict_id = f_locals_id AND me_key = name_str_id` 로 “이미 있는지” 검사 후, 있으면 `UPDATE me_value`, 없으면 `INSERT (dict_id, me_key, me_value)`.
- `me_key`에 **같은 문자열을 가진 다른 객체**가 들어오면 “다른 키”로 취급되는 등, CPython의 “키 동등성”과 다를 수 있음.
- `me_hash` 를 전혀 저장하지 않음.

---

## 3. 구현할 대상 목록

아래 순서로 진행하면, “dict 하나에 대해 hash 기반 get/set”이 먼저 완성되고, 그 다음 LOAD_NAME/STORE_NAME 등 사용처가 그 API에만 의존하도록 정리된다.

1. **스키마**
   - `py_dict_entry`에 `me_hash BIGINT NOT NULL` 추가.
   - 기존 행 backfill: `me_hash = py_object_hash(me_key)` (마이그레이션에서 한 번에 수행).

2. **인덱스**
   - `(dict_id, me_hash)` 또는 `(dict_id, me_hash, me_key)` 로 hash 기반 검색이 인덱스를 타도록 설정.
   - 후보가 적을 때는 `(dict_id, me_hash)` 만으로도 충분할 수 있고, `me_key` 포함 시 “같은 dict·같은 hash” 내 키 필터까지 인덱스로 유도 가능.

3. **키 동등성 함수(1단계)**
   - `py_object_equals_key(a_id UUID, b_id UUID) RETURNS BOOLEAN`
   - 지원 타입별 분기: str → `py_unicode_object.str_value` 비교, int → `py_long_object.long_value` 비교.
   - **그 외 타입**: 1단계에서는 동등성 비교를 하지 않는다. id 비교는 하지 않고, **tp_richcompare가 있을 때만** 그 타입의 비교를 사용한다. tp_richcompare가 없으면 “같다”고 보지 않는다(항상 FALSE).
   - 주석으로 “2단계에서는 [§7](#7-2단계-tp_richcompare-기반-키-동등성-추후)의 `py_object_richcompare_eq` 로 대체” 명시.

4. **Dict API (핵심)**
   - `py_dict_get_item(dict_id UUID, key_id UUID) RETURNS UUID`
     - `key_id`에 대해 `py_object_hash(key_id)` 호출. unhashable이면 예외 전파.
     - `dict_id`·`me_hash = h` 인 엔트리만 조회한 뒤, 그 중 `py_object_equals_key(me_key, key_id)` 인 첫 엔트리의 `me_value` 반환. 없으면 NULL.
   - `py_dict_set_item(dict_id UUID, key_id UUID, value_id UUID) RETURNS VOID`
     - `py_object_hash(key_id)` 로 `h` 계산.
     - `dict_id`·`me_hash = h` 인 엔트리 중 `py_object_equals_key(me_key, key_id)` 인 것 검색.
     - 있으면 해당 row의 `me_value` 만 `value_id` 로 UPDATE (이미 있는 `me_hash` 유지).
     - 없으면 `INSERT (dict_id, me_key, me_value, me_hash)` 에 `me_hash = h` 포함하여 삽입.

5. **진입점 정리**
   - **LOAD_NAME**: `f_locals` → `f_globals` → `f_builtins` 순으로 `py_dict_get_item(dict_id, name_str_id)` 호출. 먼저 찾은 비-NULL을 push, 모두 NULL이면 NameError.
   - **STORE_NAME**: `py_dict_set_item(f_locals_id, name_str_id, value_obj_id)` 한 번만 호출.
   - 그 외 `py_dict_entry`를 직접 조회·삽입하는 모든 위치를 위 API로 교체:
     - `20260114233000_vm_opcodes_basic.sql` (LOAD_NAME / STORE_NAME)
     - `20260114225000_builtin_functions.sql` (builtin 등록 시 `py_dict_set_item` 사용)
     - `20260114226000_type_method_slots.sql` 등에서 dict를 “키로 찾는” 부분
     - 테스트에서 “dict에 넣고/찾는” 패턴은 가능하면 `py_dict_get_item` / `py_dict_set_item` 사용. 단, 테스트가 “엔트리 존재/값”을 검증할 때는 기존처럼 `py_dict_entry` 직조회도 유지 가능.

6. **INSERT 경로 일원화**
   - `py_dict_entry`에 대한 INSERT는 반드시 `me_hash`를 포함하도록 한다.
   - “헬퍼만 쓰게” 하려면, 가능한 한 `py_dict_set_item` 이 유일한 삽입 경로가 되고, bootstrap/테스트에서도 새 엔트리는 `py_dict_set_item` 또는 “INSERT 시 `me_hash = py_object_hash(me_key)` 를 넣는 공식 패턴”을 사용하도록 문서·주석으로 고정.

---

## 4. CPython과의 대응 관계

| CPython | Elytra (본 계획) |
|--------|-------------------|
| `PyDictKeyEntry.me_hash` | `py_dict_entry.me_hash` |
| `_PyObject_HashFast` / `PyObject_Hash` | `py_object_hash(key_id)` |
| hash로 후보 슬롯 좁히기 (do_lookup) | `WHERE dict_id = ? AND me_hash = ?` 로 후보 행 좁히기 |
| `PyObject_RichCompareBool(me_key, key, Py_EQ)` | 1단계: `py_object_equals_key(me_key, key_id)` (타입별 값 비교) |
| insert 시 `STORE_HASH(ep, hash)` | INSERT/UPDATE 시 항상 `me_hash = py_object_hash(me_key)` 유지 |

다음은 **이번 단계에서 구현하지 않는** CPython 디테일이다. “의미상 hash + equality 로 찾는다”는 점만 맞추고, 구조는 단순하게 간다.

- `dk_indices` / `dk_entries` 같은 물리 레이아웃
- perturb/probe 순서, `PERTURB_SHIFT`, `find_empty_slot` 등
- 테이블 크기·resize·load factor(USABLE_FRACTION 등)
- `DKIX_EMPTY` / `DKIX_DUMMY` 상태기계

이렇게 두는 이유는, **CPython의 “의미론(키는 hash + 동등성으로 찾는다)”만 고증**하고, **저장 구조는 PostgreSQL의 테이블·인덱스에 맡기는 설계 선택**이기 때문이다.

---

## 5. 주의사항

### 5.1 Unhashable

- `py_object_hash(key_id)`가 이미 `TypeError: unhashable type: '...'` 를 낸다.
- `py_dict_get_item` / `py_dict_set_item` 은 key에 대해 한 번만 hash를 부르면 되고, 예외는 그대로 전파하면 된다.
- dict/set 등 unhashable을 키로 넣으려 하면 CPython과 동일하게 타입 쪽에서 막히도록 둔다.

### 5.2 키 동등성의 범위

- “문자열 내용이 같으면 같은 키”처럼 동작하려면, 반드시 **동등성 비교**를 해야 한다. UUID가 같을 때만 같은 키로 보면 co_names과 무관한 str 객체가 같은 이름이어도 다른 키로 취급된다.
- 1단계는 str/int 등 지원 타입에 한해 값 비교로 동등성을 정의하고, 이후 `tp_richcompare` 기반으로 확장하는 경로를 남겨둔다.

### 5.3 기존 데이터 및 bootstrap

- `py_dict_entry`에 `me_hash` 를 추가하는 마이그레이션 시, 기존 모든 행에 대해 `me_hash = py_object_hash(me_key)` 를 실행해야 한다.
- bootstrap에서 __builtins__ 등에 엔트리를 넣는 부분은 “INSERT 시 `me_hash` 포함” 또는 `py_dict_set_item` 사용으로 바꾼다.

### 5.4 INSERT 시 me_hash 강제

- 모든 `py_dict_entry` INSERT가 `me_hash`를 넣도록, 다음 중 하나 이상으로 강제하는 것이 좋다:
  - `me_hash BIGINT NOT NULL` + 마이그레이션/backfill;
  - 그리고 “dict 엔트리 삽입은 `py_dict_set_item` 또는 명시적 `me_hash = py_object_hash(me_key)` 패턴으로만 수행”한다는 규칙을 README/코멘트에 명시.

---

## 6. 구현 단계 제안

1. **스키마·backfill**
   - `py_dict_entry.me_hash BIGINT NOT NULL` 추가.
   - 기존 데이터 backfill: 새 컬럼은 먼저 nullable로 추가한 뒤, `UPDATE py_dict_entry SET me_hash = py_object_hash(me_key)` 로 일괄 계산 후 `ALTER COLUMN me_hash SET NOT NULL` 로 고정한다. (같은 마이그레이션 또는 곧이은 마이그레이션에서 처리.)

2. **인덱스**
   - `CREATE INDEX ... ON py_dict_entry (dict_id, me_hash);` (필요 시 `(dict_id, me_hash, me_key)` 로 확장).

3. **키 동등성**
   - `py_object_equals_key(a_id, b_id)` 구현 (str/int 등 지원).

4. **Dict API**
   - `py_dict_get_item`, `py_dict_set_item` 구현 및 단위 테스트.

5. **호출부 이전**
   - LOAD_NAME / STORE_NAME을 위 API만 사용하도록 수정.
   - builtin 등록·기타 dict 삽입/조회를 `py_dict_set_item` / `py_dict_get_item` 으로 교체.

6. **테스트**
   - hash 기반 lookup 전용 테스트(같은 hash 다른 키, unhashable 키 예외 등).
   - 기존 LOAD_NAME/STORE_NAME·builtin 통합 테스트가 그대로 통과하는지 확인.

이 순서로 진행하면 “dict lookup을 hash 기반으로, CPython 의미에 맞게 바꾸고, 임시 구현을 제거한다”는 목표를 단계적으로 충족할 수 있다.

---

## 7. 2단계: tp_richcompare 기반 키 동등성 (추후)

dict 키 동등성을 “타입이 정의한 비교”로 통일할 때 쓸 **구체적인 파일·함수·배치**다. 구현 순서는 아래 순서를 참고하면 된다.

### 7.0 구현 과정 (고증·비임시방편 원칙)

아래는 tp_richcompare를 추가할 때 **CPython 고증을 지키고**, **임시방편을 넣지 않기 위해** 지킬 과정이다.

#### CPython 고증 포인트

- **비교 연산 상수**: `Include/object.h`와 동일한 값 사용.
  - `Py_LT=0`, `Py_LE=1`, `Py_EQ=2`, `Py_NE=3`, `Py_GT=4`, `Py_GE=5`
- **tp_richcompare 시그니처**: CPython은 `PyObject *(*richcmpfunc)(PyObject *, PyObject *, int)`.
  - Elytra에서는 `(self_id UUID, other_id UUID, op INTEGER) RETURNS UUID`로 매핑. CPython이 `int`를 쓰므로 PostgreSQL은 INTEGER로 둔다.
  - 반환값은 **객체 id 하나**이며, 의미상 True / False / NotImplemented 중 하나.
- **반환 객체**: True·False·NotImplemented는 **실제 DB 객체**(`py_bool_object`, `py_not_implemented_object` 행)로만 사용한다. "매직 id 상수만 쓰고 테이블 없이 넘어가는" 방식은 쓰지 않는다.
- **디스패치**: 비교 로직은 **타입별 분기 if/else가 아니라** `ob_type` → `tp_richcompare` 슬롯 조회 → 그 함수 호출로만 수행한다. 새 타입은 "슬롯 등록"만으로 붙어야 한다.

#### 임시방편을 피하는 원칙

1. **타입 이름 하드코딩 최소화**  
   타입별 richcompare 함수 내부에서는 "str인지 int인지"를 타입 이름 문자열로 분기하지 않는다. 해당 함수는 이미 그 타입 전용이므로, 테이블(`py_unicode_object` 등)만 보면 된다. 디스패치는 `py_object_richcompare`에서 **tp_richcompare 슬롯 유무**만 보면 된다.

2. **True/False/NotImplemented는 부트스트랩 상수로만 참조**  
   236000 마이그레이션에서는 `ID_TRUE_OBJ` 등 부트스트랩에서 이미 쓰는 고정 UUID 상수만 사용한다. "테이블에서 한 행만 잡아서 쓰자" 같은 동적 조회는 불필요하다. 부트스트랩이 먼저 돌므로, 236000 시점에는 이미 DB에 있다.

3. **dict 키 동등성은 "한 군데만" 교체**  
   `py_dict_get_item` / `py_dict_set_item` 안에서 **키 동등성 판단**만 `py_object_equals_key` → `py_object_richcompare_eq`로 바꾼다. 그 외 hash·인덱스·INSERT 경로는 1단계와 동일하게 둔다. "dict만을 위한 특수 비교 경로"를 따로 두지 않고, 전부 `py_object_richcompare_eq` 한 경로로 통일한다.

4. **Py_EQ 외 op는 "NotImplemented 반환"으로 통일**  
   str/int의 타입별 richcompare에서 Py_EQ가 아닌 op는 당분간 전부 NotImplemented id를 반환한다. CPython도 해당 타입이 그 op를 구현하지 않으면 NotImplemented를 돌려주므로, "일단 False 넣어두기" 같은 임시 처리보다 고증에 맞다.

#### 구현 순서(의존 관계)

1. **선행 조건 확인**  
   - `py_bool_object`, `py_not_implemented_object` 스키마 및 True/False/NotImplemented 부트스트랩이 이미 있음(현재 코드 기준 만족). 없으면 §7.2·§7.1 전에 220000/223000에서 보완.

2. **236000 마이그레이션 한 파일 안에서 할 일** (아래 순서대로 작성해도 됨)
   - `ALTER TABLE py_type_object ADD COLUMN tp_richcompare regproc;`
   - 상수 정의: `Py_EQ` 등 op 값, 및 `ID_TRUE_OBJ`, `ID_FALSE_OBJ`, `ID_NOT_IMPLEMENTED_OBJ`(부트스트랩과 동일 값).
   - 타입별 함수: `py_unicode_richcompare`, `py_long_richcompare` (시그니처·반환 의미가 §7.3과 맞는지 확인).
   - 범용 디스패치: `py_object_richcompare` (슬롯이 없으면 NotImplemented id 반환).
   - dict용 보조: `py_object_richcompare_eq` (True/False/NotImplemented + reverse 한 번 시도, §7.4).
   - 슬롯 등록: str/int의 `tp_richcompare`에 위 타입별 함수 등록.

3. **dict 쪽 전환**  
   - `py_dict_get_item` / `py_dict_set_item` 내부의 `py_object_equals_key(me_key, key_id)` 호출만 `py_object_richcompare_eq(me_key, key_id)`로 교체. 이 작업은 236000 다음 마이그레이션에 넣거나, "235000 자체를 수정해 236000에서 쓰는 새 함수를 부른다"는 식으로 정책을 정해 한 곳에서만 바꾼다. 설계상 호출부는 **한 군데**로 유지한다(§7.5).

이 순서와 원칙을 지키면, "타입 슬롯 하나로 비교를 확장하는" CPython 방식이 그대로 유지되고, 나중에 float·bytes 등은 **타입별 richcompare 함수 추가 + 슬롯 등록**만으로 붙일 수 있다.

### 7.1 스키마·슬롯

- **위치**: `py_type_object`에 컬럼 추가이므로, 기존 타입 스키마를 직접 건드리지 않고 **새 마이그레이션**에서 `ALTER TABLE`로 추가하는 편이 기존 규칙과 맞다. `tp_hash`와 같은 방식.
- **파일**: `supabase/migrations/20260114236000_tp_richcompare_slot.sql` (또는 35000 다음 번호).
- **내용**:  
  - `ALTER TABLE public.py_type_object ADD COLUMN tp_richcompare regproc;`  
  - 시그니처 규약: `(self_id UUID, other_id UUID, op INTEGER) RETURNS UUID`. (CPython의 op 인자 타입 `int`에 대응.)  
  - `op`는 CPython과 동일하게 `Py_LT=0, Py_LE, Py_EQ, Py_NE, Py_GT, Py_GE` 값 사용.  
  - 반환 UUID는 **True / False / NotImplemented** 에 대응하는 객체 id.

### 7.2 부트스트랩(싱글턴)

- **파일**: `supabase/migrations/20260114223000_python_bootstrap.sql`
- **내용**: 비교 결과로 쓸 **실제 싱글턴 객체**를 None과 동일한 방식으로 만든다. “id만 상수로 둔다”는 식의 임시 조치는 하지 않는다.  
  - **True / False**: CPython의 `Py_True` / `Py_False` 에 대응. `py_bool_object` 테이블에 각각 한 행씩 두고, 부트스트랩에서 `bool` 타입과 함께 생성한다.  
  - **NotImplemented**: CPython의 `Py_NotImplemented` 에 대응. `py_not_implemented_object` 테이블에 한 행 두고, `NotImplementedType` 타입과 함께 부트스트랩에서 생성한다.
- 스키마는 `supabase/migrations/20260114220000_python_object_schema.sql` 에 `py_bool_object(ob_base, bool_value)`, `py_not_implemented_object(ob_base)` 를 None과 같은 패턴으로 추가해 두었다고 가정한다.

tp_richcompare 슬롯 마이그레이션(§7.1)에서는 이 객체 id를 부트스트랩에서 확정한 상수명(예: `ID_TRUE_OBJ`, `ID_FALSE_OBJ`, `ID_NOT_IMPLEMENTED_OBJ`)으로 참조하면 된다. 부트스트랩이 먼저 돌아가므로, tp_richcompare 단계에서는 이미 DB에 존재한다.

### 7.3 타입별 구현 함수

- **정의 위치**: 위와 동일한 `supabase/migrations/20260114236000_tp_richcompare_slot.sql` 안에 두면, `tp_hash`를 `20260114235000_tp_hash_slot.sql`에 모아둔 것과 같은 구조가 된다.
- **함수 이름·역할**:
  - `public.py_unicode_richcompare(self_id UUID, other_id UUID, op INTEGER) RETURNS UUID`  
    - `op = Py_EQ` 일 때 `py_unicode_object.str_value` 비교 후 True/False id 반환.  
    - 그 외 op는 당장은 `NotImplemented` id 반환해도 됨.
  - `public.py_long_richcompare(self_id UUID, other_id UUID, op INTEGER) RETURNS UUID`  
    - `op = Py_EQ` 일 때 `py_long_object.long_value` 비교 후 True/False id 반환.  
    - 그 외 op는 당장은 `NotImplemented` id 반환해도 됨.
- **등록**: `py_type_object`에서 `tp_name = 'str'` 인 행의 `tp_richcompare`에 `'py_unicode_richcompare'::regproc`, `tp_name = 'int'` 인 행에 `'py_long_richcompare'::regproc` 설정.

### 7.4 범용 디스패치·dict용 보조 함수

- **정의 위치**: 동일 마이그레이션 `20260114236000_tp_richcompare_slot.sql`.
- **함수 이름·역할**:
  - `public.py_object_richcompare(self_id UUID, other_id UUID, op INTEGER) RETURNS UUID`  
    - `self_id`의 `ob_type`으로 `py_type_object.tp_richcompare` 조회 후, NULL이면 NotImplemented id 반환.  
    - 있으면 `tp_richcompare(self_id, other_id, op)` 호출 결과를 그대로 반환.  
    - (추가로 “reverse” 호출은, `py_object_richcompare_eq` 단계에서 처리해도 됨.)
  - `public.py_object_richcompare_eq(a_id UUID, b_id UUID) RETURNS BOOLEAN`  
    - dict 키 동등성 전용.  
    - `py_object_richcompare(a_id, b_id, Py_EQ)` 호출 → 반환 id가 True id이면 TRUE, False id이면 FALSE.  
    - NotImplemented id이면 `py_object_richcompare(b_id, a_id, Py_EQ)` 한 번 더 시도한 뒤, 그 결과가 True id이면 TRUE, 아니면 FALSE.  
    - 두 타입 모두 tp_richcompare가 없거나 둘 다 NotImplemented를 반환하면 FALSE.

### 7.5 dict 쪽과의 연결

- **수정 위치**: dict get/set을 구현하는 마이그레이션(예: `py_dict_get_item` / `py_dict_set_item` 이 들어가는 파일).
- **변경 내용**: 1단계에서는 `py_object_equals_key(me_key, key_id)` 를 쓰고, 2단계 전환 시 이 호출을 `py_object_richcompare_eq(me_key, key_id)` 로 바꾼다.  
  - 문서·주석에 “2단계 전환 시 이곳만 `py_object_richcompare_eq` 로 교체”라고 적어두면, 수정 범위가 한 군데로 명확해진다.

### 7.6 요약 표

| 구분 | 파일 | 내용 |
|------|------|------|
| 슬롯·타입별 함수·디스패치 | `supabase/migrations/20260114236000_tp_richcompare_slot.sql` | `tp_richcompare` 컬럼 추가, `py_unicode_richcompare`, `py_long_richcompare`, `py_object_richcompare`, `py_object_richcompare_eq` 정의 및 str/int에 슬롯 등록 |
| True/False/NotImplemented | `supabase/migrations/20260114223000_python_bootstrap.sql` | 비교 결과용 싱글턴을 None과 동일하게 실제 객체로 생성 (`py_bool_object`·`py_not_implemented_object`). §7.2 참고. |
| dict 키 비교 호출부 | `py_dict_get_item` / `py_dict_set_item` 이 정의된 마이그레이션 | 1단계: `py_object_equals_key` → 2단계: `py_object_richcompare_eq` 로 교체 |

이렇게 두면, 나중에 “tp_richcompare를 어디에 어떻게 붙일지”를 이 문서만 보고도 찾을 수 있다.
