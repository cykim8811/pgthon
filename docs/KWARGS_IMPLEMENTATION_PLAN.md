# kwargs 구현 기획 — CPython 고증·임시방편 없는 깨끗한 구현

CPython의 `PyObject_Call(callable, args, kwargs)` 및 `tp_call(callable, args, kwargs)` 고증에 맞춰 Elytra에서 kwargs를 어떻게 구현·검증·확장할지 단계별로 정리한 기획 문서다.

- **설계 배경**: `docs/TP_CALL_KWARGS_DESIGN.md`
- **실행 체크리스트**: `docs/CHANGE_3_TP_CALL_KWARGS_PLAN.md`

---

## 1. CPython 쪽 고증 요약

### 1.1 호출 API

| CPython | Elytra 대응 |
|--------|-------------|
| `PyObject_Call(obj, args, kwargs)` | `py_object_call(obj_id, args, kwargs_id)` |
| `args`: tuple, **non-NULL** (인자 없으면 빈 tuple) | `args`: `UUID[]`, 빈 배열 가능 |
| `kwargs`: dict 또는 **NULL** (키워드 없음) | `kwargs_id`: dict의 `py_object.id` 또는 **NULL** |

- **tp_call 시그니처** (ternaryfunc):  
  `PyObject* (*tp_call)(PyObject* callable, PyObject* args, PyObject* kwargs)`  
  → 호출 시 **항상 인자 3개** (callable, args, kwargs). kwargs 없으면 NULL.

### 1.2 C 함수 호출 규약 (PyCFunction)

| 플래그 | 값 | 의미 | kwargs 허용 |
|--------|---|------|-------------|
| METH_VARARGS | 0x0001 | 위치 인자만 (args tuple) | 거절 |
| METH_KEYWORDS | 0x0002 | 키워드 인자 받음 (kwargs dict) | 허용 |
| METH_NOARGS | 0x0004 | 인자 없음 | 거절 |
| METH_O | 0x0008 | 인자 1개 (단일 PyObject*) | 거절 |

- **kwargs 거절 시 에러**: `TypeError: name() takes no keyword arguments`  
  - CPython: 함수 **이름**만 넣고, 이름 주변에 따옴표 없음. 예: `len() takes no keyword arguments`.
- **이름 출처**: `PyCFunction`의 `m_ml->ml_name` (C 문자열). Elytra에서는 `m_ml_name`(uuid) → `py_unicode_object.str_value`. **타입 이름(`tp_name`)이나 `'builtin'`으로 대체하지 않고**, 반드시 `m_ml_name`으로만 조회.

### 1.3 바이트코드

| Opcode | 의미 | kwargs |
|--------|------|--------|
| CALL_FUNCTION | 위치 인자만 | **NULL**로 호출 |
| CALL_FUNCTION_KW | 위치 + 키워드 | 스택에서 이름·값을 모아 dict 생성 후 `kwargs_id`로 전달 |

---

## 2. 현재 구현 상태 (확인 결과)

- **234000 (tp_call_slot.sql)**  
  - `py_object_call(obj_id, args, kwargs_id DEFAULT NULL)` 이미 3인자.  
  - tp_call 호출: `EXECUTE ... ($1, $2, $3)` 로 **항상 3인자** 전달.  
  - 규약에 맞음.

- **233000 (ceval_opcodes_basic.sql)**  
  - `py_call_cfunction(func_obj_id, args, kwargs_id DEFAULT NULL)` 이미 3인자.  
  - METH_O / METH_NOARGS / METH_VARARGS 에서 `kwargs_id IS NOT NULL` 이면 `TypeError` 발생.  
  - 함수 이름: `m_ml_name` → `py_unicode_object.str_value` 로 조회.  
  - `py_opcode_CALL_FUNCTION`: `py_object_call(func_obj_id, args, NULL)` 호출.  
  - **에러 메시지만** CPython과 미세 차이 가능: 현재 `'TypeError: ''%''() takes no keyword arguments'` → 결과에 함수 이름 주변 따옴표가 붙음. CPython은 `len() takes no keyword arguments` 형태(따옴표 없음).

