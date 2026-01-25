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

#### 2.1 메인 인터프리터 루프

```sql
CREATE OR REPLACE FUNCTION py_eval_frame(frame_id UUID)
RETURNS UUID AS $$
DECLARE
    code_obj_id UUID;
    co_code_id UUID;
    bytecode TEXT;  -- unicode object의 str_value
    opcode INTEGER;
    arg INTEGER;
    i INTEGER := 0;
    stack_top INTEGER;
BEGIN
    -- 1. Frame에서 code object 가져오기
    SELECT f_code INTO code_obj_id
    FROM py_frame_object
    WHERE ob_base = frame_id;
    
    -- 2. Code object에서 bytecode 가져오기
    SELECT co_code INTO co_code_id
    FROM py_code_object
    WHERE ob_base = code_obj_id;
    
    SELECT str_value INTO bytecode
    FROM py_unicode_object
    WHERE ob_base = co_code_id;
    
    -- 3. Bytecode 실행 루프
    WHILE i < length(bytecode) LOOP
        -- Opcode 읽기 (1바이트)
        opcode := ascii(substring(bytecode FROM i+1 FOR 1));
        
        -- Operand 읽기 (1바이트 또는 3바이트)
        -- TODO: opcode에 따라 operand 크기 결정
        
        -- Opcode dispatch
        CASE opcode
            WHEN 100 THEN  -- LOAD_CONST
                PERFORM py_opcode_LOAD_CONST(frame_id, arg);
            WHEN 101 THEN  -- LOAD_NAME
                PERFORM py_opcode_LOAD_NAME(frame_id, arg);
            WHEN 23 THEN   -- BINARY_ADD
                PERFORM py_opcode_BINARY_ADD(frame_id);
            -- ... 다른 opcode들
            ELSE
                RAISE EXCEPTION 'Unknown opcode: %', opcode;
        END CASE;
        
        -- f_lasti 업데이트 (byte offset)
        -- CPython의 f_lasti는 byte offset을 저장합니다 (instruction index가 아님)
        UPDATE py_frame_object
        SET f_lasti = i
        WHERE ob_base = frame_id;
        
        -- 다음 instruction으로 이동
        i := i + 2;  -- 기본적으로 2바이트 (opcode + operand)
    END LOOP;
    
    -- 4. Stack에서 최종 결과 반환
    SELECT array_length(f_valuestack, 1) INTO stack_top
    FROM py_frame_object
    WHERE ob_base = frame_id;
    
    IF stack_top IS NULL OR stack_top = 0 THEN
        RETURN NULL;  -- 또는 None 객체
    END IF;
    
    -- Stack top 반환
    SELECT f_valuestack[stack_top] INTO result_id
    FROM py_frame_object
    WHERE ob_base = frame_id;
    
    RETURN result_id;
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
2. Stack operations (push/pop) 함수
3. Bytecode 읽기 유틸리티 함수

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
- 현재: `co_code`를 unicode object로 저장
- CPython: bytes 객체
- **해결책**: unicode object의 `str_value`에 bytecode를 문자열로 저장하거나, 별도의 bytes 타입 필요

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

## 다음 단계

1. **Stack operations 함수 구현 및 테스트**
2. **LOAD_CONST opcode 구현 및 테스트**
3. **간단한 표현식 실행 테스트** (예: `1 + 2`)
4. **LOAD_NAME, STORE_NAME 구현**
5. **변수 할당 및 참조 테스트**
