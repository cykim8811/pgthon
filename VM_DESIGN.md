# Elytra VM 설계안

## 개요

Elytra VM은 CPython의 bytecode execution engine을 PostgreSQL 위에 구현합니다. CPython의 stack-based virtual machine 구조를 유지하면서, PostgreSQL의 PL/pgSQL을 사용하여 bytecode를 실행합니다.

## CPython VM 핵심 구조

### 1. Stack-Based Execution Model

CPython은 **stack-based VM**입니다:
- 모든 연산은 evaluation stack (`f_valuestack`)에서 수행됩니다
- Opcode는 stack에서 operand를 pop하고, 결과를 push합니다
- 예: `LOAD_CONST 0` → stack에 constant push, `BINARY_ADD` → stack에서 2개 pop, 더한 후 push

### 2. Frame Object의 역할

- `f_code`: 실행할 bytecode가 담긴 code object
- `f_valuestack`: 중간 계산 결과를 저장하는 stack (uuid[] 배열)
- `f_locals`: 지역 변수 dictionary
- `f_globals`: 전역 변수 dictionary
- `f_builtins`: builtin 함수 dictionary
- `f_lasti`: 마지막으로 실행한 instruction의 인덱스

### 3. Bytecode Instruction Format

CPython 3.6+ 기준:
- 각 instruction은 2바이트 (opcode 1바이트 + operand 1바이트)
- 또는 4바이트 (opcode 1바이트 + operand 3바이트, 확장 opcode)
- `co_code`는 bytes 객체로 저장 (Elytra에서는 unicode object로 저장)

## PostgreSQL 구현 설계

### 1. 아키텍처 개요

```
┌─────────────────────────────────────────┐
│  py_eval_frame(frame_id)               │  ← 메인 인터프리터 루프
│  - bytecode 읽기                        │
│  - opcode dispatch                      │
│  - stack 관리                           │
└─────────────────────────────────────────┘
           │
           ├─→ py_opcode_LOAD_CONST(frame_id, arg)
           ├─→ py_opcode_LOAD_NAME(frame_id, arg)
           ├─→ py_opcode_BINARY_ADD(frame_id)
           ├─→ py_opcode_CALL_FUNCTION(frame_id, arg)
           └─→ ... (각 opcode별 처리 함수)
```

### 2. 핵심 함수 구조

#### 2.1 메인 인터프리터 루프 (py_eval_frame)

**구현 위치**: `supabase/migrations/20260114232000_ceval_eval_frame.sql`

**CPython 대응**: `PyEval_EvalFrameEx` / `_PyEval_EvalFrameDefault`

