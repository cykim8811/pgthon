# 검증: PUSH_NULL(2) · RESUME(151) 수정

이번 수정의 목적, 동작 여부, CPython 고증, 임시방편 여부, 마이그레이션 관리 방식을 검증한 결과이다.

---

## 1. 수정 목적

| 항목 | 목적 |
|------|------|
| **PUSH_NULL(2)** | CPython 3.11 호출 규약 완성. `obj.method(...)` 등 bound method 호출 시 스택에 “호출용 NULL”을 넣고, CALL 시 callable pop 직후 TOS가 NULL이면 1개 더 pop하여 정리. |
| **RESUME(151)** | 3.11 컴파일러가 프레임 맨 앞(및 yield/await 후)에 넣는 opcode. 1바이트 인자(where)만 읽고 no-op. 3.11 생성 바이트코드 실행 시 Unknown opcode 방지. |

참고: `docs/OPCODE_3_11_ROADMAP.md` 권장 순서 2·3번, `docs/CALL_PROTOCOL_3_11_DESIGN.md` Phase 3.

---

## 2. 잘 되었는지 (동작 검증)

- **DB 리셋**: `pnpm dlx supabase db reset` 성공. 모든 마이그레이션 적용됨.
- **테스트**: `./run_tests.sh` 실행 시 **48개 테스트 스위트 전부 통과**.
- **PUSH_NULL**: opcode 2 디스패치 → NULL 싱글턴 push. CALL 시 callable pop 후 TOS가 NULL이면 1개 pop 후 `py_object_call` 호출.
- **RESUME**: opcode 151 디스패치 → `py_opcode_RESUME(frame_id, arg)` no-op. 바이트코드 2바이트 진행.

---

## 3. CPython 고증

### 3.1 PUSH_NULL(2)

| CPython 3.11 | Pgthon 구현 | 일치 |
|--------------|-------------|------|
| opcode 2, 인자 없음 | `WHEN 2 THEN PERFORM py_opcode_PUSH_NULL(frame_id)` (arg는 2바이트 진행용으로만 사용) | ✓ |
| 스택에 “호출용 NULL” push | `py_stack_push(frame_id, ID_NULL_OBJ)` (전용 싱글턴) | ✓ |
| Py_None와 구분되는 전용 값 | 부트스트랩에 `null` 타입·`py_null_object` 싱글턴 추가, `Py_None`(ID_NONE_OBJ)와 별도 UUID | ✓ |

설계 문서 권장: “부트스트랩에 Py_NULL 타입·싱글턴 하나 추가해 Py_None와 구분” → **옵션 (1) 채택**.

### 3.2 CALL 시 PUSH_NULL 정리

| 설계 문서 Pop 순서 (CALL_PROTOCOL_3_11_DESIGN.md §2) | 구현 순서 (opcode_call_function.sql) | 일치 |
|------------------------------------------------------|----------------------------------------|------|
| 1. 키워드 값 k개 pop | `kw_names` 있으면 k개 `py_stack_pop` | ✓ |
| 2. 위치 인자 n개 pop | `FOR i IN 1..n` → `array_prepend(py_stack_pop, args)` | ✓ |
| 3. callable 1개 pop | `func_obj_id := py_stack_pop(frame_id)` | ✓ |
| 4. TOS가 NULL이면 1개 pop | `current_stack[stack_len] = ID_NULL_OBJ`이면 `f_valuestack`에서 1개 제거 | ✓ |

스택 레이아웃 “[ ..., NULL, callable, pos_1, ..., pos_n, kw_1, ... ]” 및 pop 순서와 일치.

### 3.3 RESUME(151)

| CPython 3.11 / 설계 문서 | Pgthon 구현 | 일치 |
|--------------------------|-------------|------|
| opcode 151, 함수/제너레이터 진입 no-op | `WHEN 151 THEN PERFORM py_opcode_RESUME(frame_id, arg)` | ✓ |
| 1바이트 인자(where): 0=시작, 1=yield 후, 2=yield from 후, 3=await 후 | `where_arg` 인자로 받고, 주석에 의미 명시. Pgthon에서는 미사용(no-op). | ✓ |
| 디스패치만 하고 동작 없음 | 프레임 존재 검사 후 종료. 스택/프레임 변경 없음. | ✓ |

`docs/EXCEPTION_HANDLING_DESIGN.md` 및 3.11 opcode 번호·시맨틱과 부합.

