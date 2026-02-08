# CPython 3.11 호출 프로토콜 설계 (PRECALL / CALL / KW_NAMES / PUSH_NULL)

Elytra의 호출 경로를 CPython 3.11 바이트코드·내부 규약에 맞게 **다시 짜는 수준의 리팩터링**을 위한 설계와 단계별 계획이다.

**참고:** Python 3.11에서 `CALL_FUNCTION`(141)·`CALL_FUNCTION_KW`(142)는 제거되고, `PRECALL`(166) + `CALL`(171), 그리고 선택적으로 `KW_NAMES`(172)·`PUSH_NULL`(2) 조합으로 호출이 이뤄진다.

---

## 1. CPython 3.11 호출 관련 opcode (opcode.h / opcode.py)

| opcode | 이름 | 인자 | 비고 |
|--------|------|------|------|
| 2 | PUSH_NULL | 없음 | 스택에 "호출용 NULL" 푸시. 메서드 해석·bound method 호출 시 사용. |
| 166 | PRECALL | n | 다음 CALL을 위해 "위치 인자 n개" 준비. 스택을 바꾸지 않음(또는 최소한의 준비만). |
| 171 | CALL | n | callable + 인자들 pop 후 실제 호출. n = 위치 인자 개수(또는 위치+키워드 합계 — 구현 확인 필요). |
| 172 | KW_NAMES | const_i | **hasconst.** `co_consts[const_i]`가 다음 CALL에서 쓸 키워드 이름 tuple. 스택에 푸시하지 않음. |

- **PRECALL**: 3.11에서는 호출 직전 플래그·캐시 준비 등. Elytra에서는 **no-op**으로 두거나, "다음 CALL의 위치 인자 개수"만 기록해 두는 정도로 활용 가능.
- **CALL**: 실제 pop·호출·push 결과. CPython에서는 `_PyEval_EvalFrameDefault` 내부에서 스택에서 callable, args, (선택) kwnames를 꺼내 `_PyObject_FastCallDictTstate` 또는 vectorcall로 넘긴다.
- **KW_NAMES**: 다음에 나오는 **한 번의** CALL에만 적용. `co_consts[arg]`가 `(str, str, ...)` 형태의 키워드 이름 tuple. 키워드 값은 스택에 "위치 인자 바로 위"에 쌓인다.
- **PUSH_NULL**: 메서드 호출 시 `obj.method(...)`에서 receiver 자리를 비우기 위해 푸시. CALL 시 pop 순서에 포함된다.

---

## 2. 스택 레이아웃 (3.11 규약)

호출 직전 스택 (아래 = 스택 바닥, 위 = TOS):

- **PUSH_NULL이 있는 경우** (예: bound method):  
  `[ ..., NULL, callable, pos_1, ..., pos_n, kw_1, ..., kw_k ]`  
  - NULL: PUSH_NULL로 넣은 값. CALL 시 callable과 함께 제거.
- **PUSH_NULL이 없는 경우** (예: `len(x)`):  
  `[ ..., callable, pos_1, ..., pos_n, kw_1, ..., kw_k ]`

**CALL oparg** 해석 (CPython 소스와의 정합성 유지):

- **옵션 A**: oparg = **위치 인자 개수**만. 키워드 개수는 직전 `KW_NAMES`의 tuple 길이.
- **옵션 B**: oparg = **위치 + 키워드 합계**. 키워드 개수는 KW_NAMES tuple 길이로 알 수 있으므로 위치 = oparg - n_kw.

Elytra는 **옵션 A**로 정한다: `CALL n` → 위치 n개, 키워드 개수는 `pending_kw_names`가 있으면 `len(co_consts[kw_names_i])`.  
(구현 전에 CPython `ceval.c`의 `case CALL:`에서 oparg 사용 방식을 한 번 더 확인할 것.)

**Pop 순서 (CALL 실행 시):**

