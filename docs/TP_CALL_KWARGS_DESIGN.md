# tp_call kwargs 추가 설계

CPython의 `PyObject_Call(callable, args, kwargs)` / `ternaryfunc tp_call(obj, args, kwargs)`에 맞추어, Elytra에서도 tp_call 경로로 kwargs를 전달하는 방법을 정리한다.

**구체적인 실행 계획(마이그레이션·순서·체크리스트)** 은 **`docs/CHANGE_3_TP_CALL_KWARGS_PLAN.md`** 를 따른다.

---

## 1. CPython 쪽 정리

- **PyObject_Call**(obj, args, kwargs): args는 tuple, kwargs는 dict 또는 NULL.
- **tp_call** 시그니처: `PyObject *(*ternaryfunc)(PyObject *callable, PyObject *args, PyObject *kwargs)`  
  → 세 인자 모두 받음.
- **CALL_FUNCTION** (위치 인자만): kwargs는 NULL로 호출.
- **CALL_FUNCTION_KW** 등: 스택에서 키워드 이름·값을 모아 kwargs dict를 만든 뒤, PyObject_Call(obj, args, kwargs) 호출.

---

## 2. Elytra에서 넣을 것 (단계별)

### 2.1 호출 API: py_object_call에 kwargs 인자 추가

- **시그니처 확장**  
  - 현재: `py_object_call(obj_id UUID, args UUID[])`  
  - 변경: `py_object_call(obj_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)`  
  - `kwargs_id`: kwargs dict 객체의 `py_object.id`. NULL이면 “키워드 인자 없음”.

- **tp_call 호출 규약**  
  - “tp_call로 등록되는 함수”는 모두 **동일 시그니처**를 가져야 함.  
  - CPython과 맞추려면: `(obj_id UUID, args UUID[], kwargs_id UUID) RETURNS UUID`.  
  - `py_object_call` 내부에서는  
    `EXECUTE format('SELECT %I($1, $2, $3)', call_func) USING obj_id, args, COALESCE(kwargs_id, NULL)`  
    로 **항상 인자 3개**를 넘김.

- **변경 파일**  
  - `234000_tp_call_slot.sql`를 수정하는 새 마이그레이션에서  
    - `py_object_call(obj_id, args, kwargs_id)` 정의로 교체하고,  
    - tp_call 호출부를 위 3인자 호출로 통일.

---

### 2.2 tp_call 구현체: py_call_cfunction가 kwargs 받기

- **시그니처**  
  - `py_call_cfunction(func_obj_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL) RETURNS UUID`  
  - 이렇게 바꿔야, regproc로 등록된 tp_call과 “(obj_id, args, kwargs_id) 세 개 인자” 규약이 맞음.

- **의미**  
  - `kwargs_id`가 NULL이면 “키워드 인자 없음”.  
  - NULL이 아니면 “kwargs dict 객체 하나”라고 해석.

- **METH_O / METH_NOARGS / METH_VARARGS**  
  - 지금처럼 위치 인자만 넘기는 경우:  
    - `kwargs_id IS NOT NULL`이면  
      `TypeError: ...() takes no keyword arguments` (또는 CPython에 가깝게) 로 처리.  
  - 호출 시에는 기존처럼 `ml_meth`에 넘기는 인자는 (obj_id) 또는 (obj_id, args) 등만 유지해도 됨.  
    즉, **내부 구현(예: py_builtin_len) 시그니처는 그대로 두고**, kwargs 존재 여부만 여기서 검사.

- **METH_KEYWORDS (0x0002)**  
  - 나중에 키워드 받는 builtin을 넣을 때:  
    - `kwargs_id`를 그대로 `ml_meth(...)` 쪽으로 넘길 수 있도록,  
    - `ml_meth`가 `(obj_id, args, kwargs_id)` 형태를 받을 수 있게 확장하면 됨.  
  - 현재는 “kwargs_id 받기만 하고, METH_KEYWORDS인 경우 나중에 구현”으로 둬도 됨.

- **변경 위치**  
  - `py_call_cfunction` 정의가 있는 마이그레이션(233000 등)을 “같은 파일을 수정하는” 새 마이그레이션에서  
    - 시그니처를 `(func_obj_id, args, kwargs_id)`로 바꾸고,  
    - METH_O/METH_NOARGS일 때 `kwargs_id IS NOT NULL`이면 TypeError 처리.