- **정리**:  
  - “tp_call 3인자 규약 + py_call_cfunction kwargs 거절 + CALL_FUNCTION에서 NULL 전달”은 **이미 구현됨**.  
  - 기획에서 다룰 내용: **(1) 고증 보정(에러 메시지)** **(2) 검증(테스트·문서)** **(3) 향후 확장(CALL_FUNCTION_KW, METH_KEYWORDS)**.

---

## 3. Phase 1: 고증 보정 및 검증 (필수)

목표: 이미 들어간 kwargs 경로를 CPython에 맞게 다듬고, 테스트·문서로 고정.

### 3.1 에러 메시지 고증

- **규칙**: kwargs를 받지 않는 builtin에 kwargs가 전달되면  
  `TypeError: <name>() takes no keyword arguments`  
  - `<name>`은 **따옴표 없이** 함수 이름만 (예: `len`).
- **구현**  
  - `py_call_cfunction` 내부에서 `RAISE` 시  
    - 현재: `'TypeError: ''%''() takes no keyword arguments', COALESCE(func_name, 'builtin')`  
    - 변경: `'TypeError: %() takes no keyword arguments', COALESCE(func_name, 'builtin')`  
  - PL/pgSQL에서 `%` 한 개가 인자 하나를 넣는 자리이므로, 위 한 줄로 `len() takes no keyword arguments` 형태가 됨.
- **이름 조회**: 그대로 `m_ml_name`(uuid) → `py_unicode_object.str_value`. 없거나 타입 다르면 `COALESCE(func_name, 'builtin')` 사용. **tp_name / 타입 이름 분기 금지.**

### 3.2 적용 위치

- **기존 마이그레이션 수정 없음** 원칙을 유지하려면:  
  새 마이그레이션 `20260114234500_tp_call_kwargs.sql` (234000 다음, 235000 이전)에서  
  `CREATE OR REPLACE FUNCTION public.py_call_cfunction(...)` 만 수행하고,  
  위 에러 메시지 한 줄만 수정.
- 또는 **기존 233000 파일을 직접 수정**하는 정책이면, 해당 파일 내 `RAISE EXCEPTION` 한 군데만 위 형식으로 교체.

### 3.3 테스트

- **기존**: Phase 14/15/16 등 CALL_FUNCTION·builtin 호출은 모두 kwargs 없음 → 그대로 통과해야 함.
- **추가** (권장):  
  - `py_object_call(builtin_func_id, args, non_null_dict_id)` 호출 시  
    `TypeError: <name>() takes no keyword arguments` 가 발생하는지 검증.  
  - `<name>`이 실제 함수 이름(len, abs 등)인지, 따옴표가 없는지까지 assertion.
- **파일**: `supabase/tests/` 에 예) `35_tp_call_kwargs_reject.sql` 추가, `run_tests.sh` 에 Phase 35로 등록.

### 3.4 문서

- **README**  
  - TODO/문서 섹션에서 “tp_call·kwargs 확장 설계 (미구현)” → “tp_call·kwargs: 3인자 규약 및 METH_O/NOARGS/VARARGS kwargs 거절 구현 완료. CALL_FUNCTION_KW는 미구현.” 등으로 한 줄 수정.
- **docs/TP_CALL_KWARGS_DESIGN.md**  
  - “tp_call로 등록되는 모든 함수는 `(obj_id UUID, args UUID[], kwargs_id UUID) RETURNS UUID` 시그니처” 규약 명시 (이미 있을 수 있음).
- **234000 또는 234500 주석**  
  - “tp_call은 (obj_id, args, kwargs_id) 3인자 규약; kwargs_id NULL이면 키워드 없음” 한 줄 명시.