```sql
CREATE OR REPLACE FUNCTION py_eval_frame(frame_id UUID)
RETURNS UUID AS $$
DECLARE
    code_obj_id UUID;
    co_code_id UUID;
    bytecode bytea;  -- bytes object의 bytes_value
    opcode INTEGER;
    arg INTEGER;
    i INTEGER := 0;
    instruction_size INTEGER;
    return_value UUID := NULL;
    should_return BOOLEAN := FALSE;
    bytecode_length INTEGER;
BEGIN
    -- 1. Frame에서 code object 가져오기
    SELECT f_code INTO code_obj_id
    FROM py_frame_object
    WHERE ob_base = frame_id;
    
    IF code_obj_id IS NULL THEN
        RAISE EXCEPTION 'Frame with id % does not have a code object', frame_id;
    END IF;
    
    -- 2. Code object에서 bytecode 가져오기
    SELECT co_code INTO co_code_id
    FROM py_code_object
    WHERE ob_base = code_obj_id;
    
    IF co_code_id IS NULL THEN
        RAISE EXCEPTION 'Code object with id % does not have co_code', code_obj_id;
    END IF;
    
    SELECT bytes_value INTO bytecode
    FROM py_bytes_object
    WHERE ob_base = co_code_id;
    
    IF bytecode IS NULL THEN
        RAISE EXCEPTION 'Bytes object with id % does not have bytes_value', co_code_id;
    END IF;
    
    bytecode_length := length(bytecode);
    
    -- 3. Bytecode 실행 루프
    -- CPython의 PyEval_EvalFrameEx와 동일하게, RETURN_VALUE opcode에서만 반환하고 루프 종료
    WHILE i < bytecode_length LOOP
        -- Opcode 읽기 (1바이트)
        opcode := get_byte(bytecode, i);  -- get_byte uses 0-based indexing
        
        -- Operand 읽기 (1바이트, 나중에 EXTENDED_ARG 지원 시 확장 가능)
        arg := get_byte(bytecode, i + 1);
        
        -- Opcode dispatch
        CASE opcode
            WHEN 100 THEN  -- LOAD_CONST
                PERFORM py_opcode_LOAD_CONST(frame_id, arg);
            WHEN 101 THEN  -- LOAD_NAME
                PERFORM py_opcode_LOAD_NAME(frame_id, arg);
            WHEN 23 THEN   -- BINARY_ADD
                PERFORM py_opcode_BINARY_ADD(frame_id);
            WHEN 83 THEN   -- RETURN_VALUE
                -- CPython: PyEval_EvalFrameEx returns the value on top of the stack
                -- when RETURN_VALUE opcode is executed
                return_value := py_stack_pop(frame_id);
                should_return := TRUE;
                -- f_lasti 업데이트 (RETURN_VALUE instruction의 byte offset)
                UPDATE py_frame_object
                SET f_lasti = i
                WHERE ob_base = frame_id;
                EXIT;  -- 루프 종료 (CPython과 동일)
            -- ... 다른 opcode들
            ELSE
                RAISE EXCEPTION 'Unknown opcode: % at byte offset %', opcode, i;
        END CASE;
        
        -- f_lasti 업데이트 (byte offset)
        -- CPython의 f_lasti는 byte offset을 저장합니다 (instruction index가 아님)
        -- RETURN_VALUE의 경우 위에서 이미 업데이트했으므로 여기서는 건너뜀
        IF opcode != 83 THEN
            UPDATE py_frame_object
            SET f_lasti = i
            WHERE ob_base = frame_id;
        END IF;
        
        -- 다음 instruction으로 이동
        instruction_size := py_get_opcode_size(opcode);
        i := i + instruction_size;
    END LOOP;
    
    -- 4. 반환값 처리
    -- CPython: PyEval_EvalFrameEx returns the value popped by RETURN_VALUE,
    -- or NULL if no RETURN_VALUE was executed (rare, usually indicates error)
    IF should_return THEN
        RETURN return_value;
    ELSE
        -- 모든 bytecode 실행 완료 (일반적이지 않음, 보통 RETURN_VALUE가 있어야 함)
        -- CPython에서는 이런 경우 NULL을 반환하거나 예외가 발생함
        RETURN NULL;  -- 또는 None 객체 (나중에 None 객체 구현 시 변경)
    END IF;
END;
$$ LANGUAGE plpgsql;
```

#### 2.2 Stack Operations

```sql
-- Stack push
CREATE OR REPLACE FUNCTION py_stack_push(frame_id UUID, obj_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE py_frame_object
    SET f_valuestack = array_append(f_valuestack, obj_id)
    WHERE ob_base = frame_id;
END;
$$ LANGUAGE plpgsql;

-- Stack pop
CREATE OR REPLACE FUNCTION py_stack_pop(frame_id UUID)
RETURNS UUID AS $$
DECLARE
    stack_top INTEGER;
    result_id UUID;
BEGIN
    SELECT array_length(f_valuestack, 1) INTO stack_top
    FROM py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_top IS NULL OR stack_top = 0 THEN
        RAISE EXCEPTION 'Stack underflow';
    END IF;
    
    SELECT f_valuestack[stack_top] INTO result_id
    FROM py_frame_object
    WHERE ob_base = frame_id;
    
    UPDATE py_frame_object
    SET f_valuestack = f_valuestack[1:stack_top-1]
    WHERE ob_base = frame_id;
    
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;
```

