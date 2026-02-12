# Python 예외 통일 계획 (CPython 고증, 임시구현 없음)

**목표:** Python 런타임에서 발생할 수 있는 오류는 모두 **Python 예외 상태**(`py_err_set_*` + NULL 반환)로 통일하고, VM/내부 검증 실패만 PL/pgSQL `RAISE EXCEPTION`으로 둔다.

---

## 1. 구분 기준

| 구분 | 의미 | 처리 방식 |
|------|------|-----------|
| **Python 런타임 오류** | Python 코드 실행 중 발생하는 오류 (TypeError, ValueError, AttributeError 등). CPython에서는 `PyErr_SetObject` 등으로 error indicator 설정 후 NULL 반환. | `py_err_set_type_error`(등) 호출 후 **RETURN NULL**. 호출부는 NULL 반환·`py_err_occurred()`로 검사. |
| **VM/내부 오류** | 객체 ID 없음, 프레임 없음, co_consts 인덱스 초과, tp_call regproc 미해결 등. 정상 바이트코드/객체 그래프에서는 발생하지 않는 오류. | **RAISE EXCEPTION** 유지. |

---

## 2. 완료된 항목

다음은 이미 Python 예외 + NULL 반환·호출부 NULL 처리·테스트 Python 예외 검사로 반영된 상태다.

| 항목 | 구현 | 호출부 | 테스트 |
|------|------|--------|--------|
| **py_call_cfunction**: 인자 개수 오류 (METH_O/METH_NOARGS) | `py_err_set_type_error` + RETURN NULL (233000) | `py_opcode_CALL_FUNCTION`: result NULL이면 push 안 함 (233000) | 14 Test 5: `py_err_occurred()`, `exc_type_id` 검사 |
| **py_call_cfunction**: kwargs 거부 (len/abs 등) | `py_err_set_type_error` + RETURN NULL (233000) | 동일 (CALL_FUNCTION_KW도 result NULL이면 push 안 함) | 35, 36: `py_err_occurred()`, exc_type_id, 메시지 검사 |

---

## 3. 남은 항목 (계획)

### 3.1 non-callable 호출 (TypeError: 'X' object is not callable)

**현재:** `py_object_call`(234000)에서 `tp_call IS NULL`이면  
`RAISE EXCEPTION 'TypeError: ''%'' object is not callable'`  
→ PL/pgSQL 예외로 블록 중단.

**CPython:** `PyObject_Call()`에서 호출 불가 객체면 `PyErr_Format(PyExc_TypeError, "'%.200s' object is not callable", type->tp_name)` 후 NULL 반환.

**변경:**

1. **구현 (234000 tp_call_slot)**  
   - `py_object_call` 내부: `tp_call IS NULL`인 경우  
     - `PERFORM public.py_err_set_type_error(''' || COALESCE(func_type_name, 'unknown') || ''' object is not callable');`  
     - `RETURN NULL;`  
   - `RAISE EXCEPTION 'TypeError: ...'` 제거.  
   - `py_err_set_type_error`는 224300에서 정의되며 234000은 그 이후 마이그레이션이므로 의존성 OK.

2. **호출부**  
   - `py_opcode_CALL_FUNCTION`(233000)은 이미 `result_id IS NULL`이면 push 하지 않고 반환.  
   - `py_eval_frame`은 NULL 반환 시 상위에서 `py_err_occurred()`로 처리.  
   - 추가 변경 없음.

3. **테스트 (14_ceval_opcode_call_function.sql)**  
   - Test 4: non-callable 호출 시 **EXCEPTION WHEN OTHERS** 제거.  
   - `py_err_clear()` 후 `PERFORM py_opcode_CALL_FUNCTION(frame_id, 0)`.  
   - `py_err_occurred()` = true, `exc_type_id` = TypeError, 예외 메시지에 `object is not callable` 포함 여부 검사.

**메시지 형식:**  
CPython은 `"'%.200s' object is not callable"` (타입 이름). Pgthon도 타입 이름만 넣어 동일하게 맞춘다.  
`py_err_set_type_error` 인자는 한 개(text)이므로 `'''' || func_type_name || ''' object is not callable'` 형태로 전달 (따옴표 이스케이프는 PL/pgSQL 규칙에 맞게).

