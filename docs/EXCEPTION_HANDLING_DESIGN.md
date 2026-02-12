# 예외 처리 설계 (CPython 3.11 고증)

CPython 3.11의 예외 모델에 맞춘 Pgthon 예외 처리 설계다. 임시 구현 없이, 문서·스키마·시맨틱을 한 번에 정의한다.

**참고:** Python 3.11에서는 `SETUP_EXCEPT`/`SETUP_FINALLY`가 제거되고 **exception table** (`co_exceptiontable`) 기반으로 동작한다. 이 설계는 3.11만 대상으로 한다.

---

## 1. CPython 3.11 요약

### 1.1 Error indicator (예외 상태)

- **위치:** 스레드당 하나 (C API: `PyThreadState` 내부). Pgthon는 스레드가 없으므로 **실행 컨텍스트당 하나**로 둠.
- **구성:** 세 개의 객체 참조
  - `exc_type`: 예외 타입 (클래스 객체)
  - `exc_value`: 예외 값 (인스턴스, 보통 `BaseException` 서브클래스)
  - `exc_traceback`: traceback 객체 (NULL 가능)
- **의미:** “아직 처리되지 않은, 전파 중인 예외”. `sys.exc_info()`와 구분됨 (exc_info는 이미 잡힌 예외).
- **설정:** `PyErr_SetObject(type, value)` 등. 설정 시 traceback은 나중에 `PyTraceBack_Here(frame)` 등으로 채움.

### 1.2 예외 객체 (BaseException)

- **계층:** `BaseException` → `Exception` → `TypeError`, `ValueError`, `NameError` 등.
- **인스턴스 필드 (Python 쪽):**
  - `args`: 생성자에 넘긴 인자 tuple
  - `__traceback__`: traceback 객체
  - `__cause__`: `raise ... from ...` 로 설정한 예외
  - `__context__`: 예외가 발생한 컨텍스트(이전 예외)
  - `__suppress_context__`: True면 `__context__` 출력 생략

### 1.3 RAISE_VARARGS (opcode 130)

- **인자 (argc):**
  - **0:** `raise` (re-raise). 현재 error indicator 그대로 두고, exception table 조회 후 unwinding.
  - **1:** `raise TOS`. 스택에서 1개 pop → 타입 또는 인스턴스. 인스턴스면 (type, value) 추출; 타입만 있으면 value = None 등으로 정규화 후 error indicator 설정, 그다음 unwinding.
  - **2:** `raise TOS1 from TOS`. 스택에서 2개 pop (cause, exc). exc로 error indicator 설정, exc의 `__cause__`를 cause로 설정, unwinding.

### 1.4 Exception table (3.11)

- **위치:** `PyCodeObject.co_exceptiontable` (bytes). Pgthon에서는 `py_code_object.co_exceptiontable`.
- **역할:** “이 바이트코드 범위에서 예외가 나면, 이 오프셋으로 점프하고, 스택을 이 깊이로 맞춘다.”
- **항목:** (start, end, target, depth, lasti) — 3.11에서는 **instruction offset** 기준. start ≤ 현재 오프셋 < end 인 항목을 찾아 target으로 점프, 스택을 depth로 trim.
- **동작:** 예외 발생 시 현재 `i`(instruction offset)로 테이블 조회 → 매칭되는 (target, depth) 사용 → `next_i := target`, 스택을 depth개만 남기고 pop, 루프 계속.

### 1.5 3.11에서 스택 위 “예외 표현”

- **예외는 스택에 “한 개” 객체로 표현** (이전의 type/value/traceback 세 개 아님).
- `PUSH_EXC_INFO`: 스택에서 한 개 pop → 현재 예외를 스택에 push → pop 했던 값 다시 push (핸들러에서 현재 예외 쓰기 위함).
- `POP_EXCEPT`: 스택에서 한 개 pop → 그 값으로 예외 상태 복원 (except 블록 탈출 시).
- `RERAISE`: 스택 top을 예외로 보고 re-raise (한 개 pop 후 그걸로 error indicator 설정 후 unwinding).

### 1.6 관련 opcode (3.11)

