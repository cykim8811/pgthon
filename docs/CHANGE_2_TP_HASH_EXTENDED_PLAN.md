# 2번 변경: Hashable 범위 확장 (CPython 고증)

tp_hash를 bytes / float / bool / NoneType / tuple 에 등록해, CPython과 같은 “hashable인 타입 집합”으로 맞춘다.  
타입 이름 분기·임시방편 없이, **구체 테이블 존재 여부 + tp_hash 슬롯 호출**만 사용한다.

---

## CPython 쪽 정리

| 타입   | hashable | 비고 |
|--------|----------|------|
| tuple  | ✅ 조건부 | 모든 원소가 hashable일 때만. 원소 해시를 조합해 tuple 해시 계산. |
| bytes  | ✅       | 바이트열 내용 기준 해시. |
| float  | ✅       | _Py_HashDouble 등 값 기준 해시. |
| bool   | ✅       | hash(True)==1, hash(False)==0. |
| None   | ✅       | hash(None) 상수. |

---

## Elytra에서 할 일 (순서)

### 1. 타입별 tp_hash 구현

**판별**: 해당 구체 테이블에 `ob_base = obj_id` 인 행이 있는지로만 판별. `tp_name` 사용 금지.

- **py_bytes_hash(obj_id)**  
  - `py_bytes_object` 존재 여부로만 판별.  
  - `bytes_value`에 대한 결정적 해시 계산 (예: `hashtext(encode(bytes_value, 'hex'))::bigint` 등).  
  - 빈 bytes는 0 등 상수 반환.

- **py_float_hash(obj_id)**  
  - `py_float_object` 존재 여부로만 판별.  
  - `ob_fval`에 대한 결정적 해시.  
  - CPython은 _Py_HashDouble 사용. Elytra는 “같은 double이면 같은 해시”만 지키면 되므로, 예: `hashtext(ob_fval::text)::bigint` 또는 비트 정규화 후 해시.

- **py_bool_hash(obj_id)**  
  - `py_bool_object` 존재 여부로만 판별.  
  - `bool_value = true` → 1, `false` → 0 반환 (CPython과 동일).

- **py_none_hash(obj_id)**  
  - `py_none_object` 존재 여부로만 판별.  
  - None은 싱글턴이므로 고정 상수 하나 반환 (예: 0 또는 CPython처럼 id 기반에 가깝게 둔 상수).

- **py_tuple_hash(obj_id)**  
  - `py_tuple_object` 존재 여부로만 판별.  
  - `ob_item`이 NULL이거나 길이 0이면 상수(예: 0) 반환.  
  - 그 외: 각 원소에 대해 `py_object_hash(elem_id)` 호출 (재귀적으로 tp_hash 사용 → unhashable 원소 있으면 TypeError 전파).  
  - 원소 해시들을 CPython tuplehash 스타일로 결합:  
    `mult = 1000003`, `x = (x * mult) # elem_hash` 형태 (또는 동등한 결합 공식).  
  - 최종값을 Py_hash_t 범위에 맞게 정규화 (예: signed 64비트).

### 2. 슬롯 등록

- bytes / float / bool / NoneType / tuple 타입에 대해  
  `UPDATE py_type_object SET tp_hash = 'py_*_hash'::regproc WHERE ob_base = <타입_id>`.

- 부트스트랩 타입 id (223000과 동일):
  - bytes: `00000000-0000-4000-a000-000000000012`
  - float: `00000000-0000-4000-a000-000000000009`
  - bool: `00000000-0000-4000-a000-000000000013`
  - NoneType: `00000000-0000-4000-a000-000000000008`
  - tuple: `00000000-0000-4000-a000-000000000007`

### 3. 마이그레이션 배치

- **파일**: 새 마이그레이션 `20260114235800_tp_hash_extended.sql` (235500 다음, 236000 이전).
- **내용**: 위 5개 타입별 hash 함수 정의 + 슬롯 등록만.  
- 235000은 수정하지 않고, “확장”만 추가하는 방식으로 진행.

### 4. 임시방편 금지 체크리스트

- [ ] 모든 타입별 hash 함수는 “해당 구체 테이블 존재 여부”만으로 타입 판별.
- [ ] `tp_name` / 타입 이름 문자열 분기 없음.
- [ ] tuple은 원소마다 `py_object_hash(elem_id)` 호출로만 재귀 (슬롯 경유).
- [ ] bool: 1/0만 반환. None: 고정 상수. bytes/float: 결정적·재현 가능.

---

## 주의

- **list / dict**는 계속 tp_hash = NULL (unhashable) 유지.
- **tuple**은 “원소가 하나라도 unhashable이면 TypeError”가 나도록, 원소 해시 시 `py_object_hash`에만 의존하면 됨.
