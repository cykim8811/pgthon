# float 타입 구현 설계 — CPython 고증·임시구현 없음

CPython의 `PyFloatObject` 및 float의 수치 연산·해시·비교를 Elytra에서 슬롯 기반으로 구현하기 위한 설계 문서다.  
**임시방편 금지**: `tp_name`/타입 이름 문자열 분기 없이, 테이블 존재·슬롯 디스패치만 사용한다.

---

## 1. CPython 고증 요약

### 1.1 PyFloatObject

| CPython | Elytra |
|--------|--------|
| `PyFloatObject.ob_fval` (double) | `py_float_object.ob_fval` (double precision) |
| `PyFloat_Type` (tp_as_number, tp_hash, tp_richcompare) | float 타입에 tp_as_number, tp_hash, tp_richcompare 등록 |

- 스키마: **이미 존재**. `20260114220000_python_object_schema.sql`에 `py_float_object(ob_base, ob_fval)` 정의됨.
- 부트스트랩: **이미 존재**. `20260114223000_python_bootstrap.sql`에 float 타입·tp_dict·tp_bases 등록됨.

### 1.2 수치 연산 (PyNumber_Add / Subtract / Multiply)

| 연산 | CPython | Elytra 대응 |
|------|--------|-------------|
| float + float | float_add → 새 float | py_float_nb_add(left, right) → 새 float id |
| float + int | float 쪽 nb_add에서 int를 double로 변환 후 덧셈 | py_float_nb_add: right가 py_long_object면 long_value를 double로 더함 |
| int + float | PyNumber_Add가 left(int) nb_add 실패 후 right(float) nb_add 호출 | 기존 py_object_add_via_nb 반대 호출로 처리 (수정 없음) |
| float - float / float - int | nb_subtract | py_float_nb_subtract (동일 coercion 규칙) |
| float * float / float * int | nb_multiply | py_float_nb_multiply (동일 coercion 규칙) |

- **타입 판별**: `EXISTS (SELECT 1 FROM py_float_object WHERE ob_base = id)` / `py_long_object` 존재로만 판별. **tp_name 사용 금지.**

### 1.3 tp_hash (PyObject_Hash)

- CPython: float는 hash 가능. `_Py_HashDouble(ob_fval)` 등으로 해시값 계산.
- Elytra: `py_float_tp_hash(obj_id) RETURNS BIGINT` 구현 후 float 타입의 tp_hash 슬롯에 등록.
- PostgreSQL: `double precision`에 대한 해시는 일관성만 유지하면 됨. (예: `hashtext(ob_fval::text)` 또는 CPython과 유사한 비트 패턴 해시. 최소 구현은 `hashtext`로 가능하나, CPython은 특정 규칙 사용 — 필요 시 나중에 정확히 맞춤.)

### 1.4 tp_richcompare (PyObject_RichCompare)

- CPython: float는 Py_LT, Py_LE, Py_EQ, Py_NE, Py_GT, Py_GE 전부 지원. float–float, float–int 비교 시 int는 double로 변환.
- Elytra: `py_float_richcompare(self_id, other_id, op)` 구현. other가 float이면 ob_fval 비교; other가 int면 long_value를 double로 변환 후 비교. 그 외 NotImplemented.
- 기존 `py_object_richcompare` 디스패치·반대 호출은 수정 없이, float 타입에 tp_richcompare만 등록하면 됨.

### 1.5 nb_absolute (abs)

- **이미 구현됨**. `20260114235500_nb_absolute_slot.sql`에 `py_float_nb_absolute` 정의 및 float의 tp_as_number에 nb_absolute 등록됨. float 타입은 이미 **tp_as_number**를 갖고 있음 (nb_add/nb_subtract/nb_multiply만 없음).

---

## 2. 현재 Elytra 상태