### 3.5 Phase 1 체크리스트 (임시방편 금지)

- [ ] 에러 메시지가 `TypeError: <name>() takes no keyword arguments` 형태이며, 이름에 따옴표가 붙지 않음.
- [ ] 함수 이름은 `m_ml_name` → `py_unicode_object.str_value` 로만 얻음. tp_name/타입 이름 대체 금지.
- [ ] METH_O / METH_NOARGS / METH_VARARGS 에서 `kwargs_id IS NOT NULL` 이면 반드시 위 TypeError.
- [ ] 기존 CALL_FUNCTION·builtin 테스트 전부 통과.
- [ ] (선택) kwargs 전달 시 거절 테스트 추가 및 run_tests.sh 반영.
- [ ] README/설계 문서 한 줄 업데이트.

---

## 4. Phase 2: CALL_FUNCTION_KW (키워드 인자 opcode)

목표: 바이트코드에서 키워드 인자를 넘길 수 있도록, CPython의 CALL_FUNCTION_KW에 대응하는 opcode를 **한 단위**로 구현.

### 4.1 CPython 동작 요약

- **CALL_FUNCTION_KW** (opcode 번호는 버전별로 다름; Elytra에서 채택할 번호는 VM_DESIGN/ceval과 통일):  
  - operand: 위치 인자 개수 등 (버전에 따라 `arg_count | (kwarg_count << 8)` 형태 등).
  - 스택 (아래에서 위):  
    `[ ... , callable, arg1, ..., argN, kwval1, ..., kwvalM, kwname1, ..., kwnameM ]`  
    - 키워드 **값** M개 pop → 키워드 **이름**(문자열 id) M개 pop → 위치 인자 N개 pop → callable pop.
  - 키워드 이름 N개와 값 N개로 **dict 하나** 생성 후,  
    `PyObject_Call(callable, args_tuple, kwargs_dict)` 호출.

### 4.2 Elytra에서 할 일

1. **스택 순서·operand 해석**  
   - CPython 3.11 등에서 CALL_FUNCTION_KW의 operand/스택 레이아웃을 하나 정해 문서화.  
   - 예: operand = `(na << 8) | nk` (위치 개수 na, 키워드 개수 nk) 등.
2. **kwargs dict 생성**  
   - 스택에서 pop한 M개의 (이름 id, 값 id)로 빈 dict 생성 후,  
     `py_dict_set_item(dict_id, name_id, value_id)` 반복.  
   - dict는 `py_dict_object` + `py_dict_entry` 사용. 키는 반드시 str(id); 동등성은 `py_object_richcompare_eq` (이미 구현됨).
3. **호출**  
   - 위치 인자만으로 `args UUID[]` 구성.  
   - `kwargs_id := 위에서 만든 dict의 id`.  
   - `py_object_call(func_obj_id, args, kwargs_id)` 호출.
4. **py_eval_frame**  
   - 새 opcode 번호에 대해 `WHEN <opcode> THEN PERFORM public.py_opcode_CALL_FUNCTION_KW(frame_id, arg);` 추가.  
   - `py_opcode_CALL_FUNCTION_KW`는 233000 또는 별도 마이그레이션(예: 234600)에서 정의.

### 4.3 설계 원칙 (임시방편 없음)

- **키워드 이름**: 스택에서 나온 객체가 str인지 **ob_type**으로만 판별. 타입 이름 문자열 비교 금지.
- **dict 생성**: 기존 `py_dict_get_item`/`py_dict_set_item`만 사용. “키워드 전용” 특수 구조 금지.
- **인자 개수**: operand와 스택에서 pop하는 개수가 일치하지 않으면 명시적 예외 (스택 언더플로 등).

### 4.4 테스트

- 키워드만: `f(a=1)` → kwargs dict `{'a': 1}` 로 전달되는지.
- 위치+키워드: `f(1, b=2)` → args `[1]`, kwargs `{'b': 2}`.
- kwargs를 받지 않는 builtin에 CALL_FUNCTION_KW로 호출 시 → Phase 1과 동일한 `TypeError: ...() takes no keyword arguments`.

