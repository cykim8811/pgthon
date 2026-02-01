# bytes 연산 설계 — CPython 고증·임시구현 없음

CPython의 `PyBytesObject` 및 bytes의 시퀀스 연산(+, *, len)·비교를 Elytra에서 슬롯 기반으로 구현하기 위한 설계 문서다.  
**임시방편 금지**: `tp_name`/타입 이름 문자열 분기 없이, 테이블 존재·슬롯 디스패치만 사용한다.

---

## 1. CPython 고증 요약

### 1.1 PyBytesObject

| CPython | Elytra |
|--------|--------|
| `PyBytesObject.ob_sval` (byte array) | `py_bytes_object.bytes_value` (bytea) |
| bytes는 **시퀀스** (tp_as_sequence): sq_length, sq_concat, sq_repeat | bytes 타입에 tp_as_sequence 등록 (nb_* 아님) |

- 스키마: **이미 존재**. `20260114220000_python_object_schema.sql`에 `py_bytes_object(ob_base, bytes_value)` 정의됨.
- 부트스트랩: **이미 존재**. `20260114223000_python_bootstrap.sql`에 bytes 타입·tp_dict·tp_bases 등록됨.
- CPython: bytes의 `+`·`*`는 **PySequenceMethods**(sq_concat, sq_repeat)로 처리. PyNumberMethods 아님.

### 1.2 시퀀스 연산 (bytes + bytes, bytes * int)

| 연산 | CPython | Elytra 대응 |
|------|--------|-------------|
| bytes + bytes | sq_concat(left, right) → 새 bytes | py_bytes_sq_concat(left_id, right_id) → 새 bytes id |
| bytes * int / int * bytes | sq_repeat(seq, n) | py_bytes_sq_repeat(seq_id, n) |
| len(bytes) | sq_length(obj) | py_bytes_sq_length(obj_id) → length |

- **타입 판별**: `EXISTS (SELECT 1 FROM py_bytes_object WHERE ob_base = id)` 만 사용. **tp_name 사용 금지.**
- bytes + str / bytes * float 등은 CPython에서 TypeError. sq_concat·sq_repeat 내부에서 right가 bytes가 아니거나 n이 int가 아니면 에러.

### 1.3 tp_hash (PyObject_Hash)

- **이미 구현·등록됨**. `20260114235000_tp_hash_slot.sql`에 `py_bytes_hash(obj_id)` 정의 및 bytes 타입 tp_hash 등록됨. 추가 작업 없음.

### 1.4 tp_richcompare (PyObject_RichCompare)

- CPython: bytes는 bytes끼리만 비교. lexicographic (바이트 열 순서). Py_LT, Py_LE, Py_EQ, Py_NE, Py_GT, Py_GE 지원.
- Elytra: `py_bytes_richcompare(self_id, other_id, op)`. other가 bytes가 아니면 NotImplemented. bytes면 bytes_value 바이트 열 비교.

### 1.5 sq_concat / sq_repeat 시맨틱

- **sq_concat(left, right)**: CPython에서 left가 bytes일 때만 호출됨. right가 bytes가 아니면 TypeError. Elytra도 동일: right가 `py_bytes_object`가 아니면 TypeError (py_err_set_type_error).
- **sq_repeat(seq, n)**: seq가 bytes일 때만 호출. n &lt; 0이면 CPython은 빈 bytes 반환. Elytra 동일.

---

## 2. 현재 Elytra 상태

| 항목 | 상태 |
|------|------|
| py_bytes_object 테이블 | ✅ 220000에 정의 (ob_base, bytes_value) |
| bytes 타입 (py_type_object) | ✅ 223000 부트스트랩에 존재 |
| tp_hash (bytes) | ✅ 235000에 py_bytes_hash 정의·등록 |
| tp_as_sequence (bytes) | ❌ 미구현 (226000에서 str/list/tuple만 등록) |
| sq_length / sq_concat / sq_repeat (bytes) | ❌ 미구현 |
| tp_richcompare (bytes) | ❌ 미구현 (236000에서 str/int/float만 등록) |