---

## 4. RAISE EXCEPTION 유지 (VM/내부 오류)

다음은 Python 런타임 오류가 아니라 VM/구현 검증 오류이므로 **RAISE EXCEPTION 유지**한다.

| 위치 | 내용 |
|------|------|
| **234000 py_object_call** | "Object with id % does not exist", "Object with id % does not have a type", "tp_call regproc % does not resolve to a function" |
| **233000 py_call_cfunction** | "Function object with id % does not exist", "Function implementation (m_ml_meth) not found", "Unsupported calling convention (m_ml_flags=%)" |
| **233000 py_opcode_CALL_FUNCTION** | "CALL_FUNCTION: arg_count must be non-negative" (오코드 인자 검증) |
| **233000 py_opcode_CALL_FUNCTION_KW** | "CALL_FUNCTION_KW: arg must be 0-255", "keyword name must be str (ob_type check)" |
| **233000 LOAD_CONST / BUILD_* 등** | "Frame with id % does not exist", "Index % out of range for co_consts tuple" 등 |
| **230000 ceval_core** | "PyObject with id % does not exist" (stack push 시 객체 검증) |

---

## 5. 의존 관계

```
[224300 py_err_set_type_error]  ← 이미 존재 (선행 마이그레이션)
         │
         ▼
[234000 py_object_call 수정]    ← non-callable 시 Python 예외 + NULL (구현)
         │
         ▼
[14 Test 4 수정]                ← non-callable 테스트가 위 동작을 검증
         │
         ▼
[검증: db reset + run_tests.sh]
```

| 작업 | 선행 조건 | 이유 |
|------|-----------|------|
| **234000 구현** | 224300 적용됨 (py_err_set_type_error 존재) | 마이그레이션 순서상 234000이 224300 이후라 이미 만족. |
| **14 Test 4 수정** | 234000 구현 완료 | 테스트가 “non-callable → Python 예외 세팅 + NULL”을 검증. 구현을 먼저 바꿔야 테스트가 새 동작을 기대할 수 있음. |
| **검증** | 234000 + 14 Test 4 완료 | 두 변경이 모두 반영된 뒤에만 전체 테스트 통과 의미 있음. |

**역방향 시 실패:** 14 Test 4만 먼저 바꾸면, 구현은 여전히 RAISE EXCEPTION이라 블록이 중단되고 Python 예외가 세팅되지 않아 테스트가 실패함.

---

## 6. 실행 순서 (가장 먼저 실행할 것부터)

1. **1순위: 구현 — 234000 tp_call_slot**
   - 파일: `supabase/migrations/20260114234000_tp_call_slot.sql`
   - `py_object_call` 내부, `tp_call IS NULL` 분기에서:
     - `PERFORM public.py_err_set_type_error(''' || COALESCE(func_type_name, 'unknown') || ''' object is not callable');`
     - `RETURN NULL;`
   - `RAISE EXCEPTION 'TypeError: ''%'' object is not callable', ...` 제거.

2. **2순위: 테스트 — 14 Test 4**
   - 파일: `supabase/tests/14_ceval_opcode_call_function.sql`
   - Test 4: non-callable 호출:
     - `BEGIN ... EXCEPTION WHEN OTHERS` 제거.
     - `py_err_clear()` → `PERFORM py_opcode_CALL_FUNCTION(frame_id, 0)` → `py_err_occurred()`·`exc_type_id`(TypeError)·메시지에 `object is not callable` 포함 여부 검사.

3. **3순위: 검증**
   - `pnpm dlx supabase db reset` 후 `./run_tests.sh` 실행.
   - Phase 14, 35, 36, 46 포함 전체 통과 확인.

---

## 7. 참고

- **EXCEPTION_HANDLING_DESIGN.md**: error indicator, `py_err_set_object`/`py_err_occurred` 등 시맨틱.
- **CPython:** `Objects/typeobject.c` `type_call`, `PyObject_Call`; `Python/ceval.c` CALL 관련 오코드에서 NULL 반환 시 예외 전파.
