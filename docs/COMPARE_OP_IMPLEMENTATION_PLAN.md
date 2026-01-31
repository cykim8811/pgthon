# COMPARE_OP 구현 단계 계획 (CPython 고증)

CPython의 `PyObject_RichCompare` 및 COMPARE_OP(opcode 107) 동작에 맞게, **reflected op**까지 반영하여 구현한다. 임시 구현 없음.

---

## 1. CPython 동작 요약

- **PyObject_RichCompare(v, w, op)**  
  1. `v->ob_type->tp_richcompare(v, w, op)` 호출.  
  2. 결과가 `NotImplemented`이면 **reflected op** 시도:  
     - op ∈ {Py_LT, Py_LE, Py_GT, Py_GE} → `w->ob_type->tp_richcompare(w, v, reflected_op)`  
       - Py_LT(0) ↔ Py_GT(4), Py_LE(1) ↔ Py_GE(5)  
     - Py_EQ(2), Py_NE(3) → 인자만 바꿔서 `tp_richcompare(w, v, op)`  
  3. 여전히 `NotImplemented`면 비교 불가(상위에서 TypeError 등 처리).
- **COMPARE_OP (opcode 107)**  
  - 피연산자: 비교 종류 (0=LT, 1=LE, 2=EQ, 3=NE, 4=GT, 5=GE).  
  - 스택: `... | left | right` → pop right, pop left → `PyObject_RichCompare(left, right, arg)` → 결과가 `NotImplemented`면 `TypeError`, 아니면 True/False 푸시.

---

## 2. 현재 Elytra 상태

- `py_object_richcompare(self_id, other_id, op)`  
  - left(`self_id`)의 `tp_richcompare`만 호출. **NotImplemented 시 other 쪽(reflected op) 시도 없음.**
- `py_object_richcompare_eq`  
  - Py_EQ 전용이며, NotImplemented일 때 `py_object_richcompare(b_id, a_id, 2)` 호출로 역방향 시도 있음. (dict 키 동등성용으로만 사용)
- `py_unicode_richcompare`, `py_long_richcompare`  
  - 6가지 op 모두 구현됨(237000).  
- COMPARE_OP opcode 핸들러 및 eval_frame 분기 **미구현**.

---

## 3. 작업 식별 및 의존 관계

| ID | 작업 | 의존 작업 | 비고 |
|----|------|-----------|------|
| **R** | `py_object_richcompare`에 reflected op 로직 추가 | 없음 | 기존 함수 교체만. NotImplemented 시 other 쪽 tp_richcompare(reflected_op) 호출 |
| **S** | `py_opcode_COMPARE_OP(frame_id, compare_op)` 정의 | **R** | 스택 pop/push, richcompare 호출, NotImplemented → RAISE |
| **T** | `py_eval_frame`에 opcode 107 분기 추가 | **S** | WHEN 107 THEN py_opcode_COMPARE_OP(frame_id, arg) |

---

## 4. 단계별 실행 계획

### Phase 1 — py_object_richcompare (reflected op)

**마이그레이션:** `20260114240000_compare_op.sql`

- `py_object_richcompare(self_id, other_id, op)` 재정의:
  1. `self_id`의 타입으로 `tp_richcompare(self_id, other_id, op)` 호출.
  2. 결과가 `NotImplemented`(싱글톤 ID)가 아니면 그대로 반환.
  3. **Reflected op**:
     - op ∈ {0,1,4,5}: `reflected_op := (0→4, 1→5, 4→0, 5→1)`, `other_id`의 타입으로 `tp_richcompare(other_id, self_id, reflected_op)` 호출.
     - op ∈ {2,3}: `tp_richcompare(other_id, self_id, op)` 호출.
  4. 위 결과 반환(NotImplemented면 그대로 반환).

### Phase 2 — py_opcode_COMPARE_OP

**마이그레이션:** `20260114240000_compare_op.sql` (phase2 opcode도 동일 파일에 통합)

- `py_opcode_COMPARE_OP(frame_id uuid, compare_op integer) RETURNS void`:
  - 스택에서 `right_id := stack_pop`, `left_id := stack_pop`.
  - `res := py_object_richcompare(left_id, right_id, compare_op)`.
  - `res`가 NotImplemented 싱글톤이면 `RAISE EXCEPTION 'TypeError: ...'`.
  - 아니면 `py_stack_push(frame_id, res)`.

### Phase 3 — py_eval_frame 분기

**마이그레이션:** `20260114232000_ceval_eval_frame.sql`

- `py_eval_frame`의 CASE에 `WHEN 107 THEN PERFORM py_opcode_COMPARE_OP(frame_id, arg);` 는 이미 `ceval_eval_frame`에 포함됨.
- `py_get_opcode_size(107)`는 기본 2바이트(ceval_core).

---

## 5. 테스트

- **슬롯/API:** `py_object_richcompare`가 int/str에 대해 6가지 op + int vs str 등 타입 조합에서 NotImplemented 시 str 쪽으로 reflected 시도하는지 검증.
- **통합:** 바이트코드 `LOAD_CONST 1; LOAD_CONST 2; COMPARE_OP 0` (1 < 2 → True) 등으로 COMPARE_OP 107 실행 후 스택에 True/False가 남는지 검증. NotImplemented 케이스는 TypeError 발생 확인.

---

## 6. 고증 체크리스트

- [x] Py_LT/Py_LE/Py_EQ/Py_NE/Py_GT/Py_GE = 0..5 (object.h)
- [x] left의 tp_richcompare(left, right, op) 먼저 시도
- [x] NotImplemented 시 reflected op: LT↔GT, LE↔GE, EQ/NE는 인자만 스왑
- [x] COMPARE_OP 스택: pop right, pop left → push True/False 또는 TypeError
- [x] opcode 107 (Python 3.11 COMPARE_OP)
