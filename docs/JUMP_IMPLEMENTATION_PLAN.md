# Jump Opcode 구현 단계 계획 (CPython 고증)

CPython의 JUMP_FORWARD·POP_JUMP_FORWARD_IF_FALSE 및 PyObject_IsTrue 동작에 맞게, 임시방편 없이 구현한다.

---

## 1. CPython 동작 요약

### 1.1 PyObject_IsTrue (truth testing)

- **규칙**: `__bool__()` 있으면 그 결과; 없으면 `__len__()` 결과(0이면 False); 둘 다 없으면 True.
- **Elytra 1단계**: 슬롯(tp_bool/__len__) 없이, 지원 타입만 테이블·싱글톤으로 판별. 타입 이름 분기 금지.
  - 싱글톤: True → true, False/None/NotImplemented → false.
  - int: `long_value = 0` → false.
  - str: `str_value = ''` → false.
  - float: `float_value = 0` → false.
  - list/tuple: 길이 0 → false.
  - dict: 항목 0개 → false.
  - 그 외: true (객체 기본값).

### 1.2 JUMP_FORWARD (opcode 110, Python 3.11)

- **jrel**: 상대 점프. 피연산자는 "건너뛸 단어 수"(word = 2바이트).
- **동작**: 다음 명령 위치 = 현재 명령 끝 + `delta_bytes` (delta_bytes = arg * 2).
- **Elytra**: `next_i := i + 2 + arg * 2` (i = 현재 opcode 바이트 오프셋, 2 = 명령 크기).

### 1.3 POP_JUMP_FORWARD_IF_FALSE (opcode 114) / POP_JUMP_FORWARD_IF_TRUE (opcode 115, Python 3.11)

- **jrel**: 상대 점프. TOS를 pop한 뒤, PyObject_IsTrue(TOS)가 False이면 점프.
- **114 (IF_FALSE)**: `tos = pop(); if not PyObject_IsTrue(tos): i := i + 2 + arg*2`.
- **115 (IF_TRUE)**: `tos = pop(); if PyObject_IsTrue(tos): i := i + 2 + arg*2`.
- **Elytra**: 114는 pop → not istrue면 점프; 115는 pop → istrue면 점프 (240500).

---

## 2. 작업 식별 및 의존 관계

| ID | 작업 | 의존 작업 | 비고 |
|----|------|-----------|------|
| **A** | `py_object_istrue(obj_id uuid) RETURNS boolean` | 없음 | 싱글톤·테이블 기반, tp_name 분기 없음 |
| **B** | `py_opcode_JUMP_FORWARD` 처리 | 없음 | eval_frame 내부에서 `next_i := i + 2 + arg*2` |
| **C** | `py_opcode_POP_JUMP_FORWARD_IF_FALSE(frame_id, delta_words) RETURNS integer` | **A** | pop → not istrue면 반환할 next_i, 아니면 NULL |
| **D** | `py_eval_frame`에서 next_i 지원 및 110/114 분기 | **B, C** | CASE에 110/114 추가, 루프 끝에서 next_i 있으면 i := next_i |

---

## 3. 단계별 실행 계획

### Phase 1 — py_object_istrue

**마이그레이션:** `20260114240300_jump_phase1_py_object_istrue.sql`

- `py_object_istrue(obj_id uuid) RETURNS boolean`:
  - 싱글톤 ID: True → true, False/None/NotImplemented → false.
  - `py_long_object`: `long_value = 0` → false.
  - `py_unicode_object`: `str_value = ''` → false.
  - `py_float_object`: `float_value = 0` → false.
  - `py_list_object`: `ob_item` 길이 0 → false.
  - `py_tuple_object`: `ob_item` 길이 0 → false.
  - `py_dict_object`: `py_dict_len(dict_id) = 0` 또는 entry 없음 → false.
  - 그 외(객체 존재): true.
  - 타입 판별은 테이블 존재·싱글톤만 사용, tp_name 사용 금지.

### Phase 2 — opcode 핸들러 및 eval_frame

**마이그레이션:** `20260114240400_jump_phase2_opcode_and_eval_frame.sql`

- `py_opcode_POP_JUMP_FORWARD_IF_FALSE(frame_id uuid, delta_words integer) RETURNS integer`:
  - `tos := py_stack_pop(frame_id)`.
  - `py_object_istrue(tos)`가 true이면 NULL 반환(점프 안 함).
  - false이면 `next_i := current_byte_offset + 2 + delta_words * 2`를 **호출자(eval_frame)가 알 수 있도록** 반환.  
  → 호출 시점에 `i`를 넘겨야 하므로, 시그니처를 `(frame_id, current_i, delta_words) RETURNS integer`로 하고, 점프 시 `current_i + 2 + delta_words*2` 반환, 아니면 NULL.
- **py_eval_frame 수정**:
  - `next_i INTEGER DEFAULT NULL` 추가.
  - `WHEN 110 THEN next_i := i + 2 + arg * 2` (JUMP_FORWARD; arg = delta words).
  - `WHEN 114 THEN next_i := py_opcode_POP_JUMP_FORWARD_IF_FALSE(frame_id, i, arg)`.
  - CASE 끝난 뒤: `IF next_i IS NOT NULL THEN i := next_i; ELSE i := i + instruction_size; END IF`.

### Phase 3 — py_get_opcode_size

- opcode 110, 114는 2바이트(opcode 1 + operand 1). 기본 2이면 수정 불필요.

---

## 4. 테스트

- **py_object_istrue**: True/False/None/0/1/''/'x' 등에 대해 기대 boolean.
- **JUMP_FORWARD**: LOAD_CONST 1, JUMP_FORWARD 2, LOAD_CONST 0, RETURN_VALUE → 두 번째 상수 건너뛰고 1 반환 등.
- **POP_JUMP_FORWARD_IF_FALSE**: COMPARE_OP로 False 푸시 후 점프해 특정 상수만 반환하는 바이트코드.

---

## 5. 고증 체크리스트

- [x] PyObject_IsTrue: None/False/0/0.0/''/[]/()/{} → false; True/1/'x' 등 → true.
- [x] 타입 판별 시 tp_name 미사용(테이블·싱글톤만).
- [x] JUMP_FORWARD 110: next_i = i + 2 + arg*2 (words).
- [x] POP_JUMP_FORWARD_IF_FALSE 114: pop, not istrue → next_i = i + 2 + arg*2.