#### 2.3 Opcode 구현 예시

```sql
-- LOAD_CONST: co_consts[index]를 stack에 push
CREATE OR REPLACE FUNCTION py_opcode_LOAD_CONST(frame_id UUID, const_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_consts_id UUID;
    const_obj_id UUID;
BEGIN
    -- Code object 가져오기
    SELECT f_code INTO code_obj_id
    FROM py_frame_object
    WHERE ob_base = frame_id;
    
    -- co_consts tuple 가져오기
    SELECT co_consts INTO co_consts_id
    FROM py_code_object
    WHERE ob_base = code_obj_id;
    
    -- Tuple에서 index번째 요소 가져오기
    SELECT ob_item[const_index + 1] INTO const_obj_id  -- PostgreSQL 배열은 1-based
    FROM py_tuple_object
    WHERE ob_base = co_consts_id;
    
    -- Stack에 push
    PERFORM py_stack_push(frame_id, const_obj_id);
END;
$$ LANGUAGE plpgsql;

-- BINARY_ADD: stack에서 2개 pop, 더하기, push
CREATE OR REPLACE FUNCTION py_opcode_BINARY_ADD(frame_id UUID)
RETURNS VOID AS $$
DECLARE
    right_id UUID;
    left_id UUID;
    left_type_id UUID;
    right_type_id UUID;
    left_type_name TEXT;
    right_type_name TEXT;
    result_id UUID;
BEGIN
    -- Stack에서 pop (right, left 순서)
    right_id := py_stack_pop(frame_id);
    left_id := py_stack_pop(frame_id);
    
    -- 타입 확인
    SELECT ob_type INTO left_type_id FROM py_object WHERE id = left_id;
    SELECT ob_type INTO right_type_id FROM py_object WHERE id = right_id;
    
    SELECT tp_name INTO left_type_name FROM py_type_object WHERE ob_base = left_type_id;
    SELECT tp_name INTO right_type_name FROM py_type_object WHERE ob_base = right_type_id;
    
    -- 타입별 덧셈 처리
    IF left_type_name = 'int' AND right_type_name = 'int' THEN
        -- int + int
        result_id := py_binary_add_int(left_id, right_id);
    ELSIF left_type_name = 'str' AND right_type_name = 'str' THEN
        -- str + str (concatenation)
        result_id := py_binary_add_str(left_id, right_id);
    ELSE
        RAISE EXCEPTION 'TypeError: unsupported operand type(s) for +: % and %', 
            left_type_name, right_type_name;
    END IF;
    
    -- 결과를 stack에 push
    PERFORM py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;
```

#### 2.4 Namespace Lookup

```sql
-- LOAD_NAME: name을 locals → globals → builtins 순서로 찾기
CREATE OR REPLACE FUNCTION py_opcode_LOAD_NAME(frame_id UUID, name_index INTEGER)
RETURNS VOID AS $$
DECLARE
    code_obj_id UUID;
    co_names_id UUID;
    name_str_id UUID;
    name_str TEXT;
    obj_id UUID;
    f_locals_id UUID;
    f_globals_id UUID;
    f_builtins_id UUID;
BEGIN
    -- Code object에서 co_names 가져오기
    SELECT f_code INTO code_obj_id
    FROM py_frame_object
    WHERE ob_base = frame_id;
    
    SELECT co_names INTO co_names_id
    FROM py_code_object
    WHERE ob_base = code_obj_id;
    
    -- name_index번째 이름 가져오기
    SELECT ob_item[name_index + 1] INTO name_str_id
    FROM py_tuple_object
    WHERE ob_base = co_names_id;
    
    SELECT str_value INTO name_str
    FROM py_unicode_object
    WHERE ob_base = name_str_id;
    
    -- Frame에서 namespace 가져오기
    SELECT f_locals, f_globals, f_builtins
    INTO f_locals_id, f_globals_id, f_builtins_id
    FROM py_frame_object
    WHERE ob_base = frame_id;
    
    -- Lookup 순서: locals → globals → builtins
    -- 1. locals에서 찾기
    SELECT me_value INTO obj_id
    FROM py_dict_entry
    WHERE dict_id = f_locals_id
    AND me_key = name_str_id;
    
    IF obj_id IS NOT NULL THEN
        PERFORM py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;
    
    -- 2. globals에서 찾기
    SELECT me_value INTO obj_id
    FROM py_dict_entry
    WHERE dict_id = f_globals_id
    AND me_key = name_str_id;
    
    IF obj_id IS NOT NULL THEN
        PERFORM py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;
    
    -- 3. builtins에서 찾기
    SELECT me_value INTO obj_id
    FROM py_dict_entry
    WHERE dict_id = f_builtins_id
    AND me_key = name_str_id;
    
    IF obj_id IS NOT NULL THEN
        PERFORM py_stack_push(frame_id, obj_id);
        RETURN;
    END IF;
    
    -- 찾지 못함
    RAISE EXCEPTION 'NameError: name ''%'' is not defined', name_str;
END;
$$ LANGUAGE plpgsql;
```