### 4.5 Phase 2 체크리스트

- [ ] CALL_FUNCTION_KW opcode 번호·operand·스택 레이아웃 문서화.
- [ ] `py_opcode_CALL_FUNCTION_KW(frame_id, arg)` 구현 (스택 pop 순서, dict 생성, py_object_call(..., kwargs_id)).
- [ ] py_eval_frame에 해당 opcode 분기 추가.
- [ ] 키워드 이름은 ob_type으로 str 여부만 확인. tp_name 분기 금지.
- [ ] 테스트 추가 및 run_tests.sh 반영.

---

## 5. Phase 3: METH_KEYWORDS (선택·향후)

목표: 키워드 인자를 받는 builtin을 하나 추가할 때, `kwargs_id`를 `ml_meth`까지 넘기는 경로를 열어 두는 것.

### 5.1 원칙

- **tp_call 규약 유지**: 모든 tp_call 구현은 계속 `(obj_id, args, kwargs_id) RETURNS UUID`.  
  - METH_KEYWORDS인 경우 `kwargs_id`를 그대로 `py_call_cfunction` → `ml_meth(..., kwargs_id)` 로 전달.
- **ml_meth 시그니처**:  
  - METH_KEYWORDS용으로 등록되는 PostgreSQL 함수는 `(func_obj_id UUID, args UUID[], kwargs_id UUID) RETURNS UUID` (기존과 동일).  
  - 내부에서 `kwargs_id`로 dict를 열어 키/값을 사용.
- **기존 builtin**: len, abs 등은 시그니처 변경 없음. `py_call_cfunction`에서 METH_O/NOARGS/VARARGS만 kwargs 거절하면 됨.

### 5.2 적용 시점

- 실제로 키워드 인자를 받는 builtin(예: `open`, `dict` 생성자 등)을 추가할 때,  
  - 해당 builtin의 `m_ml_flags`에 METH_KEYWORDS 설정,  
  - `m_ml_meth`를 3인자 시그니처를 받는 함수로 등록,  
  - `py_call_cfunction`의 METH_KEYWORDS 분기에서 `ml_meth(func_obj_id, args, kwargs_id)` 호출.

### 5.3 Phase 3 체크리스트 (미구현이어도 설계만 명확히)

- [ ] tp_call 규약은 그대로 3인자; METH_KEYWORDS일 때만 kwargs_id를 ml_meth에 전달.
- [ ] 새 builtin 추가 시에만 METH_KEYWORDS + 3인자 ml_meth 사용. 기존 len/abs 등은 변경 없음.

---

## 6. 의존관계 및 우선순위

작업 간 선행 관계를 정리한 뒤, 그에 따른 **우선순위 순서**를 둔다.

### 6.1 작업 목록 (식별자)

| ID | 작업 | 산출물 |
|----|------|--------|
| **A** | 에러 메시지 고증 | 234500 migration에서 `py_call_cfunction` RAISE 문 수정 |
| **B** | kwargs 거절 테스트 | `35_tp_call_kwargs_reject.sql`, run_tests.sh Phase 35 |
| **C** | Phase 1 문서 정리 | README, TP_CALL_KWARGS_DESIGN, 234500 주석 |
| **D** | CALL_FUNCTION_KW opcode 구현 | py_opcode_CALL_FUNCTION_KW, eval_frame 분기, operand/스택 문서화 |
| **E** | CALL_FUNCTION_KW 테스트 | 테스트 파일 + run_tests.sh |
| **F** | METH_KEYWORDS 분기 | py_call_cfunction에서 METH_KEYWORDS일 때 ml_meth(..., kwargs_id) 호출 |
| **G** | METH_KEYWORDS 사용 builtin 추가 | (선택) 키워드 받는 builtin 하나 등록 |