1. 키워드 값 k개 pop (KW_NAMES가 있었을 때만, k = 키워드 이름 tuple 길이)
2. 위치 인자 n개 pop (n = CALL oparg)
3. callable 1개 pop
4. TOS가 "NULL"이면 1개 pop (PUSH_NULL 정리)

그 다음 `py_object_call(callable_id, args_tuple_id, kwargs_dict_id)` 호출.  
- args: 위치 n개로 만든 tuple.  
- kwargs: KW_NAMES가 있었으면 키워드 이름 tuple + 방금 pop한 k개 값으로 dict 생성; 없으면 NULL.

---

## 3. Elytra에서 필요한 구조 변경

### 3.1 유지하는 것

- **tp_call 규약**: `(obj_id UUID, args UUID[], kwargs_id UUID) RETURNS UUID`. 기존과 동일.
- **py_object_call**, **py_call_cfunction**: 시그니처·의미 변경 없음. 호출 직전에 "args tuple·kwargs dict를 만드는 쪽"만 바뀜.
- **py_frame_object**: 기존 컬럼만으로 구현 가능. "다음 CALL에 쓰일 KW_NAMES"는 **프레임에 필드 하나 추가**하거나, **eval 루프 지역 변수**로 전달.

### 3.2 추가·변경하는 것

| 항목 | 내용 |
|------|------|
| **Frame 상태** | "다음 CALL에서 쓸 키워드 이름" = `co_consts` 인덱스. `py_frame_object`에 `f_pending_kw_names_const_i INTEGER` (NULL 가능) 추가하거나, `py_eval_frame` 인라인 변수로만 관리. |
| **NULL 표현** | PUSH_NULL에 대응하는 스택 값. 옵션: (1) 부트스트랩에 `Py_None`와 구분되는 전용 싱글턴 `Py_NULL`, (2) 특수 UUID(예: all-zero)를 "스택 전용 NULL"로 예약. CPython은 포인터 NULL이므로 Elytra는 (1) 또는 (2) 중 하나로 고정. |
| **opcode 핸들러** | `PUSH_NULL`(2), `PRECALL`(166), `KW_NAMES`(172), `CALL`(171) 추가. 기존 `CALL_FUNCTION`(141)·`CALL_FUNCTION_KW`(142) 제거. |
| **py_eval_frame** | CASE에 2, 166, 172, 171 추가. 141, 142 제거. |

### 3.3 KW_NAMES 상태 저장 위치

- **방안 A**: `py_frame_object.f_pending_kw_names_const_i INTEGER DEFAULT NULL`.  
  - KW_NAMES 실행 시 `UPDATE py_frame_object SET f_pending_kw_names_const_i = arg WHERE ob_base = frame_id`.  
  - CALL 실행 후 `UPDATE ... SET f_pending_kw_names_const_i = NULL`.
- **방안 B**: `py_eval_frame`의 DECLARE 블록에 `pending_kw_names_const_i INTEGER := NULL`만 두고, KW_NAMES에서 대입, CALL에서 사용 후 NULL로 초기화.  
  - 프레임 스키마 변경 없음. 3.11에서 KW_NAMES는 "다음 CALL 하나"에만 쓰이므로, 같은 프레임 내에서만 유효하면 됨.

**권장:** 우선 **방안 B**(eval 루프 지역 변수). 나중에 디버깅·추적을 위해 프레임에 올려도 됨.

---

## 4. CPython 쪽과의 대응 요약

| CPython 3.11 | Elytra |
|--------------|--------|
| `PUSH_NULL` | 스택에 NULL 대응값 push (전용 싱글턴 또는 예약 UUID). |
| `PRECALL n` | no-op 또는 "다음 CALL 위치 인자 수 = n" 기록(선택). |
| `KW_NAMES const_i` | `pending_kw_names_const_i := const_i`. |
| `CALL n` | 키워드 k = (pending 있으면 co_consts[i] tuple 길이), pop k개 kw값 → kwargs dict, pop n개 위치 → args tuple, pop callable, 필요 시 NULL 1개 pop → `py_object_call(callable, args, kwargs)` → 결과 push. |
| `PyObject_Call(callable, args, kwargs)` | `py_object_call(obj_id, args, kwargs_id)`. |
| tp_call 3인자 | 그대로 유지. |