---

### 2.3 호출부: CALL_FUNCTION 등에서 kwargs 넘기기

- **CALL_FUNCTION (위치만)**  
  - 지금: `py_object_call(func_obj_id, args)`  
  - 변경: `py_object_call(func_obj_id, args, NULL)`  
  - 의미는 “항상 kwargs 없이 호출”로 유지.

- **CALL_FUNCTION_KW (키워드 포함)**  
  - CPython에는 **CALL_FUNCTION_KW** 등이 있음.  
  - Elytra에서 추가할 때 흐름은 예를 들어:  
    1. operand에 “위치 개수 / 키워드 개수” 정보가 있음.  
    2. 스택에서:  
       - 키워드 값 N개 pop,  
       - 키워드 이름 N개(문자열 id) pop,  
       - 위치 인자 M개 pop,  
       - 호출 대상 pop.  
    3. 이름 N개와 값 N개로 `py_dict_set_item` 등을 써서 dict 하나 만들고, 그 id를 `kwargs_id`로 둠.  
    4. `py_object_call(func_obj_id, args_positional, kwargs_id)` 호출.

- **바이트코드**  
  - Py 3.11 이전: CALL_FUNCTION의 operand가 `arg_count | (kwarg_count << 8)` 형태인 경우가 있음.  
  - “kwargs를 쓰는 opcode”를 실제로 지원할 때는, 그에 맞는 하나의 opcode(또는 피연산자 해석)를 정한 뒤, 위 2.3의 “스택 → kwargs dict → py_object_call(..., kwargs_id)”만 구현하면 됨.

---

## 3. 구현 순서 제안

1. **py_object_call 시그니처 + tp_call 3인자 규약**  
   - `py_object_call(obj_id, args, kwargs_id DEFAULT NULL)`  
   - tp_call 호출 시 `(obj_id, args, kwargs_id)` 세 인자로 통일.

2. **py_call_cfunction 시그니처 확장**  
   - `(func_obj_id, args, kwargs_id DEFAULT NULL)`  
   - METH_O/METH_NOARGS(및 현재 지원하는 나머지)에서 `kwargs_id IS NOT NULL`이면 TypeError.

3. **CALL_FUNCTION 수정**  
   - `py_object_call(func_obj_id, args)` → `py_object_call(func_obj_id, args, NULL)` 로만 바꿔서, 새 시그니처에 맞춤.  
   - 동작은 “항상 kwargs 없음”으로 동일.

4. **(선택) CALL_FUNCTION_KW 또는 kwargs 사용 opcode**  
   - 스택에서 키워드 이름·값을 모아 dict 생성 → `py_object_call(..., kwargs_id)`  
   - 이건 “kwargs를 실제로 쓰는 바이트코드”를 도입할 때 하면 됨.

---

## 4. 스키마·호환

- **tp_call 컬럼**  
  - 그대로 `regproc`.  
  - **규약**: tp_call에 등록되는 모든 함수는 `(obj_id UUID, args UUID[], kwargs_id UUID) RETURNS UUID` 시그니처를 가진다. `kwargs_id = NULL`이면 키워드 인자 없음. (234500부터 적용.)
- **기존 builtin**  
  - len, abs 등은 모두 METH_O 등이라 kwargs를 받지 않음.  
  - `py_call_cfunction`에서 kwargs_id만 검사하고, 있을 때만 TypeError 내면 되므로,  
    `py_builtin_len` / `py_builtin_abs` 시그니처는 변경 없음.

---

## 5. 정리

- **최소한으로 “kwargs를 붙이려면”**  
  - **2.1** + **2.2** + **2.3의 CALL_FUNCTION만 NULL 넘기기** 까지 하면,  
    “tp_call이 (obj, args, kwargs) 3인자를 받는 구조”로 맞추고,  
    현재 로직은 모두 “kwargs = 없음”으로 동작하게 할 수 있다.  
- **실제로 kwargs를 쓰려면**  
  - **2.3의 CALL_FUNCTION_KW**(또는 유사 opcode) 에서 스택 → kwargs dict → `py_object_call(..., kwargs_id)` 를 구현하면 된다.