| 항목 | 상태 |
|------|------|
| py_float_object 테이블 | ✅ 220000에 정의 (ob_base, ob_fval) |
| float 타입 (py_type_object) | ✅ 223000 부트스트랩에 존재 |
| float tp_as_number | ✅ 235500에서 생성·연결 (nb_absolute만 설정) |
| py_float_nb_absolute | ✅ 235500에 정의 |
| nb_add / nb_subtract / nb_multiply (float) | ❌ 미구현 |
| tp_hash (float) | ❌ 미구현 (235000에서 int/str 등만 등록) |
| tp_richcompare (float) | ❌ 미구현 (236000에서 int/str 등만 등록) |

- **결론**: float용 **nb_add, nb_subtract, nb_multiply** 구현 및 기존 float용 py_number_methods 행에 UPDATE로 슬롯 추가. **tp_hash, tp_richcompare** 구현 및 float 타입에 등록.  
- **새 테이블/컬럼 불필요**. 기존 스키마·부트스트랩만 활용.

---

## 3. 구현 단계 (임시방편 없음)

### 3.1 타입별 함수 (테이블 존재로만 판별)

- **py_float_nb_add(left_id, right_id)**
  - left가 `py_float_object`가 아니면 → NotImplemented id 반환.
  - right가 `py_float_object` → ob_fval 끼리 덧셈, 새 float 객체 id 반환.
  - right가 `py_long_object` → right의 long_value를 double로 변환 후 left ob_fval과 덧셈, 새 float id 반환.
  - 그 외 → NotImplemented id 반환.
- **py_float_nb_subtract(left_id, right_id)**  
  - 동일 규칙: left는 반드시 float. right는 float 또는 int(변환 후 뺄셈). 그 외 NotImplemented.
- **py_float_nb_multiply(left_id, right_id)**  
  - 동일 규칙: left는 반드시 float. right는 float 또는 int. 그 외 NotImplemented.

- **py_float_tp_hash(obj_id)**  
  - `py_float_object` 존재 여부로만 판별. ob_fval에 대한 BIGINT 해시 반환. (CPython 호환은 별도 이슈로, 1단계는 일관된 해시만 보장.)

- **py_float_richcompare(self_id, other_id, op)**  
  - self는 float로 가정(디스패치에서 float일 때만 호출). other가 float면 ob_fval 비교; other가 int면 long_value를 double로 변환 후 비교. Py_LT~Py_GE 모두 구현. 불가능한 조합은 NotImplemented id 반환.

- **공통**: 함수 내부에서 **tp_name을 조회하거나 문자열 비교하지 않음**. `EXISTS (SELECT 1 FROM py_float_object WHERE ob_base = id)` 및 `py_long_object` 존재 여부만 사용.

### 3.2 슬롯 등록

- **nb_add, nb_subtract, nb_multiply**  
  - float 타입이 이미 갖고 있는 **tp_as_number** 행(235500에서 만든 것)을 **UPDATE**하여 nb_add, nb_subtract, nb_multiply를 설정.  
  - 새 py_number_methods 행을 만들지 않음 (기존 int/float 패턴과 동일: 238000에서 int는 UPDATE, str은 INSERT).

- **tp_hash**  
  - 235000에서 str/int 등에 tp_hash 등록하는 방식과 동일하게, float 타입의 tp_hash에 `py_float_tp_hash` 등록.

- **tp_richcompare**  
  - 236000에서 str/int에 tp_richcompare 등록하는 방식과 동일하게, float 타입의 tp_richcompare에 `py_float_richcompare` 등록.

### 3.3 디스패치·opcode

- **py_object_add_via_nb**, **py_object_subtract_via_nb**, **py_object_multiply_via_nb**, **py_object_richcompare**, **py_object_hash**  
  - **수정 없음**. 슬롯만 채우면 float가 자동으로 참여.
- **BINARY_ADD / BINARY_SUBTRACT / BINARY_MULTIPLY / COMPARE_OP**  
  - **수정 없음**. 기존 opcode가 위 디스패치 함수만 호출하므로, float 슬롯 등록으로 끝.

### 3.4 테스트