---

## 5. 단계별 구현 계획 (리팩터링 순서)

### Phase 0: 사전 작업 (문서·상수)

- [ ] 이 설계 문서를 프로젝트에 반영.
- [ ] `docs/` 또는 마이그레이션 주석에 "3.11 CALL opcode 번호" 표 정리: 2, 166, 171, 172.
- [ ] PUSH_NULL용 "스택 NULL" 표현 방식 결정: 전용 싱글턴 vs 예약 UUID. (권장: 부트스트랩에 `Py_NULL` 타입·싱글턴 하나 추가해 `Py_None`와 구분.)

### Phase 1: PRECALL(166) · CALL(171) — 위치 인자만 (KW_NAMES 미사용)

**목표:** `len(x)` 같은 "위치 인자만 있는 호출"을 3.11 스타일로 처리. PUSH_NULL은 아직 처리하지 않음(스택에 NULL이 없다고 가정).

1. **마이그레이션**
   - `py_opcode_PRECALL(frame_id, n)`  
     - 현재는 no-op. (나중에 프로파일/디버깅용으로 "다음 CALL 위치 인자 수" 저장 가능.)
   - `py_opcode_CALL(frame_id, n)`  
     - 스택에서: 위치 인자 n개 pop → args 배열, callable 1개 pop.  
     - `pending_kw_names_const_i`는 사용하지 않음(kwargs = NULL).  
     - `py_object_call(callable_id, args, NULL)` 호출 후 결과 push.
   - `py_eval_frame`:  
     - `WHEN 166 THEN PERFORM py_opcode_PRECALL(frame_id, arg);`  
     - `WHEN 171 THEN PERFORM py_opcode_CALL(frame_id, arg);`  
     - 기존 `WHEN 141`, `WHEN 142` 제거.

2. **테스트**
   - 기존 "CALL_FUNCTION으로 len/abs 호출" 테스트를 **바이트코드만** 3.11 형식으로 변경:  
     `LOAD_GLOBAL` 또는 `LOAD_NAME` + `LOAD_FAST`/`LOAD_CONST` + `PRECALL 1` + `CALL 1` + `RETURN_VALUE`.  
   - Elytra가 아직 LOAD_GLOBAL/LOAD_FAST를 구현하지 않았다면, **LOAD_NAME + LOAD_CONST + PRECALL 1 + CALL 1** 조합으로 동일 시나리오 검증.

3. **기존 141/142 제거**
   - `py_opcode_CALL_FUNCTION`, `py_opcode_CALL_FUNCTION_KW` 호출부를 eval에서 제거.
   - 두 함수는 "레거시 바이트코드 호환"이 필요할 때까지 유지하거나, 한 번에 삭제.

### Phase 2: KW_NAMES(172) + CALL(171) 키워드 인자

**목표:** `f(a, b, x=1, y=2)` 형태. CALL 시 `pending_kw_names_const_i`와 `co_consts`를 사용해 kwargs 구성.

1. **상태**
   - `py_eval_frame` DECLARE에 `pending_kw_names_const_i INTEGER := NULL` 추가.
   - 매 iteration 시작 시 유지, KW_NAMES에서만 `pending_kw_names_const_i := arg` 설정.

2. **KW_NAMES 핸들러**
   - `py_opcode_KW_NAMES(frame_id, const_i)`  
     - 호출부에서 `pending_kw_names_const_i := const_i`만 설정. (또는 프레임 컬럼이 있으면 UPDATE.)

3. **CALL 확장**
   - `pending_kw_names_const_i IS NOT NULL`이면:  
     - `co_consts[pending_kw_names_const_i]`에서 tuple 객체를 가져와, 그 길이만큼 스택에서 키워드 값 pop.  
     - tuple의 각 원소(이름 str id)와 pop한 값으로 `py_dict_set_item` 해서 kwargs dict 생성.  
     - `py_object_call(callable_id, args, kwargs_id)` 호출.  
   - CALL 실행 후 `pending_kw_names_const_i := NULL`.