| opcode | 이름 | 시맨틱 |
|--------|------|--------|
| 130 | RAISE_VARARGS | argc 0/1/2에 따라 위와 같이 동작 |
| 119 | RERAISE | 스택 top 1개 = 예외, re-raise |
| 89 | POP_EXCEPT | 스택 1개 pop → 예외 상태 복원 |
| 35 | PUSH_EXC_INFO | 현재 예외를 스택에 push (기존 TOS는 잠깐 빼두었다가 다시 push) |
| 36 | CHECK_EXC_MATCH | except Type: 에서 매칭 여부 (TOS = 타입, TOS1 = 예외 → pop 1, boolean push) |
| 151 | RESUME | no-op (트레이싱/디버깅 등). where 0=함수 시작, 1=yield 후, 2=yield from 후, 3=await 후 |

---

## 2. Pgthon 설계

### 2.1 예외 상태 저장소

- **테이블:** `py_exception_state` (실행 컨텍스트당 1행, 스레드 없으면 1행만 사용).
- **컬럼:**
  - `id` uuid PRIMARY KEY (고정 1개 사용 시 상수 UUID 가능)
  - `exc_type_id` uuid REFERENCES py_object(id) — 예외 타입
  - `exc_value_id` uuid REFERENCES py_object(id) — 예외 인스턴스
  - `exc_traceback_id` uuid REFERENCES py_object(id) — traceback (NULL 가능)
- **규칙:** `exc_type_id`가 NULL이면 “예외 없음”. NULL이 아니면 반드시 `exc_value_id`도 설정 (value만 NULL 허용하는 경우는 C API에서만, 여기서는 항상 인스턴스 보관).
- **생명주기:** `py_eval_frame` 진입 시 기존 상태를 “백업”할지 여부는 호출 규약으로 정한다. raise 시 이 테이블을 갱신; handler에서 catch 후 clear 또는 POP_EXCEPT로 복원.

### 2.2 예외 타입 계층 (bootstrap)

- **객체:** `py_type_object` + `py_object` 로 기존 타입과 동일하게 표현.
- **최소 도입 타입 (고정 UUID 권장):**
  - `BaseException` (object 서브클래스)
  - `Exception` (BaseException 서브클래스)
  - `TypeError`, `ValueError`, `NameError`, `RuntimeError` (Exception 서브클래스)
- **인스턴스:** 예외 “값”은 보통 `BaseException` 서브클래스 인스턴스. Pgthon에서는 **별도 테이블 없이** `py_object` + `ob_type`으로만 구분해도 되고, 필요 시 `py_base_exception_object` 같은 테이블에 `ob_args` (tuple uuid) 등을 두어 `args`를 표현할 수 있다.
- **최소 구현:** `py_base_exception_object(ob_base, ob_args uuid)` — `ob_args`는 인자 tuple. `__cause__`/`__context__`/`__traceback__`는 1단계에서는 NULL/미구현 가능, 단 문서에는 “나중에 확장”으로 명시.

### 2.3 Traceback

- **테이블:** `py_traceback_object(ob_base, tb_next uuid, tb_frame uuid, tb_lasti integer)`.
  - `tb_next`: 다음 traceback (연결 리스트)
  - `tb_frame`: 해당 프레임
  - `tb_lasti`: 해당 프레임의 마지막 instruction (byte offset 또는 instruction index, 3.11 문서에 맞춤)
- **생성:** raise 시 현재 프레임부터 `f_back` 따라가며 traceback 체인 생성. `PyTraceBack_Here(frame)`에 대응하는 함수 `py_traceback_here(frame_id)`로 “현재 예외”의 traceback에 현재 프레임을 앞에 붙인다.

### 2.4 Code object 확장

- **`py_code_object`에 추가:**
  - `co_exceptiontable` bytea — 3.11 형식 그대로 저장. 비어 있으면 예외 처리 구간 없음.
- **파싱:** exception table 바이너리 포맷은 CPython 소스(`Objects/exception_handling.c` 등)와 동일하게 파싱하는 함수를 둔다. 반환: (start, end, target, depth, lasti) 리스트. **instruction offset** 단위로 통일 (3.10+).

### 2.5 Frame 확장 (선택)

