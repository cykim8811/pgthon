# BINARY_MULTIPLY 구현 단계 계획 (BINARY_ADD와 동일 방식)

CPython PyNumber_Multiply: (1) nb_multiply (BINARY_OP1) (2) 실패 시 left의 sq_repeat(seq, n) 또는 right의 sq_repeat(seq, n).  
n은 다른 피연산자를 PyNumber_AsSsize_t로 변환한 값. str*int, int*str 지원.

---

## 1. 작업 식별 및 의존 관계

| ID | 작업 | 의존 작업 | 비고 |
|----|------|-----------|------|
| **A** | `py_number_methods`에 `nb_multiply regproc` 컬럼 추가 | 없음 | |
| **B** | `py_sequence_methods`에 `sq_repeat regproc` 컬럼 추가 | 없음 | ssizeargfunc → (uuid, integer) |
| **C** | `py_long_nb_multiply(left_id, right_id)` — int*int | 없음 | |
| **E** | `py_unicode_sq_repeat(seq_id uuid, n integer)` — str*n | 없음 | n<0이면 빈 문자열 등 |
| **F** | `py_object_multiply_via_nb(left_id, right_id)` | **A** | left nb_multiply, NotImplemented 시 right nb_multiply(right, left) |
| **G** | `py_sequence_repeat(seq_id uuid, n integer)` | **B** | left의 tp_as_sequence->sq_repeat(seq_id, n) |
| **I** | 슬롯 등록: int의 nb_multiply, str의 sq_repeat | **A, B, C, E** | |
| **H** | `py_object_multiply(left_id, right_id)` | **F, G** | via_nb → left sq_repeat(left, right_as_int) → right sq_repeat(right, left_as_int) → TypeError |
| **J** | `py_opcode_BINARY_MULTIPLY(frame_id)` | **H** | stack pop/push + py_object_multiply |
| **K** | `py_eval_frame`에 opcode 20 분기 추가 | **J** | 20 = BINARY_MULTIPLY |

---

## 2. CPython 동작 (Objects/abstract.c)

- PyNumber_Multiply: BINARY_OP1(nb_multiply) → NotImplemented 시 mv->sq_repeat(v, w) 시도 (v가 seq, w를 count로 변환), 없으면 mw->sq_repeat(w, v). sequence_repeat는 n = PyNumber_AsSsize_t(다른 피연산자).

---

## 3. 마이그레이션 배치

| 마이그레이션 | 포함 작업 | 설명 |
|--------------|-----------|------|
| `20260114239000_binary_multiply_phase1_*.sql` | A, B, C, E | nb_multiply, sq_repeat 컬럼, py_long_nb_multiply, py_unicode_sq_repeat |
| `20260114239100_binary_multiply_phase2_*.sql` | F, G, I | py_object_multiply_via_nb, py_sequence_repeat, 슬롯 등록 |
| `20260114239200_binary_multiply_phase3_*.sql` | H | py_object_multiply |
| `20260114239300_binary_multiply_phase4_*.sql` | J | py_opcode_BINARY_MULTIPLY |
| `20260114239400_binary_multiply_phase5_*.sql` | K | py_eval_frame opcode 20 분기 |