#### 2.5 Function Call

```sql
-- CALL_FUNCTION: stack에서 함수와 인자들을 pop하고 호출
CREATE OR REPLACE FUNCTION py_opcode_CALL_FUNCTION(frame_id UUID, arg_count INTEGER)
RETURNS VOID AS $$
DECLARE
    func_obj_id UUID;
    func_type_id UUID;
    func_type_name TEXT;
    args UUID[];
    i INTEGER;
    result_id UUID;
BEGIN
    -- Stack에서 인자들 pop (역순)
    args := array[]::UUID[];
    FOR i IN 1..arg_count LOOP
        args := array_prepend(py_stack_pop(frame_id), args);
    END LOOP;
    
    -- Stack에서 함수 객체 pop
    func_obj_id := py_stack_pop(frame_id);
    
    -- 함수 타입 확인
    SELECT ob_type INTO func_type_id FROM py_object WHERE id = func_obj_id;
    SELECT tp_name INTO func_type_name FROM py_type_object WHERE ob_base = func_type_id;
    
    -- 타입별 호출 처리
    IF func_type_name = 'builtin_function_or_method' THEN
        -- C function 호출
        result_id := py_call_cfunction(func_obj_id, args);
    ELSIF func_type_name = 'function' THEN
        -- Python function 호출
        result_id := py_call_function(func_obj_id, args);
    ELSE
        RAISE EXCEPTION 'TypeError: ''%'' object is not callable', func_type_name;
    END IF;
    
    -- 결과를 stack에 push
    PERFORM py_stack_push(frame_id, result_id);
END;
$$ LANGUAGE plpgsql;

-- C function 호출 (builtin 함수)
CREATE OR REPLACE FUNCTION py_call_cfunction(func_obj_id UUID, args UUID[])
RETURNS UUID AS $$
DECLARE
    ml_meth regproc;
    result_id UUID;
BEGIN
    -- m_ml_meth 가져오기
    SELECT m_ml_meth INTO ml_meth
    FROM py_cfunction_object
    WHERE ob_base = func_obj_id;
    
    IF ml_meth IS NULL THEN
        RAISE EXCEPTION 'Function implementation not found';
    END IF;
    
    -- 동적 호출 (METH_O 방식 가정, 단일 인자)
    IF array_length(args, 1) = 1 THEN
        EXECUTE format('SELECT %I($1)', ml_meth::text) USING args[1] INTO result_id;
    ELSE
        RAISE EXCEPTION 'Unsupported argument count for C function';
    END IF;
    
    RETURN result_id;
END;
$$ LANGUAGE plpgsql;
```

## 구현 단계

### Phase 1: 기본 인프라
1. ✅ Frame object 스키마 (이미 완료)
2. ✅ Stack operations (push/pop) 함수
3. ✅ Bytecode 읽기 유틸리티 함수 (opcode size)
4. ✅ py_eval_frame 메인 인터프리터 루프

