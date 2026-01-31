# BINARY_ADD 구현 단계 계획 (의존성 기반)

CPython 고증에 맞게 nb_add + sq_concat 폴백으로 BINARY_ADD를 넣는다.  
각 작업의 의존 관계를 정리하고, **다른 작업에 의존하지 않는 것부터** 순서대로 진행한다.

---

## 1. 작업 식별 및 의존 관계

| ID | 작업 | 의존 작업 | 비고 |
|----|------|-----------|------|
| **A** | `py_number_methods`에 `nb_add regproc` 컬럼 추가 (ALTER) | 없음 | 235500에서 생성된 테이블에 컬럼만 추가 |
| **B** | `py_sequence_methods`에 `sq_concat regproc` 컬럼 추가 (ALTER) | 없음 | 226000에서 생성된 테이블에 컬럼만 추가 |
| **C** | `py_long_nb_add(left_id, right_id)` 함수 정의 | 없음 | `py_long_object` 등 기존 스키마만 사용 |
| **D** | `py_unicode_nb_add(left_id, right_id)` 함수 정의 | 없음 | `py_unicode_object` 등 기존 스키마만 사용 |
| **E** | `py_unicode_sq_concat(left_id, right_id)` 함수 정의 | 없음 | `py_unicode_object` 등 기존 스키마만 사용 |
| **F** | `py_object_add_via_nb(left_id, right_id)` 정의 | **A** | left/right의 `tp_as_number->nb_add` 조회·호출. 컬럼이 있어야 함 |
| **G** | `py_sequence_concat(left_id, right_id)` 정의 | **B** | left의 `tp_as_sequence->sq_concat` 조회·호출. 컬럼이 있어야 함 |
| **I** | 슬롯 등록 (int/str의 nb_add, str의 sq_concat) | **A, B, C, D, E** | 새 컬럼 + 타입별 함수가 모두 있어야 UPDATE 가능 |
| **H** | `py_object_add(left_id, right_id)` 정의 (PyNumber_Add 대응) | **F, G** | 내부에서 F·G만 호출 |
| **J** | `py_opcode_BINARY_ADD(frame_id)` 정의 | **H** | stack pop/push + `py_object_add` 호출 |
| **K** | `py_eval_frame`에 opcode 23 분기 추가 | **J** | 23일 때 `py_opcode_BINARY_ADD` 호출 |

---

## 2. 의존성 DAG 요약

```
[선행 없음]     A, B, C, D, E
                    │
     A ─────────────┼─────────────┐
     B ─────────────┼─────────────┤
     C ─────────────┤             │
     D ─────────────┤             │
     E ─────────────┘             │
                    │             │
                    ▼             ▼
              F, G, I        (F←A, G←B, I←A,B,C,D,E)
                    │
              F ────┴──── G
                    │
                    ▼
                    H
                    │
                    ▼
                    J
                    │
                    ▼
                    K
```

---

## 3. 단계별 실행 계획 (의존성 순)

### Phase 1 — 선행 없음 (가장 먼저 진행)

**의존성:** 없음. 다른 BINARY_ADD 관련 작업에 의존하지 않는다.

| 순서 | 작업 ID | 내용 |
|------|---------|------|
| 1 | A | `ALTER TABLE py_number_methods ADD COLUMN nb_add regproc;` |
| 2 | B | `ALTER TABLE py_sequence_methods ADD COLUMN sq_concat regproc;` |
| 3 | C | `CREATE OR REPLACE FUNCTION py_long_nb_add(uuid, uuid) RETURNS uuid ...` |
| 4 | D | `CREATE OR REPLACE FUNCTION py_unicode_nb_add(uuid, uuid) RETURNS uuid ...` |
| 5 | E | `CREATE OR REPLACE FUNCTION py_unicode_sq_concat(uuid, uuid) RETURNS uuid ...` |

**배치:** 하나의 마이그레이션 파일에서 모두 수행해도 되고, 스키마(A,B)와 타입별 함수(C,D,E)를 나눠도 된다. 의존 관계상 같은 Phase이므로 한 번에 넣는 편이 단순하다.

---

### Phase 2 — Phase 1 완료 후 가능