- **결론**: bytes용 **py_bytes_sq_length, py_bytes_sq_concat, py_bytes_sq_repeat** 구현 및 **tp_as_sequence** 신규 행 생성·연결. **tp_richcompare** 구현 및 bytes 타입에 등록.
- **새 테이블/컬럼 불필요**. 기존 스키마·부트스트랩만 활용.

---

## 3. 구현 단계 (임시방편 없음)

### 3.1 타입별 함수 (테이블 존재로만 판별)

- **py_bytes_sq_length(obj_id)**  
  - `py_bytes_object` 존재 여부로만 판별. `length(bytes_value)` 반환. 그 외 TypeError(py_err_set_type_error).

- **py_bytes_sq_concat(left_id, right_id)**  
  - left가 `py_bytes_object`가 아니면 TypeError.  
  - right가 `py_bytes_object`가 아니면 TypeError (CPython: "can only concatenate bytes (not \"str\") to bytes" 등).  
  - 둘 다 bytes면 `bytes_value || bytes_value`로 새 bytes 객체 id 반환.

- **py_bytes_sq_repeat(seq_id, n integer)**  
  - seq가 `py_bytes_object`가 아니면 TypeError.  
  - n &lt;= 0이면 빈 bytes (E'\\\\x'::bytea) 반환. n &gt; 0이면 bytes_value를 n번 반복한 새 bytes id 반환.

- **py_bytes_richcompare(self_id, other_id, op)**  
  - self는 bytes로 가정(디스패치에서 bytes일 때만 호출). other가 bytes가 아니면 NotImplemented.  
  - other가 bytes면 bytes_value 바이트 열 lexicographic 비교. Py_LT~Py_GE 모두 구현. True/False/NotImplemented id 반환.

- **공통**: 함수 내부에서 **tp_name을 조회하거나 문자열 비교하지 않음**. `EXISTS (SELECT 1 FROM py_bytes_object WHERE ob_base = id)` 만 사용.

### 3.2 슬롯 등록

- **tp_as_sequence (bytes)**  
  - **새** py_sequence_methods 행 생성: sq_length = py_bytes_sq_length, sq_concat = py_bytes_sq_concat, sq_repeat = py_bytes_sq_repeat.  
  - bytes 타입의 tp_as_sequence를 해당 행으로 UPDATE. (현재 bytes는 tp_as_sequence = NULL.)

- **tp_richcompare (bytes)**  
  - 236000에서 str/int/float에 tp_richcompare 등록하는 방식과 동일하게, bytes 타입의 tp_richcompare에 `py_bytes_richcompare` 등록.

### 3.3 디스패치·opcode

- **py_object_size** (len): tp_as_sequence → sq_length. bytes에 tp_as_sequence만 채우면 len(bytes) 동작.
- **py_object_add** (bytes + bytes): nb_add 실패 후 py_sequence_concat 호출. bytes에 sq_concat만 등록하면 됨.
- **py_object_multiply** (bytes * int): nb_multiply 실패 후 py_sequence_repeat 호출. bytes에 sq_repeat만 등록하면 됨.
- **py_object_richcompare**: bytes에 tp_richcompare만 등록하면 됨.
- **BINARY_ADD / BINARY_MULTIPLY / COMPARE_OP**: 수정 없음.

### 3.4 테스트

- len(bytes), bytes + bytes, bytes * int, int * bytes.
- bytes &lt; bytes, bytes == bytes.
- bytes + str → TypeError, bytes * float → TypeError (또는 기존 에러 경로).
- 바이트코드: LOAD_CONST bytes, LOAD_CONST bytes, BINARY_ADD, RETURN_VALUE 등.

---

## 4. 마이그레이션 배치

- **원칙**: 기존 마이그레이션을 코드처럼 관리. 스키마 변경 없으므로 **기존 파일 수정**만.
- **제안**:
  - **py_bytes_sq_length, py_bytes_sq_concat, py_bytes_sq_repeat**: `20260114226000_type_method_slots.sql`에 추가 (다른 sq_* 함수들과 함께).
  - **bytes용 py_sequence_methods 행 생성 및 bytes 타입 tp_as_sequence 연결**: 같은 226000의 DO 블록에서 INSERT·UPDATE 추가.
  - **py_bytes_richcompare**: `20260114236000_tp_richcompare_slot.sql`에 추가.
  - **bytes tp_richcompare 등록**: 같은 236000의 DO 블록에 bytes 추가.