- **nb_add**: float+float, float+int, int+float → 결과 float 값 검증. float+str → TypeError(NotImplemented).
- **nb_subtract**: float-float, float-int, int-float.
- **nb_multiply**: float*float, float*int, int*float.
- **tp_hash**: float 객체 hash 호출 시 예외 없이 BIGINT 반환. (동일 float → 동일 해시.)
- **tp_richcompare**: float–float, float–int, int–float에 대해 <, <=, ==, !=, >, >= 결과 검증. float–str → TypeError.
- **통합**: 바이트코드 `1.5 + 2`, `1.5 - 0.5`, `2.0 * 3`, `1.0 < 2.0` 등으로 py_eval_frame 경로 검증.

---

## 4. 마이그레이션 배치

- **원칙**: 기존 마이그레이션을 코드처럼 관리. 스키마 변경(테이블/컬럼 추가)이 없으므로 **기존 파일 수정**으로 진행 가능.  
- **제안**:
  - **방안 A**: float 전용 마이그레이션 하나 추가 (예: `20260114239200_float_slots.sql`).  
    - 내용: py_float_nb_add, py_float_nb_subtract, py_float_nb_multiply, py_float_tp_hash, py_float_richcompare 정의 + float의 tp_as_number UPDATE + float의 tp_hash·tp_richcompare UPDATE.
  - **방안 B**: nb_add는 238000, nb_subtract는 238500, nb_multiply는 239000에 각각 float 분을 **추가** (기존 int/str과 같은 파일에 py_float_* 정의 및 float 슬롯 UPDATE).  
    - tp_hash는 235000, tp_richcompare는 236000에 float 분 추가.

- **권장**: **방안 A** — float를 한 단위로 묶어서 한 파일에서 완성하면 추적·검증이 쉽고, 기존 int/str 마이그레이션은 건드리지 않는다. (README 규칙: “기존 스키마 생성 코드 수정”은 스키마 변경 시이고, 여기서는 스키마 변경 없음.)

---

## 5. 임시방편 금지 체크리스트

- [ ] float 여부 판별: **py_float_object** 테이블 존재로만. tp_name = 'float' 분기 금지.
- [ ] int 여부 판별: **py_long_object** 존재로만. tp_name = 'int' 분기 금지.
- [ ] 디스패치: **py_object_add_via_nb** 등 기존 함수는 그대로 두고, float 타입의 **슬롯만** 등록.
- [ ] 에러 메시지: TypeError 시 타입 이름이 필요하면 **py_type_object.tp_name**을 한 번만 조회해 메시지에 넣는 것은 허용 (CPython도 타입 이름을 에러에 포함). 단 **분기 로직**에서 tp_name 사용 금지.
- [ ] float–int 변환: int → double은 **py_long_object.long_value**를 double로 캐스트. 별도 “float() builtin” 호출이나 특수 경로 금지.

---

## 6. 의존 관계

- 220000 (py_float_object), 223000 (float 타입), 235500 (float tp_as_number + nb_absolute) → 선행 완료.
- 238000 (py_object_add_via_nb, BINARY_ADD), 238500 (nb_subtract), 239000 (nb_multiply), 235000 (tp_hash), 236000 (tp_richcompare) → **로직 수정 없이** float용 함수·슬롯만 추가하면 됨.

---

## 7. 요약

| 단계 | 내용 | 산출물 |
|------|------|--------|
| 1 | py_float_nb_add / nb_subtract / nb_multiply 정의 (left=float, right=float 또는 int) | 새 마이그레이션 또는 238000/238500/239000에 추가 |
| 2 | float의 tp_as_number에 nb_add, nb_subtract, nb_multiply UPDATE | 동일 마이그레이션 |
| 3 | py_float_tp_hash, py_float_richcompare 정의 | 동일 또는 235000/236000 |
| 4 | float의 tp_hash, tp_richcompare 등록 | 동일 |
| 5 | 테스트: float 연산·비교·해시·바이트코드 통합 | supabase/tests/, run_tests.sh |

**CPython 고증**: float–int 혼합 연산 시 int를 double로 변환하는 쪽은 float의 nb_* 슬롯에서 처리.  
**임시구현 없음**: 타입 판별은 전부 테이블 존재·슬롯 디스패치로만 수행.
