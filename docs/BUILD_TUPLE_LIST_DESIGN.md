# BUILD_TUPLE / BUILD_LIST opcode 설계 — CPython 고증·임시구현 없음

CPython의 **BUILD_TUPLE**(opcode 102)·**BUILD_LIST**(opcode 103)를 Elytra VM에서 구현하기 위한 설계 문서다.  
**임시방편 금지**: `tp_name`/타입 이름 문자열 분기 없이, 기존 스키마·부트스트랩만 사용한다.

---

## 1. CPython 고증 요약

### 1.1 Opcode 시맨틱

| Opcode | CPython | Elytra 대응 |
|--------|--------|-------------|
| **BUILD_TUPLE** 102 | operand = count. 스택에서 count개 pop (TOS가 튜플의 **마지막** 원소). 새 `PyTupleObject` 생성 후 push. | `py_opcode_BUILD_TUPLE(frame_id, count)`: count개 pop → `py_tuple_object` 행 생성 → push |
| **BUILD_LIST** 103 | operand = count. 스택에서 count개 pop (TOS가 리스트의 **마지막** 원소). 새 `PyListObject` 생성 후 push. | `py_opcode_BUILD_LIST(frame_id, count)`: count개 pop → `py_list_object` 행 생성 → push |

- **스택 순서**: CPython에서 첫 번째 pop한 값이 튜플/리스트의 **인덱스 count-1** (마지막 원소), 마지막으로 pop한 값이 **인덱스 0** (첫 원소). 즉 `stack[..., a, b, c]`에서 BUILD_*(3)이면 pop 순서 c, b, a → 결과 (a, b, c) / [a, b, c].
- **instruction 크기**: Python 3.6+ 기준 2바이트 (opcode 1 + operand 1). `py_get_opcode_size(102)` = `py_get_opcode_size(103)` = 2. 수정 불필요.

### 1.2 CPython 참조

- `Python/ceval.c`: `BUILD_TUPLE`, `BUILD_LIST` — 스택에서 count개 pop 후 `PyTuple_New`/`PyList_New`로 새 객체 생성, 원소 순서 유지.
- `Include/opcode.h`: 102 = BUILD_TUPLE, 103 = BUILD_LIST.

---

## 2. 현재 Elytra 상태

| 항목 | 상태 |
|------|------|
| `py_tuple_object` (ob_base, ob_item uuid[]) | ✅ 220000에 정의 |
| `py_list_object` (ob_base, ob_item uuid[]) | ✅ 220000에 정의 |
| tuple / list 타입 (py_type_object) | ✅ 223000 부트스트랩에 존재 |
| sq_length (list/tuple) | ✅ 226000에 py_list_sq_length, py_tuple_sq_length 등록 |
| **BUILD_TUPLE / BUILD_LIST opcode** | ❌ 미구현 |

- **결론**: 새 테이블/컬럼 불필요. opcode 핸들러 `py_opcode_BUILD_TUPLE`, `py_opcode_BUILD_LIST` 정의 및 `py_eval_frame`·예외 디스패치에 102/103 분기 추가만 하면 된다.

---

## 3. 구현 설계 (임시방편 없음)

### 3.1 py_opcode_BUILD_TUPLE(frame_id uuid, count integer)

- **동작**:
  1. count &lt; 0이면 에러 (CPython에서도 비정상).
  2. 스택에서 count개 pop: 첫 pop = 결과 튜플의 **마지막** 원소(ob_item[count]), 마지막 pop = **첫** 원소(ob_item[1]).  
     즉 `FOR i IN 1..count LOOP pop → ob_item[count - i + 1]` 또는 동치 로직.
  3. 새 `py_object` 행 생성(ob_type = tuple 타입 ID), 새 `py_tuple_object` 행 생성(ob_base = 해당 id, ob_item = 수집한 uuid[]).
  4. 새 객체 id를 스택에 push.
- **타입 ID**: 부트스트랩과 동일한 고정 UUID 사용. `tp_name` 조회/분기 금지. `ID_TUPLE_TYPE := '00000000-0000-4000-a000-000000000007'` 상수 사용.

### 3.2 py_opcode_BUILD_LIST(frame_id uuid, count integer)

- **동작**: BUILD_TUPLE과 동일. 단, `py_list_object`에 삽입, list 타입 ID `'00000000-0000-4000-a000-000000000005'` 사용.
- **타입 ID**: `ID_LIST_TYPE` 상수만 사용.

### 3.3 스택 underflow

- count개 pop 전에 스택이 부족하면 `py_stack_pop`에서 이미 "Stack underflow" 예외 발생. 별도 분기 없이 일관되게 처리.

### 3.4 eval_frame·예외 디스패치

- **232000** `py_eval_frame`: CASE에 `WHEN 102 THEN PERFORM py_opcode_BUILD_TUPLE(frame_id, arg);`, `WHEN 103 THEN PERFORM py_opcode_BUILD_LIST(frame_id, arg);` 추가.
- **41000** `ceval_exception_dispatch`: 동일 CASE에 102, 103 분기 추가(실행 경로 통일).
- **41100** `python_exception_setters`: 최종 `py_eval_frame` 정의를 갖고 있으므로 CASE에 102, 103 분기 **필수** 추가. 미추가 시 BUILD_TUPLE/BUILD_LIST 실행 시 "Unknown opcode" 발생.

---

## 4. 임시방편 금지 체크리스트

- [ ] tuple/list 타입 지정: **고정 UUID 상수**만 사용. `tp_name = 'tuple'` / `'list'` 조회 금지.
- [ ] 객체 생성: **기존** `py_object`·`py_tuple_object`·`py_list_object` INSERT만 사용. 스키마 변경 없음.
- [ ] opcode 크기: **py_get_opcode_size** 수정 없음 (102, 103 ≥ 90 → 이미 2바이트 반환).

