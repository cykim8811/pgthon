# 예외 처리 설계 감사 — CPython 고증·임시방편 검토

프로젝트 내 예외 처리 관련 설계·코드를 검토하고, CPython 고증에 맞지 않는 부분과 임시방편을 정리한 문서다. (인터넷 검색 없이, 코드베이스·CPython 지식 기준.)

**→ 정식 설계:** **docs/EXCEPTION_HANDLING_DESIGN.md** (CPython 3.11 고증, exception table, RAISE_VARARGS, 예외 객체·상태·traceback, 임시 구현 없음)

---

## 1. 현재 문서·코드에서 확인된 내용

### 1.1 VM_DESIGN.md Phase 5 (유일한 예외 설계 언급)

- **Phase 5: 예외 처리** (3줄)
  1. Exception 객체
  2. `RAISE_VARARGS`: 예외 발생
  3. `SETUP_EXCEPT`: 예외 처리 블록

- **고려사항 §4 Exception Handling**
  - Frame의 block stack 필요할 수 있음
  - 현재 스키마에는 없음
  - 해결책: 필요시 `f_blockstack` 추가

→ 예외 객체 구조, RAISE_VARARGS 시맨틱, 예외 상태 저장 위치, 블록 스택 형식, traceback 등에 대한 **설계 문서는 없음**.

### 1.2 스키마

- **py_frame_object** (224000): `f_code`, `f_globals`, `f_locals`, `f_builtins`, `f_back`, `f_valuestack`, `f_lasti`만 존재.
  - **예외 상태**(exc_type, exc_value, exc_traceback) 없음.
  - **f_blockstack**(또는 블록 스택용 컬럼) 없음.
- **py_object / bootstrap** (220000, 223000): object, type, str, int, float, list, dict, tuple, NoneType, bool, builtin_function_or_method, module, NotImplemented 타입·싱글톤만 생성.
  - **BaseException, Exception, TypeError, ValueError** 등 예외 타입·객체 **없음**.

### 1.3 현재 “예외” 구현 방식

- 모든 TypeError, NameError 등은 **PL/pgSQL `RAISE EXCEPTION 'TypeError: ...'`** 로만 처리됨.
- 즉, **PostgreSQL 예외**를 던지는 방식이며, **Python 예외 객체**를 만들거나 VM이 “예외 상태 + unwinding”을 하는 구조가 아님.
- `py_eval_frame` 주석에는 “An exception is raised (propagated to caller)”라고 되어 있으나, 실제로는 DB 예외가 상위로 전파될 뿐, **Python 수준의 except 블록**이나 **예외 객체/타입/메시지**를 VM이 다루지 않음.

---

## 2. CPython 고증과의 차이 (요지만)

### 2.1 예외는 “객체”이고, 상태가 따로 있음

- CPython: 예외는 **PyObject** (타입 + 인스턴스, 보통 `args` 등).  
  “현재 활성 예외”는 **스레드(또는 인터프리터)별 예외 상태** (exc_type, exc_value, exc_traceback)에 보관.
- Elytra: **예외 타입/인스턴스용 타입 객체·테이블이 없고**, 예외 상태를 넣을 **프레임/스레드/인터프리터 쪽 필드도 없음**.  
  → “Exception 객체” 설계가 없고, 고증상 예외 상태를 둘 위치도 정해져 있지 않음.

### 2.2 RAISE_VARARGS 시맨틱

- CPython: **RAISE_VARARGS**는 인자(0/1/2)에 따라  
  - 0: 현재 예외 상태로 re-raise  
  - 1: TOS 하나 pop (예외 인스턴스 또는 타입)  
  - 2: 타입·값 두 개 pop  
  등으로 **스택에서 꺼낸 값으로 예외 상태를 설정**한 뒤 unwinding.
- Elytra: RAISE_VARARGS opcode 자체가 없고, “예외 상태” 개념도 없음.  
  → 설계만 보면 **RAISE_VARARGS 동작이 정의되어 있지 않음**.

### 2.3 SETUP_EXCEPT와 3.11

- VM_DESIGN에는 **SETUP_EXCEPT**가 “예외 처리 블록”으로만 나옴.
- CPython **3.11**에서는 예외 처리 바이트코드가 이전과 다름.  
  **SETUP_EXCEPT / SETUP_FINALLY** 같은 블록 설정 opcode가 3.11에서는 제거·대체되고, **exception table + RESUME** 등 다른 구조를 씀.
- 프로젝트는 **Python 3.11** (uniform 2-byte, JUMP_FORWARD 110 등)을 기준으로 하고 있으므로, **“SETUP_EXCEPT”만 쓰는 현재 문구는 3.11 고증과 맞지 않음**.  
  → 3.11용 예외 처리 메커니즘(exception table 등)을 설계에 반영할 필요가 있음.