### 6.2 의존관계

```
선행 없음:  A, C
A → B       (테스트 B는 수정된 에러 메시지를 검증하므로 A 적용 후)
A,C → (Phase 1 완료)
Phase 1 완료 → D   (Phase 1 검증·문서 정리 후 CALL_FUNCTION_KW 진행 권장)
D → E             (opcode 구현 후 해당 opcode 테스트)
D → F             (바이트코드로 키워드 호출을 하려면 D 필요; F는 D 없이 구현 가능하나 검증은 D 후)
F → G             (METH_KEYWORDS 분기 후 해당 규약을 쓰는 builtin 추가)
```

- **A**: 다른 작업에 의존하지 않음. 가장 먼저 적용 가능.
- **B**: A가 적용된 뒤에야 “정확한 에러 메시지” assertion이 통과함. **A → B**.
- **C**: 구현 상태를 반영하는 문서이므로 A 적용 후 정리하는 것이 자연스러움. 엄밀한 선행은 없음.
- **D**: `py_object_call(..., kwargs_id)`·dict 생성은 이미 있음. Phase 1(A,B,C) 완료 후 진행하면 순서가 명확함. **Phase 1 → D**.
- **E**: D(opcode 구현)가 있어야 테스트 가능. **D → E**.
- **F**: 3인자 규약은 이미 있음. D 없이 F만 구현 가능하지만, 바이트코드로 키워드 호출을 검증하려면 D가 선행. **D → F** (검증 관점).
- **G**: METH_KEYWORDS 분기(F)가 있어야 해당 규약을 쓰는 builtin을 붙일 수 있음. **F → G**.

### 6.3 우선순위 순서 (작업 시 권장 순서)

| 순위 | 작업 | 선행 작업 | 비고 |
|------|------|-----------|------|
| **1** | **A** 에러 메시지 고증 | 없음 | 234500에서 `py_call_cfunction` 한 군데만 수정 |
| **2** | **B** kwargs 거절 테스트 | A | 테스트가 A의 메시지 형식을 검증 |
| **3** | **C** Phase 1 문서 정리 | A (권장) | README/설계/주석 한 줄 정리 |
| **4** | **D** CALL_FUNCTION_KW 구현 | A,B,C (Phase 1 완료 권장) | opcode·eval_frame·문서화 |
| **5** | **E** CALL_FUNCTION_KW 테스트 | D | run_tests.sh Phase 36 등 |
| **6** | **F** METH_KEYWORDS 분기 | D (바이트코드 검증 시) | py_call_cfunction 분기만 추가해도 됨 |
| **7** | **G** METH_KEYWORDS builtin 추가 | F | 필요 시 한 builtin부터 |

### 6.4 요약: 단계별 진행 순서

| 단계 | 내용 | 산출물 |
|------|------|--------|
| **1** | 에러 메시지 고증 + kwargs 거절 테스트 + 문서 정리 | 234500 migration 또는 233000 수정, 35_tp_call_kwargs_reject.sql, README/설계 한 줄 |
| **2** | CALL_FUNCTION_KW opcode: 스택→kwargs dict→py_object_call(..., kwargs_id) | 234600 등 새 migration, py_opcode_CALL_FUNCTION_KW, eval_frame 분기, 테스트 |
| **3** | METH_KEYWORDS 지원 (키워드 받는 builtin 추가 시) | py_call_cfunction 분기 확장, ml_meth 3인자 등록 |

**임시방편 금지**  
- 함수 이름: `m_ml_name` → str_value 만 사용.  
- 타입/호출 규약: tp_call은 항상 3인자, kwargs_id NULL 가능.  
- dict/동등성: 기존 py_dict_*·tp_richcompare_eq 만 사용.  
- 특례/하드코딩/타입 이름 문자열 분기 없이, 위 단계만으로 CPython과 동일한 의미를 유지한다.
