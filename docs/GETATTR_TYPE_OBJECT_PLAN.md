# getattr(Type, name) 수정 계획 — CPython 고증·임시방편 없음

타입 객체에서 속성 조회(`getattr(Type, name)`)가 동작하도록 `py_object_getattr`를 수정하기 위한 계획이다.  
**CPython 고증**: Class.attr 시 Class의 `__dict__`(tp_dict) 및 MRO에서 조회.  
**임시방편 금지**: `tp_name` 비교 없이, **테이블 존재(py_type_object)** 만으로 타입 객체 여부 판별.

---

## 1. 목표

- **현상**: `getattr(T, "f")` 시 T의 tp_dict가 아닌 type(T)의 tp_dict에서만 검색하여, T에 있는 "f"를 찾지 못함.
- **목표**: `obj_id`가 타입 객체(즉 `py_type_object` 행 존재)일 때는 **obj_id 자신의 tp_dict(및 tp_bases)** 에서 name을 검색하도록 함.

---

## 2. CPython 고증

- **Class.attr** (또는 `getattr(Class, "attr")`): Class는 타입 객체. CPython은 Class의 `__dict__`(tp_dict) 및 Class의 MRO에서 "attr"을 찾음.
- **instance.attr**: 인스턴스의 타입(Class)의 tp_dict 및 MRO에서 찾음. (인스턴스 __dict__ 우선은 기존 Phase 2대로.)
- **정리**:  
  - **obj가 인스턴스** → 검색 기준 타입 = type(obj).  
  - **obj가 타입** → 검색 기준 타입 = obj (그 타입 자신).

---

## 3. 수정 위치·내용

### 3.1 수정 파일

- **파일**: `supabase/migrations/20260114235000_tp_hash_slot.sql`
- **대상**: `py_object_getattr` 함수 (기존 마이그레이션 수정 원칙 준수).

### 3.2 수정 내용

- **현재**: 항상 `lookup_in_type_and_bases(type_id, obj_id, name_str_id)` 호출.  
  → `type_id` = type(obj) 이므로, 타입 객체 obj에 대해서는 type의 tp_dict만 검색됨.

- **수정 후**:
  1. **검색 기준 타입** `search_type_id` 결정:
     - `obj_id`에 대해 `py_type_object`에 행이 있으면 (obj가 타입) → `search_type_id := obj_id`.
     - 없으면 (obj가 인스턴스 등) → `search_type_id := type_id`.
  2. `lookup_in_type_and_bases(search_type_id, obj_id, name_str_id)` 호출.

- **타입 객체 판별**:  
  `EXISTS (SELECT 1 FROM public.py_type_object WHERE ob_base = obj_id)` 만 사용.  
  **`tp_name` 또는 타입 이름 문자열 비교 사용 금지.**

### 3.3 코드 수준 변경 요약

- `py_object_getattr` 내부에서:
  - `type_id` 계산은 그대로 두고,
  - `search_type_id`를 새로 두어:  
    - `py_type_object`에 `ob_base = obj_id`인 행이 있으면 `search_type_id := obj_id`,  
    - 없으면 `search_type_id := type_id`.
  - 기존 `lookup_in_type_and_bases(type_id, obj_id, name_str_id)` 호출을  
    `lookup_in_type_and_bases(search_type_id, obj_id, name_str_id)` 로 변경.

---

## 4. 임시방편 금지 체크리스트

- [ ] 타입 객체 판별: **py_type_object 테이블 존재·행 조회**만 사용. `tp_name = 'type'` 등 문자열 비교 금지.
- [ ] 검색 로직: **lookup_in_type_and_bases**에 넘기는 첫 인자만 `search_type_id`로 바꿈. 그 외 분기·특례 추가 없음.
- [ ] 스키마·다른 함수: 변경 없음. `lookup_in_type_and_bases` 시그니처·동작 유지.

---

## 5. 검증

- **기존 테스트**: Phase 45 Bound Method 통합 테스트  
  - Test 2: `getattr(Type, "f")` → len (함수 그대로)  
  → 수정 후 이 테스트가 통과해야 함.
- **회귀**: Phase 42, 43, 44 (LOAD_ATTR / STORE_ATTR) 등 기존 getattr 경로 테스트는 그대로 통과해야 함.  
  인스턴스에 대해서는 `search_type_id = type_id`로 동작이 기존과 동일함.

---

## 6. 요약

| 항목 | 내용 |
|------|------|
| **수정 대상** | `py_object_getattr` (235000) |
| **변경** | 검색 기준 타입을 `type_id` → `search_type_id`로. 타입 객체일 때 `search_type_id = obj_id`. |
| **판별** | `py_type_object`에 `ob_base = obj_id` 행 존재 여부만 사용 |
| **검증** | Phase 45 통과, Phase 42·43·44 회귀 없음 |

**CPython 고증**: Class.attr 시 Class의 tp_dict에서 조회.  
**임시방편 없음**: tp_name 미사용, 기존 함수·스키마만 활용.