4. **테스트**
   - 기존 CALL_FUNCTION_KW 통합 테스트를 3.11 스타일로:  
     `KW_NAMES const_i` + 인자 푸시 + `PRECALL n` + `CALL n`, co_consts에 키워드 이름 tuple 넣어 두기.

### Phase 3: PUSH_NULL(2)

**목표:** `obj.method(...)` 같은 호출에서 스택에 NULL이 있는 경우 처리.

1. **NULL 표현**
   - 부트스트랩에 `Py_NULL` 타입(또는 예약 UUID) 정의.  
   - `PUSH_NULL`: 해당 값 push.

2. **CALL 확장**
   - callable pop 직후, 현재 TOS가 "NULL"이면 1개 더 pop(호출 인자로는 사용하지 않음).

3. **테스트**
   - bound method 호출 등 PUSH_NULL이 나오는 바이트코드로 검증.

### Phase 4: 정리 및 고증 점검

- [ ] 모든 호출 관련 테스트를 3.11 opcode(PRECALL, CALL, KW_NAMES, PUSH_NULL) 기준으로 통과시키기.
- [ ] `CALL_FUNCTION`/`CALL_FUNCTION_KW` 코드 및 참조 제거(또는 레거시 분기로만 유지).
- [ ] VM_DESIGN.md·README 등에 "호출은 3.11 CALL 프로토콜 사용" 명시.
- [ ] run_tests.sh에서 호출 관련 Phase 순서 유지.

---

## 6. 마이그레이션·파일 배치

- **기존 파일 수정 원칙**: 새 마이그레이션을 추가하기보다, 기존 호출 관련 마이그레이션을 **같은 파일에서 CREATE OR REPLACE**로 바꾸는 방식을 우선한다.
- **추가 마이그레이션**이 필요하면:
  - PRECALL/CALL/KW_NAMES: `20260114240302_opcode_call_function.sql`를 **3.11 CALL 프로토콜**로 교체하는 마이그레이션 하나.
  - PUSH_NULL: opcode 2 처리 및 NULL 싱글턴은 부트스트랩 또는 별도 작은 마이그레이션.
- **eval_frame**: `20260114241100_ceval_eval_frame.sql`에서 141/142 분기 제거, 2/166/171/172 추가.

---

## 7. 위험·주의사항

- **LOAD_GLOBAL(116)·LOAD_FAST(124)**: 3.11 컴파일 결과는 `len(x)`를 LOAD_GLOBAL + LOAD_FAST + PRECALL + CALL로 낼 수 있음. Elytra가 아직 116/124를 구현하지 않았다면, **테스트용 바이트코드는 LOAD_NAME + LOAD_CONST**로 수동 구성해 동일 시맨틱만 검증.
- **CALL oparg 해석**: CPython ceval.c에서 CALL oparg가 "위치만"인지 "위치+키워드"인지 소스로 한 번 더 확인 후, 위 "옵션 A"가 맞으면 그대로, 아니면 oparg 해석만 수정.
- **CACHE(0)**: 3.11 바이트코드에는 PRECALL/CALL 뒤에 CACHE가 붙을 수 있음. CACHE 처리를 먼저 넣어 두면, 나중에 3.11 생성 바이트코드를 그대로 넣었을 때 오동작을 줄일 수 있음.

---

## 8. 참고

- CPython: `Python/ceval.c` (PRECALL/CALL 분기), `Include/opcode.h`, `Lib/opcode.py`.
- Elytra: `docs/TP_CALL_KWARGS_DESIGN.md`, `docs/CHANGE_3_TP_CALL_KWARGS_PLAN.md`.
- Python 3.11 dis: `PRECALL`, `CALL`, `KW_NAMES`, `PUSH_NULL` 설명 및 예제.