- CPython 3.11에서는 generator 등에서 “프레임별 예외 스왑”을 위해 `f_exc_type`, `f_exc_value`, `f_exc_traceback`를 쓰지만, Pgthon 1단계에서는 **전역(단일) py_exception_state만** 써도 됨.
- 나중에 generator/코루틴을 넣을 때 프레임에 예외 상태 컬럼을 추가할 수 있다.

### 2.6 py_eval_frame 동작 (예외 경로)

1. **일반 opcode 실행 중**  
   opcode 핸들러가 “예외를 설정”하려면 (예: BINARY_ADD에서 TypeError)  
   - **PL/pgSQL RAISE EXCEPTION 대신**  
   - `py_err_set_object(type_id, value_id)` 호출: `py_exception_state` 행을 갱신하고, traceback은 `py_traceback_here(current_frame_id)`로 채움.  
   - 그 다음 **반환하지 않고** “예외 디스패치”로 넘어감: 현재 `i`로 exception table 조회 → (target, depth) 있으면 `next_i := target`, 스택을 depth로 trim, 루프 계속; 없으면 상위로 전파 (호출자에게 반환 시 “예외 발생”을 알리는 방식, 예: 특별한 return 값 또는 OUT 파라미터).

2. **RAISE_VARARGS(0):**  
   현재 `py_exception_state`가 비어 있으면 RuntimeError “No active exception to re-raise”. 아니면 exception table 조회 후 위와 동일하게 unwinding.

3. **RAISE_VARARGS(1):**  
   TOS 1개 pop → 타입/인스턴스 정규화 → `py_err_set_object(type, value)`, traceback 붙임, exception table 조회 후 unwinding.

4. **RAISE_VARARGS(2):**  
   TOS, TOS1 pop (cause, exc) → exc로 예외 설정, exc의 `__cause__`를 cause로 설정, traceback 붙임, unwinding.

5. **RERAISE:**  
   TOS 1개 pop (예외 인스턴스) → 그걸로 error indicator 설정, unwinding.

6. **POP_EXCEPT:**  
   TOS 1개 pop → 그 값으로 `py_exception_state` 복원 (이전에 PUSH_EXC_INFO 등으로 스택에 넣어 둔 “저장된 예외 상태” 복원).

7. **PUSH_EXC_INFO:**  
   TOS 1개 pop (v) → 현재 예외(한 개 객체 표현)를 스택에 push → v 다시 push. (스택 순서는 3.11 dis 문서대로.)

8. **CHECK_EXC_MATCH:**  
   TOS = match type, TOS1 = 예외. `isinstance(exc, type)`에 해당하는 판별 후 TOS pop, 결과 boolean push.

- **Unwinding 시:**  
  exception table에 (start, end, target, depth)가 있으면, 스택을 depth만큼 남기고 pop, `i := target`으로 점프. 없으면 현재 프레임을 끝내고 호출자에게 “예외 전파”를 반환한다 (호출자도 자신의 exception table을 본다).

### 2.7 기존 “RAISE EXCEPTION” 제거

- **원칙:** VM/opcode 쪽에서는 **PL/pgSQL RAISE EXCEPTION을 쓰지 않는다.**  
  TypeError, NameError 등은 모두  
  1) 해당 타입/인스턴스 객체를 만들고  
  2) `py_err_set_object(type_id, value_id)`로 설정한 뒤  
  3) exception table 기반 unwinding으로 처리한다.  
- **DB 레벨 오류** (frame 없음, code 없음 등)만 PL/pgSQL RAISE EXCEPTION 유지 가능. 이때는 “Python 예외”가 아니라 “Pgthon 런타임 오류”로 구분한다.

---

## 3. 구현 순서 제안

### 3.1 의존 관계 (먼저 해야 할 것)

```
[1] 스키마
     ↓
[2] 예외 설정/조회     [3] Exception table 파싱   ← 둘 다 1만 의존, 병렬 가능
     ↓                        ↓
     └──────────┬─────────────┘
                ↓
[4] py_eval_frame 확장
     ↓
[5] 기존 opcode 정리 (RAISE EXCEPTION → py_err_set_object + unwinding)
     ↓
[6] 테스트
```