### Phase 2: 핵심 Opcode 구현
1. `LOAD_CONST`: 상수 로드
2. `LOAD_NAME`: 이름 로드 (namespace lookup)
3. `STORE_NAME`: 이름 저장
4. `BINARY_ADD`: 덧셈 연산
5. `RETURN_VALUE`: 함수 반환

### Phase 3: 함수 호출
1. `CALL_FUNCTION`: 함수 호출
2. `CALL_FUNCTION_KW`: 키워드 인자 함수 호출
3. Frame 생성 및 관리

### Phase 4: 제어 흐름
1. `POP_JUMP_IF_FALSE`: 조건부 점프
2. `JUMP_FORWARD`: 순방향 점프
3. `SETUP_LOOP`: 루프 블록 설정

### Phase 5: 예외 처리
1. Exception 객체
2. `RAISE_VARARGS`: 예외 발생
3. `SETUP_EXCEPT`: 예외 처리 블록

## 설계 원칙

### 1. CPython 고증 유지
- Opcode 번호와 의미는 CPython과 동일
- Stack-based execution model 유지
- Namespace lookup 순서 (locals → globals → builtins) 유지

### 2. 단계적 구현
- 최소 opcode 세트부터 시작 (LOAD_CONST, RETURN_VALUE)
- 간단한 표현식 실행 가능하게 만들기
- 점진적으로 opcode 추가

### 3. 테스트 우선
- 각 opcode별 단위 테스트
- Frame execution 통합 테스트
- 실제 Python 코드 컴파일 → bytecode → 실행 테스트

### 4. 확장 가능성
- 새로운 opcode 추가가 쉬운 구조
- 타입별 연산 처리 확장 가능
- Exception handling 확장 가능

## 고려사항

### 1. Bytecode 저장 형식
- ✅ 해결됨: `co_code`를 bytes object (`py_bytes_object`)로 저장
- CPython: bytes 객체 (PyBytesObject)
- PostgreSQL: `bytea` 타입 사용 (NULL 바이트 포함 가능)

### 2. Opcode 확장 (EXTENDED_ARG)
- 일부 opcode는 3바이트 operand 사용
- Opcode별로 operand 크기 다름
- **해결책**: opcode 테이블 또는 함수로 operand 크기 관리

### 3. 성능
- PL/pgSQL은 C보다 느림
- 하지만 구조적 정확성이 우선
- **해결책**: 최적화는 나중에, 먼저 정확한 구현

### 4. Exception Handling
- Frame의 block stack 필요할 수 있음
- 현재 스키마에는 없음
- **해결책**: 필요시 `f_blockstack` 추가

---

## BINARY_ADD 구현 계획 (nb_add 슬롯)

CPython 고증을 지키고, 임시방편 없이 **타입 슬롯(nb_add)** 로만 이항 덧셈을 처리하는 진행 계획이다.

### 1. CPython 쪽

- **PyNumber_Add(o1, o2)**: `o1 + o2`를 수행하는 C API. 반환: 새 참조 또는 NULL(에러).
- **nb_add**: `PyNumberMethods` 안의 `binaryfunc` 슬롯. 시그니처 `(PyObject *a, PyObject *b) -> PyObject*`.  
  - 왼쪽 타입의 nb_add(a, b) 먼저 시도 → `NotImplemented`면 오른쪽 타입의 nb_add(b, a) 시도(역방향).  
  - 둘 다 없거나 둘 다 NotImplemented면 TypeError.
- **타입별**: int는 수치 덧셈, str은 concatenation. int+str → int의 nb_add가 NotImplemented 반환 후 str의 nb_add(str, int)도 NotImplemented → TypeError.

### 2. Elytra에서 할 일(순서)