### 2.4 블록 스택·unwinding

- CPython: try/except/finally는 **프레임의 block stack** (b_type, b_handler, b_level 등)으로 관리하고, raise 시 이 스택을 **unwind** 하며 핸들러로 점프.
- Elytra: **f_blockstack(또는 동일 역할) 미정의**.  
  → “필요시 f_blockstack 추가”는 방향만 맞고, **구체적인 블록 타입·형식·unwinding 규칙**은 비어 있음.

### 2.5 Traceback

- CPython: 예외에는 **traceback** (PyTracebackObject: tb_next, tb_frame, tb_lasti 등)이 붙음.
- Elytra: VM_DESIGN·스키마·코드 어디에도 **traceback 객체·필드**가 없음.  
  → 고증상 traceback 설계가 빠져 있음.

---

## 3. 임시방편 정리

| 항목 | 현재 상태 | CPython 관점 |
|------|-----------|--------------|
| 예외 표현 | 모든 오류를 PL/pgSQL `RAISE EXCEPTION 'TypeError: ...'` 등 **문자열 메시지**로만 처리 | 예외는 **PyObject**(타입+인스턴스, args 등). VM은 **예외 상태 3종세트**(type, value, traceback)로 다룸 |
| 예외 타입 | **TypeError, Exception 등 타입 객체·인스턴스 없음**. bootstrap에 예외 계층 없음 | BaseException → Exception → TypeError 등 **타입 객체 + 인스턴스** 존재 |
| 예외 전파 | DB 예외가 트랜잭션/호출 스택으로 전파될 뿐, **VM 수준의 except 블록·핸들러 점프 없음** | raise 시 **block stack unwinding + 핸들러로 점프**, except에서 **Python 객체로 catch** |
| RAISE_VARARGS | opcode 없음, 설계 없음 | 스택에서 0/1/2개 pop → 예외 상태 설정 → unwinding |
| Block stack | 프레임에 **블록 스택 없음** | 프레임에 block stack, try/except/finally용 |
| SETUP_EXCEPT | 문서에 이름만 등장 | 3.11에서는 **다른 메커니즘**(exception table 등)으로 대체됨 — 3.11 고증과 불일치 |
| Traceback | 없음 | 예외에 traceback 객체 연결 |

→ 정리하면, **“예외 처리”는 현재 전부 임시방편**이다.  
문자열 메시지 + DB 예외로만 동작하고, **Python 예외 객체·예외 상태·unwinding·except 동작·3.11 바이트코드**는 설계·구현 모두 비어 있음.

---

## 4. 결론 및 제안

- **CPython 고증과 안 맞는 점**
  - 예외를 “객체 + 예외 상태”로 다루는 설계가 없음.
  - RAISE_VARARGS 시맨틱·저장 위치 미정의.
  - **SETUP_EXCEPT**만 언급한 것은 **Python 3.11** 예외 처리와 맞지 않음 (3.11은 exception table 등 다른 구조).
  - Block stack 형식·unwinding 규칙 미정의.
  - Traceback 설계 없음.

- **임시방편**
  - 모든 “TypeError/NameError/…” 는 **PL/pgSQL RAISE EXCEPTION** 한 가지 방식뿐이며, Python 예외 객체·VM 수준 catch/unwinding은 없음.

- **다음 단계 제안**
  1. **예외 전용 설계 문서** 작성: 예외 타입 계층(BaseException/Exception/TypeError 등), 예외 상태 저장 위치(프레임 vs “스레드/인터프리터” 대응 개념), RAISE_VARARGS(0/1/2) 동작, **3.11 기준** 예외 처리 바이트코드(exception table·RESUME 등) 반영.
  2. **SETUP_EXCEPT** 문구를 3.11에 맞게 수정: “예외 처리 블록”은 유지하되, 3.11에서는 SETUP_EXCEPT 대신 **exception table + 해당 opcode**를 쓰는 식으로 설계 명시.
  3. **스키마**: 예외 상태용 컬럼(또는 별도 테이블), 필요 시 **f_blockstack**(또는 3.11에 대응하는 블록 정보) 추가 방안을 설계 문서에 명시.
  4. **bootstrap**: BaseException, Exception, TypeError 등 **예외 타입 객체**와, 필요하면 기본 인스턴스 생성 방안을 설계에 포함.

이 문서는 인터넷 검색 없이, 저장소 내 문서·스키마·코드와 CPython 동작에 대한 일반 지식만으로 작성했다.