- **1 → 2, 3:** 스키마 없으면 예외 상태·traceback·exception table을 쓸 수 없음.
- **2, 3 → 4:** unwinding은 예외 상태 + exception table 조회가 있어야 함. RAISE_VARARGS 등은 `py_err_set_object`에 의존.
- **4 → 5:** eval_frame에 “예외 경로”가 들어가야, opcode에서 예외를 설정했을 때 unwinding이 동작함.
- **5 → 6:** 전체 경로가 연결된 뒤에 테스트.

### 3.2 작업 내용

1. **스키마**
   - `py_exception_state` 테이블 추가.
   - `py_base_exception_object` (또는 예외 인스턴스용 최소 테이블) 추가.
   - `py_traceback_object` 추가.
   - `py_code_object`에 `co_exceptiontable` bytea 추가.
   - Bootstrap에 BaseException, Exception, TypeError, ValueError, NameError 타입 및 필요 시 기본 인스턴스 생성.

2. **예외 설정/조회**
   - `py_err_set_object(type_id, value_id)`, `py_err_clear()`, `py_err_occurred()` (또는 `py_err_get_raised()` 스타일) 구현.
   - `py_traceback_here(frame_id)` 구현 (현재 예외에 현재 프레임 추가).

3. **Exception table 파싱**
   - `co_exceptiontable` bytea → (start, end, target, depth[, lasti]) 리스트 반환 함수. 3.11 바이너리 포맷 준수.

4. **py_eval_frame 확장**
   - opcode 실행 루프에서 “예외 설정”이 일어나면 즉시 RAISE EXCEPTION 하지 말고, `py_err_set_object` + traceback 후 exception table 조회 및 unwinding 분기.
   - RAISE_VARARGS(0/1/2), RERAISE, POP_EXCEPT, PUSH_EXC_INFO, CHECK_EXC_MATCH opcode 핸들러 추가.
   - 루프 끝에서 “반환” 시, 예외가 남아 있으면 호출자에게 예외 전파를 알리는 방식 정의 (예: OUT 파라미터 또는 특수 return 값).

5. **기존 opcode 정리**
   - BINARY_ADD, COMPARE_OP, LOAD_NAME 등에서 `RAISE EXCEPTION 'TypeError: ...'` 제거 → `py_err_set_object(TypeError_id, value_id)` + unwinding 호출로 교체.

6. **테스트**
   - `raise TypeError('msg')` → exception table로 핸들러 점프, `except TypeError` 매칭.
   - `1 + "a"` → TypeError 설정 후 unwinding, try/except로 잡히는지 검증.

---

## 4. 참고 자료

- **Python 3.11 dis:** https://docs.python.org/3.11/library/dis.html (RAISE_VARARGS, RERAISE, POP_EXCEPT, PUSH_EXC_INFO, CHECK_EXC_MATCH, RESUME)
- **C API Exceptions:** https://docs.python.org/3/c-api/exceptions.html (error indicator, PyErr_SetObject, PyErr_Occurred, traceback)
- **Python 3.11 exception table:** SETUP_EXCEPT 제거, `co_exceptiontable` (start, end, target, depth, lasti) — instruction offset
- **Include/opcode.h (3.11):** RAISE_VARARGS 130, RERAISE 119, POP_EXCEPT 89, PUSH_EXC_INFO 35, CHECK_EXC_MATCH 36, RESUME 151

---

## 5. VM_DESIGN.md와의 정리

- **Phase 5** 문구를 다음처럼 바꾸는 것을 권장한다.
  - “Exception 객체” → 이 문서 §2.2
  - “RAISE_VARARGS” → 이 문서 §1.3, §2.6
  - “SETUP_EXCEPT” → **삭제.** 3.11에서는 **exception table** (§1.4, §2.4, §2.6)으로 대체.
- **고려사항 §4 Exception Handling:** “f_blockstack 추가” 대신 “예외 상태는 `py_exception_state`, try/except는 **exception table**로 처리”라고 명시.

이 설계는 **임시 구현 없이** CPython 3.11 동작에 맞춘 예외 처리 경로를 정의한다. 구현 시 위 순서대로 진행하면 된다.