| 단계 | 내용 |
|------|------|
| 1 | **스키마** `py_type_object`에 `nb_add regproc` 추가. **지향**: `20260114220000_python_object_schema.sql`의 `create table py_type_object`를 직접 수정해 컬럼 포함. (README 규칙: 기존 스키마 생성 코드 수정.) |
| 2 | **타입별 구현** `py_long_nb_add(left_id, right_id)`, `py_unicode_nb_add(left_id, right_id)`. 각각 (left, right 모두 해당 타입일 때만) 덧셈/연결 후 새 객체 id 반환. 다른 타입이면 NotImplemented id 반환. |
| 3 | **디스패치** `py_object_add(left_id, right_id)`: left의 `ob_type` → `nb_add` 조회. NULL이면 NotImplemented. 있으면 `nb_add(left, right)` 호출. 반환값이 NotImplemented id면 `nb_add(right, left)` 한 번 더 시도. 둘 다 없거나 둘 다 NotImplemented면 `RAISE EXCEPTION 'TypeError: unsupported operand type(s) for +: ...'`. |
| 4 | **슬롯 등록** str, int의 `nb_add`에 위 타입별 함수 등록. |
| 5 | **BINARY_ADD opcode** `py_opcode_BINARY_ADD(frame_id)`: stack에서 right, left 순으로 pop → `result_id := py_object_add(left, right)` → `py_stack_push(frame_id, result_id)`. (예외는 그대로 전파.) |
| 6 | **eval_frame에 23 연결** opcode 23일 때 `PERFORM public.py_opcode_BINARY_ADD(frame_id);` 호출. `py_get_opcode_size`는 기본 2바이트로 23 포함되므로 수정 불필요. **배치**: BINARY_ADD/디스패치를 넣은 마이그레이션(예: 238000) **다음** 마이그레이션에서 `py_eval_frame`을 CREATE OR REPLACE로 수정해 `WHEN 23` 분기만 추가. (232000을 “이미 실행된 과거”로 두고, eval_frame 수정은 별도 마이그레이션에서만 수행.) |
| 7 | **테스트** nb_add 슬롯·디스패치 단위, `1+2` / `"a"+"b"` 통합, `1+"a"` → TypeError. `supabase/tests/`에 추가하고 `run_tests.sh`에 Phase로 등록. |

### 3. 배치(파일) 및 실행 순서

- **스키마**: `20260114220000_python_object_schema.sql`의 `py_type_object` 정의에 `nb_add regproc` 한 줄 추가.
- **함수·슬롯·opcode**: `20260114238000_binary_add.sql`  
  - `py_long_nb_add`, `py_unicode_nb_add`, `py_object_add` 정의, str/int에 nb_add 등록, `py_opcode_BINARY_ADD` 정의.
- **eval_frame 연결**: `20260114232000_ceval_eval_frame.sql`에서 `py_eval_frame`의 CASE에 `WHEN 23 THEN PERFORM public.py_opcode_BINARY_ADD(frame_id);` 포함 (238000과 함께 해당 파일에 반영).  
  - 스텁 없이 진행: 238000에서 이미 `py_opcode_BINARY_ADD`가 정의되므로, 그 다음에 eval_frame에서 23을 연결하면 된다. 232000 파일 자체는 수정하지 않고, “eval_frame 수정은 별도 마이그레이션에서만” 수행한다.

### 4. 임시방편 금지

- **타입 이름 분기 금지**: `py_object_add` 안에서는 `tp_name = 'int'` / `'str'`로 분기하지 않는다. left의 `nb_add` 슬롯 유무·호출 결과(NotImplemented 여부)와, 필요 시 right의 nb_add만 사용.
- **타입별 함수**: `py_long_nb_add`는 “left/right가 int인가”만 확인(예: `py_long_object` 존재 여부). `py_unicode_nb_add`는 str만. 타입 이름 문자열 비교는 쓰지 않는다.
- **NotImplemented 싱글턴**: 반환은 기존 부트스트랩의 NotImplemented 객체 id(`00000000-0000-4000-b000-000000000012`)만 사용.

### 5. 이후 확장