---

## 5. 임시방편 금지 체크리스트

- [ ] bytes 여부 판별: **py_bytes_object** 테이블 존재로만. tp_name = 'bytes' 분기 금지.
- [ ] 디스패치: **py_object_add**·**py_object_multiply**·**py_object_size**·**py_object_richcompare** 는 수정 없이, bytes 타입의 **슬롯만** 등록.
- [ ] 에러 메시지: TypeError 시 타입 이름이 필요하면 **py_type_object.tp_name** 한 번만 조회해 메시지에 넣는 것은 허용. **분기 로직**에서 tp_name 사용 금지.

---

## 6. 작업 목록·의존관계·실행 순서

### 6.1 작업 ID 정의

| ID | 작업 | 산출물 |
|----|------|--------|
| **A** | py_bytes_sq_length 구현 | 226000에 함수 추가 |
| **B** | py_bytes_sq_concat 구현 | 226000에 함수 추가 |
| **C** | py_bytes_sq_repeat 구현 | 226000에 함수 추가 |
| **D** | bytes용 tp_as_sequence 등록 | 226000 DO: INSERT py_sequence_methods, UPDATE bytes 타입 |
| **E** | py_bytes_richcompare 구현 | 236000에 함수 추가 |
| **F** | bytes tp_richcompare 등록 | 236000 DO에 bytes UPDATE 추가 |
| **G** | bytes 연산·비교 테스트 | 39 또는 40번 테스트 파일, run_tests.sh |

### 6.2 의존관계

```
A ─┐
B ─┼─→ D   (D는 A,B,C 완료 후 실행: 한 DO에서 세 함수 모두 사용)
C ─┘

E ──→ F   (F는 E 완료 후)

D ─┐
   ├─→ G   (테스트는 D, F 완료 후)
F ─┘
```

- **A, B, C, E**: 선행 없음. 서로 독립.
- **D**: A, B, C에 의존 (세 함수를 참조하는 py_sequence_methods 행 생성).
- **F**: E에 의존.
- **G**: D, F에 의존 (len/+/*/비교 모두 검증하려면 D와 F 필요).

### 6.3 실행 순서 (가장 먼저 할 일부터)

| 순위 | 작업 | 선행 | 비고 |
|------|------|------|------|
| **1** | **A** py_bytes_sq_length | 없음 | 226000에 함수 정의 |
| **2** | **B** py_bytes_sq_concat | 없음 | 226000에 함수 정의 |
| **3** | **C** py_bytes_sq_repeat | 없음 | 226000에 함수 정의 |
| **4** | **E** py_bytes_richcompare | 없음 | 236000에 함수 정의 |
| **5** | **D** bytes tp_as_sequence 등록 | A, B, C | 226000 DO에서 INSERT·UPDATE |
| **6** | **F** bytes tp_richcompare 등록 | E | 236000 DO에 bytes 추가 |
| **7** | **G** 테스트 추가 | D, F | 테스트 파일 + run_tests.sh |

- **먼저 실행할 것**: **A, B, C, E** 중 아무 순서로나 구현 (보통 파일 순서대로 A → B → C, 그 다음 236000에서 E).
- 그 다음 **D**, 그 다음 **F**, 마지막 **G**.

---

## 7. 요약

| 단계 | 내용 | 산출물 |
|------|------|--------|
| 1 | py_bytes_sq_length, sq_concat, sq_repeat 정의 | 226000 |
| 2 | bytes용 py_sequence_methods 행 생성·연결 | 226000 DO |
| 3 | py_bytes_richcompare 정의 | 236000 |
| 4 | bytes tp_richcompare 등록 | 236000 DO |
| 5 | 테스트: len(bytes), bytes+bytes, bytes*n, 비교, 바이트코드 | supabase/tests/, run_tests.sh |

**CPython 고증**: bytes는 시퀀스 슬롯(sq_length, sq_concat, sq_repeat)으로 +, *, len 지원. bytes끼리만 비교.  
**임시구현 없음**: 타입 판별은 전부 테이블 존재·슬롯 디스패치로만 수행.