---

## 5. 작업 ID·의존관계·실행 순서

### 5.1 작업 ID 정의

| ID | 작업 | 산출물 |
|----|------|--------|
| **A** | py_opcode_BUILD_TUPLE 정의 | 새 마이그레이션(예: 239500) 또는 기존 opcode 마이그레이션 |
| **B** | py_opcode_BUILD_LIST 정의 | 위와 동일 파일 |
| **C** | py_eval_frame에 102, 103 분기 추가 | 232000 수정 |
| **D** | ceval_exception_dispatch에 102, 103 분기 추가 | 41000 수정 |
| **E** | python_exception_setters에 102, 103 분기 추가 | 41100 수정 |
| **F** | BUILD_TUPLE/BUILD_LIST 통합 테스트 추가 | supabase/tests/, run_tests.sh |

### 5.2 의존관계

```
A ──┐
    ├──→ C   (C는 A, B 완료 후: eval_frame에서 두 opcode 호출)
B ──┘

A ──┐
    ├──→ D   (D는 A, B 완료 후: 예외 디스패치에서 102, 103 처리)
B ──┘

A ──┐
    ├──→ E   (E는 A, B 완료 후, 41100이 opcode별 분기 시)
B ──┘

C ──┐
D ──┼──→ F   (테스트는 eval_frame·예외 경로 반영 후)
E ──┘
```

- **A, B**: 서로 독립. 동시에 같은 마이그레이션 파일에 넣어도 됨.
- **C, D, E**: A, B에 의존 (해당 함수가 정의된 뒤에만 CASE에 넣을 수 있음).
- **F**: C, D, E 완료 후 실행 (세 파일 모두 102/103 분기 필요).

### 5.3 실행 순서 (가장 먼저 할 일부터)

| 순위 | 작업 | 선행 | 비고 |
|------|------|------|------|
| **1** | **A** py_opcode_BUILD_TUPLE 정의 | 없음 | 새 마이그레이션(예: 20260114239500_build_tuple_list.sql)에 함수 정의 |
| **2** | **B** py_opcode_BUILD_LIST 정의 | 없음 | 같은 마이그레이션에 함수 정의 |
| **3** | **C** py_eval_frame에 102, 103 추가 | A, B | 232000의 CASE에 WHEN 102, WHEN 103 추가 |
| **4** | **D** ceval_exception_dispatch에 102, 103 추가 | A, B | 41000의 CASE에 WHEN 102, WHEN 103 추가 |
| **5** | **E** python_exception_setters에 102, 103 추가 | A, B | 41100은 최종 py_eval_frame이므로 필수 |
| **6** | **F** 통합 테스트 | C, D(, E) | 바이트코드 (1,2) → tuple/list, len() 등 검증, run_tests.sh Phase 41 등록 |

---

## 6. 마이그레이션 배치

- **원칙**: 기존 마이그레이션을 코드처럼 관리. 스키마 변경 없으므로 **새 파일 1개**로 opcode만 추가하는 방식 권장.
- **제안**:
  - **새 파일** `20260114239500_build_tuple_list.sql`: `py_opcode_BUILD_TUPLE`, `py_opcode_BUILD_LIST` 정의.
  - **232000** `20260114232000_ceval_eval_frame.sql`: CASE에 `WHEN 102`, `WHEN 103` 추가.
  - **41000** `20260114241000_ceval_exception_dispatch.sql`: CASE에 `WHEN 102`, `WHEN 103` 추가.
  - **41100** `20260114241100_python_exception_setters.sql`: opcode별 분기가 있다면 102, 103 추가.

---

## 7. 요약

| 단계 | 내용 | 산출물 |
|------|------|--------|
| 1 | py_opcode_BUILD_TUPLE, py_opcode_BUILD_LIST 정의 | 239500 (새 파일) |
| 2 | py_eval_frame·예외 디스패치(·setters)에 102, 103 연결 | 232000, 41000, 41100 수정 |
| 3 | 테스트: 바이트코드 (1,2) → tuple/list, len 등 | supabase/tests/, run_tests.sh |

**CPython 고증**: BUILD_TUPLE(102)·BUILD_LIST(103)는 스택에서 count개 pop, TOS=마지막 원소, 새 tuple/list 생성 후 push.  
**임시구현 없음**: 타입은 고정 UUID 상수만 사용, `tp_name` 분기·스키마 변경 없음.

---

## 8. 가장 먼저 실행할 작업 요약

| 순서 | 작업 ID | 할 일 |
|------|---------|--------|
| 1 | A | 새 마이그레이션 파일에 `py_opcode_BUILD_TUPLE(frame_id, count)` 정의 |
| 2 | B | 같은 파일에 `py_opcode_BUILD_LIST(frame_id, count)` 정의 |
| 3 | C | `20260114232000_ceval_eval_frame.sql`의 CASE에 `WHEN 102`, `WHEN 103` 추가 |
| 4 | D | `20260114241000_ceval_exception_dispatch.sql`의 CASE에 `WHEN 102`, `WHEN 103` 추가 |
| 5 | E | `20260114241100_python_exception_setters.sql`의 CASE에 `WHEN 102`, `WHEN 103` 추가 |
| 6 | F | 통합 테스트 파일 추가(예: `41_build_tuple_list_integration.sql`) 및 `run_tests.sh` Phase 41 등록 |

의존 관계: **A, B → C, D, E** (A·B 완료 후 C·D·E 수정). **C, D, E → F** (eval_frame 세 파일 반영 후 테스트 추가).