- float, bytes 등은 **타입별 nb_add 하나 정의 + 슬롯 등록**만 하면 되며, `py_object_add`와 BINARY_ADD는 수정하지 않는다.
- 나중에 nb_subtract, nb_multiply 등이 필요하면 동일하게 “스키마에 슬롯 추가(220000 수정 지향) + 타입별 함수 + 디스패치” 패턴으로 확장.

### 6. 진행 요약 (CPython 고증 · 비임시방편 · 깔끔한 구현)

아래 순서대로 진행하면, 임시 스텁·타입 이름 분기·우회 구현 없이 nb_add 슬롯 방식으로만 BINARY_ADD를 넣을 수 있다.

| 순서 | 작업 | 파일/위치 | 비고 |
|------|------|-----------|------|
| 1 | 스키마에 `nb_add regproc` 추가 | `20260114220000_python_object_schema.sql` 내 `create table py_type_object` | 기존 테이블 정의 직접 수정(README 규칙). tp_richcompare 다음 한 줄 추가. |
| 2 | 타입별 nb_add 구현 | `20260114238000_binary_add.sql` | `py_long_nb_add(left_id, right_id)`, `py_unicode_nb_add(left_id, right_id)`. int/str만 처리, 나머지는 NotImplemented id 반환. 타입 판별은 `py_long_object`/`py_unicode_object` 존재 여부로만. |
| 3 | 디스패치 `py_object_add` | 같은 238000 | left의 `ob_type` → `nb_add` 호출. NotImplemented면 right의 nb_add(b,a) 한 번 더. 둘 다 없거나 둘 다 NotImplemented면 `RAISE EXCEPTION 'TypeError: unsupported operand type(s) for +: ...'`. tp_name 분기 금지. |
| 4 | 슬롯 등록 | 같은 238000 | str, int의 `nb_add`에 위 타입별 함수 등록. |
| 5 | BINARY_ADD opcode | 같은 238000 | `py_opcode_BINARY_ADD(frame_id)`: right/left pop → `py_object_add(left, right)` → push. |
| 6 | eval_frame에 opcode 23 연결 | `20260114232000_ceval_eval_frame.sql` (opcode 23 분기는 238000_binary_add와 함께 해당 파일에 반영) | `py_eval_frame`만 CREATE OR REPLACE, CASE에 `WHEN 23 THEN PERFORM public.py_opcode_BINARY_ADD(frame_id);` 추가. `py_get_opcode_size`는 기본 2바이트로 23 포함되어 있으므로 변경 없음. |
| 7 | 테스트 | `supabase/tests/21_nb_add_slot.sql` (예), `run_tests.sh` | nb_add 슬롯·디스패치 단위, `1+2`/`"a"+"b"` 통합, `1+"a"` → TypeError. Phase 21 등록. |

- **CPython 고증**: PyNumber_Add / nb_add(binaryfunc) · 왼쪽 시도 → NotImplemented 시 오른쪽 역방향 · 둘 다 실패 시 TypeError.
- **비임시방편**: 스텁 함수 없음. `py_object_add` 내부에 `tp_name`/타입 문자열 분기 없음. 타입별 함수는 테이블 존재로만 판별, NotImplemented는 부트스트랩 싱글턴 id (`00000000-0000-4000-b000-000000000012`)만 사용.
- **깔끔한 확장**: 이후 float/bytes 등은 타입별 nb_add 함수 하나 + 슬롯 등록만 추가하면 되고, `py_object_add`·BINARY_ADD·eval_frame 분기는 수정하지 않는다.

---

## 다음 단계

1. **BINARY_ADD (nb_add 슬롯)**  
   위 “BINARY_ADD 구현 계획”대로 스키마 수정 → 238000에서 함수·슬롯·opcode → 다음 마이그레이션에서 eval_frame에 23 연결 → 테스트 추가.
2. **간단한 표현식 실행**  
   `1 + 2`, `"a" + "b"`가 한 프레임 실행으로 기대값이 나오는지 통합 테스트.
3. (이후) 제어 흐름 opcode, 예외 처리 등은 VM_DESIGN Phase 4·5 참고.
