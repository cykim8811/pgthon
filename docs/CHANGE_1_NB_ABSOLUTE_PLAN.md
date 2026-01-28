# 1번 변경: abs()를 nb_absolute 슬롯으로 이전

CPython 고증에 맞추고, tp_name 분기 없이 **PyNumber_Absolute → nb_absolute 슬롯** 경로만 쓰도록 바꾼다.

---

## CPython 쪽 정리

- **builtin_abs**: `return PyNumber_Absolute(obj);` 만 함.
- **PyNumber_Absolute(obj)**  
  - `Py_TYPE(obj)->tp_as_number->nb_absolute` 를 본다.  
  - 없거나 호출 결과가 `NotImplemented` 이면 TypeError.
- **nb_absolute**: `PyNumberMethods` 안의 `unaryfunc`  
  - 시그니처: `(PyObject *o) -> PyObject*`  
  - 반환: 새 객체 또는 `Py_NotImplemented`.

---

## Elytra에서 할 일 (순서)

### 1. 스키마 (CPython 구조 유지)

- **CPython**: `PyTypeObject`에는 `nb_absolute`가 직접 없고, `PyNumberMethods *tp_as_number` 안에 `nb_absolute`가 있음. `tp_as_sequence` → `PySequenceMethods`, `tp_as_mapping` → `PyMappingMethods`와 같은 패턴.
- **220000**: `py_type_object`에는 **컬럼 추가하지 않음**. (주석으로 “tp_as_number는 235500에서 py_number_methods 경유로 추가”만 남김.)
- **235500**: `py_number_methods` 테이블 생성 (`id`, `nb_absolute regproc`) + `py_type_object`에 `tp_as_number uuid REFERENCES py_number_methods(id)` 추가. 226000이 `tp_as_sequence`/`tp_as_mapping`을 ALTER로 넣는 방식과 동일.

### 2. 타입별 nb_absolute 구현

**시그니처 통일**: `(obj_id UUID) RETURNS UUID`  
- 반환: 새 객체 id **또는** NotImplemented 싱글턴 id (`00000000-0000-4000-b000-000000000012`).

**py_long_nb_absolute(obj_id)**  
- `py_long_object` 에 `ob_base = obj_id` 인 행이 있는지로만 “int 여부” 판별. (tp_name 사용 금지.)
- int이면 `ABS(long_value)` 로 새 int 객체 만들어 반환.
- int가 아니면 NotImplemented id 반환.

**py_float_nb_absolute(obj_id)**  
- `py_float_object` 존재 여부로만 float 여부 판별.
- float이면 `ABS(ob_fval)` 로 새 float 객체 만들어 반환.
- 아니면 NotImplemented id 반환.

### 3. 디스패치

**py_object_absolute(obj_id UUID) RETURNS UUID**  
- `ob_type` → `py_type_object.tp_as_number` 조회 (CPython: `Py_TYPE(obj)->tp_as_number`).
- `tp_as_number`가 NULL 이면: 타입 이름만 조회해 `TypeError: bad operand type for abs(): 'tp_name'`.
- NULL 이 아니면: `py_number_methods`에서 해당 id의 `nb_absolute` 조회 (CPython: `tp_as_number->nb_absolute`).  
  - `nb_absolute`가 NULL 이면 위와 동일 TypeError.  
  - 아니면 `nb_absolute(obj_id)` 호출 → 반환 id가 NotImplemented id 이면 동일 TypeError, 그 외는 그대로 반환.

**금지**  
- `py_object_absolute` 안에서 `tp_name` / 타입 이름 문자열로 분기하지 않음.  
- “tp_as_number 유무”, “nb_absolute 유무”, “반환값이 NotImplemented인지”만 사용.

### 4. 슬롯 등록

- int/float용으로 `py_number_methods` 행을 각각 하나씩 만들고, `nb_absolute`에 `py_long_nb_absolute` / `py_float_nb_absolute` 등록.
- `py_type_object.tp_as_number`를 해당 `py_number_methods.id`로 연결 (int/float 타입만).
- 부트스트랩 타입 id는 223000과 동일 상수 사용 (int `00000000-0000-4000-a000-000000000004`, float `00000000-0000-4000-a000-000000000009`).

### 5. py_builtin_abs 교체

- **위치**: 새 마이그레이션에서 `CREATE OR REPLACE FUNCTION public.py_builtin_abs ...` 로 덮어씀.
- **내용**  
  - 인자 1개인지 등 기본 검사는 유지해도 됨.  
  - **내부 구현은 전부 제거하고** `RETURN public.py_object_absolute(obj_id);` 한 줄만 두고, 예외는 그대로 전파.
- **제거**  
  - `tp_name` / `obj_type_name` 분기, int/float 전용 로직, 별도 INSERT 등 모두 제거.

---

## 마이그레이션 배치

| 작업 | 파일 |
|------|------|
| py_type_object 초기 정의 | `20260114220000_python_object_schema.sql` — nb_absolute/tp_as_number 컬럼 없음 (주석만) |
| py_number_methods 생성 + tp_as_number 추가 + 타입별 함수 + 디스패치 + 슬롯 등록 + py_builtin_abs 교체 | `20260114235500_nb_absolute_slot.sql` (235000 다음, 236000 이전) |

225000은 수정하지 않는다.  
225000이 이미 `py_builtin_abs`를 정의하고 __builtins__에 등록해 두었으므로, 235500에서 “abs가 호출될 때 불리는 함수 몸통”만 슬롯 경유로 바꾸면 된다.

---

## 임시방편 금지 체크리스트

- [ ] `py_object_absolute` 안에 `tp_name` / `'int'` / `'float'` 분기 없음.
- [ ] 타입 판별은 “해당 구체 테이블에 행이 있는지”만 사용 (py_long_object, py_float_object).
- [ ] NotImplemented 는 부트스트랩 싱글턴 id 상수 하나만 사용.
- [ ] `py_builtin_abs` 안에는 `py_object_absolute(obj_id)` 호출과 예외 전파만 있음.

---

## 이후 확장

- 나중에 complex 등이 들어오면, 그 타입용 `py_*_nb_absolute` 하나 추가하고 해당 타입에만 `nb_absolute` 슬롯 등록하면 됨.
- `py_object_absolute` / `py_builtin_abs` / 다른 슬롯 쪽 코드는 수정하지 않아도 됨.
