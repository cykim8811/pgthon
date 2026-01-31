# POP_TOP 구현 단계 계획 (CPython 고증)

CPython의 POP_TOP(opcode 1) 동작에 맞게, 임시방편 없이 구현한다.

---

## 1. CPython 동작 요약

### 1.1 POP_TOP (opcode 1)

- **위치**: Python 3.11 `opcode.py`: `def_op('POP_TOP', 1)`. HAVE_ARGUMENT(90) 미만이므로 **의미상 피연산자 없음**. Python 3.6+는 **모든 명령이 2바이트**(opcode+arg)로 저장됨.
- **동작**: 스택에서 값 하나를 pop하고 **버린다**. 반환값/부작용만 쓰고 결과를 쓰지 않을 때 사용(예: `f()` 후 반환값 무시).
- **Elytra**: `py_stack_pop(frame_id)` 호출 후 반환값 미사용. 기존 스택 API만 사용, 타입 분기·스텁 없음.

### 1.2 py_get_opcode_size

- Python 3.6+ 고증: **모든 명령이 2바이트**(opcode 1바이트 + arg 1바이트)로 저장됨.  
  따라서 `py_get_opcode_size(1) = 2` (마이그레이션 240700: uniform 2-byte).

---

## 2. 작업 식별 및 의존 관계

| ID | 작업 | 의존 작업 | 비고 |
|----|------|-----------|------|
| **A** | `py_opcode_POP_TOP(frame_id) RETURNS void` | 없음 | `py_stack_pop(frame_id)` 호출만, 반환값 버림 |
| **B** | `py_get_opcode_size(1) = 2` | 없음 | 3.6+ uniform 2바이트 (240700) |
| **C** | `py_eval_frame`에 opcode 1 분기 | **A, B** | WHEN 1 THEN PERFORM py_opcode_POP_TOP(frame_id) |

---

## 3. 단계별 실행 계획

### Phase 1 — opcode 핸들러 및 eval_frame·opcode_size

**마이그레이션:** `20260114240600_pop_top.sql`

1. **py_opcode_POP_TOP(frame_id uuid) RETURNS void**
   - frame 존재 검사 후 `PERFORM py_stack_pop(frame_id);` (반환값 무시).
   - 스택 underflow는 `py_stack_pop` 내부에서 예외로 처리.

2. **py_get_opcode_size**
   - 240700에서 모든 opcode 2바이트로 통일 (3.6+ 고증).

3. **py_eval_frame**
   - `WHEN 1 THEN PERFORM py_opcode_POP_TOP(frame_id);` 추가.
   - arg는 사용하지 않음; 다음 PC는 `i + 2`.

---

## 4. 테스트

- **통합**: 바이트코드 `LOAD_CONST 0, POP_TOP, LOAD_CONST 1, RETURN_VALUE`  
  → const0 푸시 → POP_TOP으로 버림 → const1 푸시 → RETURN_VALUE → **const1 반환**.
- co_consts = [const0, const1], bytecode: `\x64000164015300` (64,00 LOAD_CONST 0; 01 POP_TOP; 64,01 LOAD_CONST 1; 53,00 RETURN_VALUE).

---

## 5. 고증 체크리스트

- [x] POP_TOP: 스택에서 값 하나 pop 후 버림 (CPython과 동일).
- [x] opcode 1은 2바이트 명령 (3.6+ uniform; HAVE_ARGUMENT는 의미상만).
- [x] 타입 분기·스텁 없음. 기존 `py_stack_pop`만 사용.