---

## 4. 임시방편 구현 여부

| 항목 | 검사 | 결과 |
|------|------|------|
| 테스트만 통과시키기 위한 특례 | 없음. PUSH_NULL/CALL/RESUME 모두 설계 문서·로드맵 시맨틱 그대로 구현. | ✓ |
| 하드코딩 우회 | 없음. NULL은 부트스트랩에 등록된 싱글턴 UUID 하나로 통일. CALL은 “TOS == ID_NULL_OBJ”일 때만 1개 pop. | ✓ |
| 스키마/타입 우회 | 없음. `py_null_object` 테이블·null 타입·tp_dict/tp_bases 등 부트스트랩에서 정식 등록. | ✓ |
| opcode 번호/인자 무시 | 없음. 2는 인자 없음(2바이트만 소비), 151은 arg 읽어서 2바이트 진행. | ✓ |

**결론: 임시방편 구현 없음.**

---

## 5. 마이그레이션 관리 방식 (기존 수정 vs 새 파일)

규칙 요약:

- **기존 스키마 변경**: 새 migration 추가 금지 → **기존 migration 파일 수정**.
- **새 opcode 핸들러**: **opcode당 migration 파일 하나** 추가 (예: `..._opcode_push_null.sql`, `..._opcode_resume.sql`).

### 5.1 기존 migration 수정 (스키마·부트스트랩·기존 핸들러)

| 파일 | 변경 내용 | 방식 |
|------|-----------|------|
| `20260114220000_python_object_schema.sql` | `py_null_object` 테이블, RLS, policy 추가 | **기존 파일 수정** ✓ |
| `20260114223000_python_bootstrap.sql` | ID_NULL_TYPE, ID_NULL_OBJ, ID_DICT_NULL_TYPE, Phase 1~5에 null 타입·싱글턴·dict·tp_bases/tp_dict·`py_null_object` INSERT | **기존 파일 수정** ✓ |
| `20260114240302_opcode_call_function.sql` | CALL 내부: callable pop 후 TOS가 NULL이면 1개 pop (ID_NULL_OBJ 상수, current_stack/stack_len 사용) | **기존 파일 수정** ✓ |
| `20260114241100_ceval_eval_frame.sql` | `WHEN 2 THEN ...`, `WHEN 151 THEN ...` 추가 | **기존 파일 수정** ✓ |

**스키마/부트스트랩/기존 opcode 관련 변경은 모두 기존 migration 수정으로 처리됨.**

### 5.2 새 migration 추가 (opcode당 1파일)

| 파일 | 내용 | 규칙 준수 |
|------|------|-----------|
| `20260114240319_opcode_push_null.sql` | `py_opcode_PUSH_NULL(frame_id)` 정의 | 새 opcode 1개 → 파일 1개 ✓ |
| `20260114240320_opcode_resume.sql` | `py_opcode_RESUME(frame_id, where_arg)` 정의 | 새 opcode 1개 → 파일 1개 ✓ |

**새 opcode는 “한 opcode당 하나의 migration 파일” 규칙을 따름.**

### 5.3 정리

- **기존 스키마 변경 시**: 새 migration을 만들지 않고, `python_object_schema.sql`·`python_bootstrap.sql` 등 **기존 migration 파일을 수정**하여 코드처럼 관리함.
- **새 opcode 핸들러**: `opcode_push_null`, `opcode_resume` 각각 **별도 migration 파일**로 추가.
- **eval_frame 디스패치·CALL 로직**: 기존 `ceval_eval_frame.sql`, `opcode_call_function.sql` **수정**으로 반영.

---

## 6. 요약

| 검증 항목 | 결과 |
|-----------|------|
| 수정 목적 | PUSH_NULL(2) 호출 규약 완성, RESUME(151) 3.11 맨 앞 no-op 대응. |
| 동작 | DB 리셋·전체 48개 테스트 통과. |
| CPython 고증 | opcode 번호·인자·스택 순서·NULL 표현·RESUME no-op 모두 설계 문서·로드맵과 일치. |
| 임시방편 | 없음. |
| 마이그레이션 관리 | 스키마/부트스트랩/기존 핸들러는 기존 migration 수정; 새 opcode만 opcode당 새 migration 1개 추가. |

이 문서는 2026-02-08 기준 PUSH_NULL(2)·RESUME(151) 수정에 대한 검증 기록이다.