**의존성:** F는 A에만, G는 B에만, I는 A,B,C,D,E 전부에 의존한다. Phase 1이 끝나면 F·G·I를 **서로 순서 없이** 진행 가능하다.

| 순서 | 작업 ID | 내용 |
|------|---------|------|
| 6 | F | `CREATE OR REPLACE FUNCTION py_object_add_via_nb(uuid, uuid) RETURNS uuid ...` |
| 7 | G | `CREATE OR REPLACE FUNCTION py_sequence_concat(uuid, uuid) RETURNS uuid ...` |
| 8 | I | int/str의 `py_number_methods.nb_add` 등록, str의 `py_sequence_methods.sq_concat` 등록 (UPDATE) |

**배치:** Phase 1과 같은 마이그레이션에 이어서 넣어도 되고, “Phase 1 = 스키마+타입별 함수”, “Phase 2 = 디스패치·등록”처럼 별도 마이그레이션으로 나눠도 된다.

---

### Phase 3 — Phase 2 완료 후 가능

**의존성:** H는 F와 G에만 의존한다.

| 순서 | 작업 ID | 내용 |
|------|---------|------|
| 9 | H | `CREATE OR REPLACE FUNCTION py_object_add(uuid, uuid) RETURNS uuid ...` (nb 경로 → sq_concat 폴백 → TypeError) |

**배치:** Phase 2와 같은 파일에 이어서 넣거나, “디스패치만” 별도 마이그레이션으로 둘 수 있다.

---

### Phase 4 — Phase 3 완료 후 가능

**의존성:** J는 H에만 의존한다.

| 순서 | 작업 ID | 내용 |
|------|---------|------|
| 10 | J | `CREATE OR REPLACE FUNCTION py_opcode_BINARY_ADD(uuid) RETURNS void ...` |

**배치:** VM·opcode 계열과 함께 두기 좋다. Phase 3과 같은 마이그레이션에 포함하거나, “opcode + eval 연결”만 다음 마이그레이션으로 분리할 수 있다.

---

### Phase 5 — Phase 4 완료 후 가능

**의존성:** K는 J에만 의존한다.

| 순서 | 작업 ID | 내용 |
|------|---------|------|
| 11 | K | `py_eval_frame`을 CREATE OR REPLACE로 수정해, opcode 23일 때 `PERFORM public.py_opcode_BINARY_ADD(frame_id);` 호출 추가 |

**배치:** 기존 규칙대로 “eval_frame 수정은 별도 마이그레이션에서만” 하면, 이 단계만 들어가는 마이그레이션을 두는 것이 좋다.

---

## 4. 마이그레이션 파일 배치 제안

현재 마이그레이션 최신 타임스탬프는 237000대이므로, 아래처럼 새 타임스탬프를 쓰면 된다.

| 마이그레이션 | 포함 Phase | 포함 작업 | 설명 |
|--------------|------------|-----------|------|
| `20260114238000_binary_add.sql` | Phase 1~4 통합 | A–J | 스키마 확장, 타입별 함수, 디스패치, 슬롯 등록, BINARY_ADD opcode |
| `20260114232000_ceval_eval_frame.sql` | Phase 5 | K | `py_eval_frame`에 opcode 23 분기 (해당 파일에 반영됨) |

또는 의존성 단위로 더 쪼개려면:

| 마이그레이션 | 포함 Phase | 포함 작업 |
|--------------|------------|-----------|
| `20260114238000_binary_add.sql` | Phase 1~5 통합 | A–K | 스키마·타입별 함수·디스패치·opcode·eval_frame 분기 한 파일에 반영 |

---

## 5. “가장 먼저 추가할 수 있는 것” 정리

- **제일 먼저 할 수 있는 것(Phase 1):**  
  **A**(nb_add 컬럼), **B**(sq_concat 컬럼), **C**(py_long_nb_add), **D**(py_unicode_nb_add), **E**(py_unicode_sq_concat).  
  이 다섯 개는 서로 의존하지 않고, 기존 마이그레이션(226000, 235500 등) 결과에만 의존하므로, **어떤 BINARY_ADD 관련 작업보다 먼저** 들어가도 된다.

- 그 다음으로 **F, G, I**를 Phase 1 다음에 넣고, 이후 **H → J → K** 순서로 진행하면 의존성을 만족한다.
