# tp_call kwargs 추가 — 실행 계획

CPython의 `PyObject_Call(obj, args, kwargs)` / `tp_call(callable, args, kwargs)` 고증에 맞추기 위한 **구체적인 실행 계획**이다.  
설계 배경은 `docs/TP_CALL_KWARGS_DESIGN.md` 참고.

---

## 1. 목표

- **tp_call 규약**: 모든 tp_call 구현은 `(obj_id UUID, args UUID[], kwargs_id UUID) RETURNS UUID` 시그니처를 갖는다. `kwargs_id = NULL`이면 키워드 인자 없음.
- **py_object_call**: 세 번째 인자 `kwargs_id DEFAULT NULL` 추가 후, tp_call을 **항상 인자 3개**로 호출.
- **py_call_cfunction**: 같은 시그니처로 바꾸고, METH_O/METH_NOARGS(및 미구현 METH_VARARGS)에서 `kwargs_id IS NOT NULL`이면 `TypeError: ...() takes no keyword arguments` 발생.
- **CALL_FUNCTION**: `py_object_call(func_obj_id, args, NULL)`로 호출해, “항상 kwargs 없음”을 명시.
- **기존 builtin**(len, abs 등) 시그니처는 변경하지 않음. kwargs 검사·에러만 `py_call_cfunction` 안에서 처리.

---

## 2. 마이그레이션 배치

| 항목 | 내용 |
|------|------|
| 파일명 | `supabase/migrations/20260114234500_tp_call_kwargs.sql` |
| 위치 | 234000(tp_call_slot) 다음, 235000(tp_hash_slot) 이전 |
| 수정 방식 | 기존 233000·234000 파일은 건드리지 않고, 새 마이그레이션에서 `CREATE OR REPLACE`만 수행 |

---

## 3. 적용 순서 (같은 마이그레이션 내)

반드시 아래 순서로 적용한다. tp_call이 가리키는 `py_call_cfunction`이 먼저 3인자 시그니처를 가져야, 이어서 바뀐 `py_object_call`이 3인자로 호출할 수 있다.

### 3.1 py_call_cfunction 시그니처·kwargs 검사

**함수**: `public.py_call_cfunction`

- **시그니처**
  - 기존: `(func_obj_id UUID, args UUID[])`
  - 변경: `(func_obj_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)`

- **본문 맨 앞에 추가** (타입·메타 조회 직후)
  - `kwargs_id IS NOT NULL` 이고  
    `(ml_flags & 8) != 0` (METH_O) 또는 `(ml_flags & 4) != 0` (METH_NOARGS) 이면  
    → `TypeError: 'name'() takes no keyword arguments`  
  - `name`은 `m_ml_name`(uuid) → `py_unicode_object.str_value` 로 조회. 없으면 `'builtin'` 등으로 대체.
  - METH_VARARGS(`ml_flags & 1`) 구간 직전에, `kwargs_id IS NOT NULL`이면 동일한 `TypeError` (또는 “METH_VARARGS不支持keyword” 등, 정책에 따라 한 가지로 통일).

- **나머지 로직**
  - METH_O / METH_NOARGS / METH_VARARGS 분기와 `ml_meth` 호출 방식은 그대로 두고, 시그니처와 kwargs 검사만 위와 같이 넣는다.

### 3.2 py_object_call 시그니처·tp_call 3인자 호출

**함수**: `public.py_object_call`

- **시그니처**
  - 기존: `(obj_id UUID, args UUID[])`
  - 변경: `(obj_id UUID, args UUID[], kwargs_id UUID DEFAULT NULL)`

- **tp_call 호출부**
  - 기존: `EXECUTE format('SELECT %I($1, $2)', call_func::text) USING obj_id, args INTO result_id;`
  - 변경: `EXECUTE format('SELECT %I($1, $2, $3)', call_func::text) USING obj_id, args, COALESCE(kwargs_id, NULL) INTO result_id;`  
    (의도: 항상 인자 3개로 호출. `kwargs_id`가 NULL이면 NULL을 넘김.)

- **나머지**
  - 객체·타입 검사, tp_call NULL 검사, TypeError 메시지 등은 기존과 동일.

### 3.3 py_opcode_CALL_FUNCTION 호출부

**함수**: `public.py_opcode_CALL_FUNCTION` (233000에서 정의, 여기서는 교체만)

- **호출 한 줄**
  - 기존: `result_id := public.py_object_call(func_obj_id, args);`
  - 변경: `result_id := public.py_object_call(func_obj_id, args, NULL);`

- **나머지**
  - 인자 pop 순서, 함수 pop, 결과 push 등은 변경하지 않는다.

---

## 4. CPython 대응·에러 메시지

- **에러 문구**  
  - `TypeError: '%s() takes no keyword arguments'` 형식 사용.  
  - `%s` 자리에는 `m_ml_name`으로 얻은 함수 이름(문자열)을 넣는다.

- **이름 조회**  
  - `py_cfunction_object.m_ml_name` → `py_unicode_object.str_value`  
  - 해당 타입이 아니거나 없으면 `'builtin'` 등 고정 문자열 사용.

---

## 5. 규약 문서화

- **docs/TP_CALL_KWARGS_DESIGN.md**  
  - “tp_call로 등록되는 모든 함수는 `(obj_id UUID, args UUID[], kwargs_id UUID) RETURNS UUID` 시그니처를 가진다”는 규약을 **문서에 명시**해 둔다.
- **234000 주석**  
  - (선택) `tp_call_slot.sql`를 읽을 수 있는 주석이나, 새 마이그레이션 상단 주석에서 “tp_call은 234500부터 (obj, args, kwargs_id) 3인자 규약”이라고 한 줄 적어 두면 좋다.

---

## 6. 테스트

- **기존 테스트**  
  - Phase 14 (CALL_FUNCTION), Phase 15 (CALL_FUNCTION 통합, Phase 16 (abs) 등)이 **kwargs 없이** 호출하므로 그대로 통과해야 한다.
- **추가 검증(선택)**  
  - “kwargs를 넣었을 때 거절”만 검증하고 싶다면, `py_object_call(func_id, args, some_dict_id)` 호출 시 `TypeError: ...() takes no keyword arguments`가 나는지 한 번만 확인하는 케이스를 `supabase/tests/` 에 넣을 수 있다.  
  - 이 단계에서는 기존 21개 테스트가 모두 통과하는지만 확인해도 된다.

---

## 7. 체크리스트 (임시방편 금지)

- [ ] `py_call_cfunction` 시그니처가 `(func_obj_id, args, kwargs_id DEFAULT NULL)` 이다.
- [ ] METH_O / METH_NOARGS(및 검사하는 다른 컨벤션)에서 `kwargs_id IS NOT NULL`이면 **반드시** `TypeError: 'name'() takes no keyword arguments` 를 낸다.
- [ ] 함수 이름은 `m_ml_name` → `py_unicode_object.str_value` 로만 얻고, `tp_name` 등 타입 이름으로 대체하지 않는다.
- [ ] `py_object_call`은 tp_call을 **항상** `(obj_id, args, kwargs_id)` 세 인자로 호출한다.
- [ ] `py_opcode_CALL_FUNCTION`은 `py_object_call(func_obj_id, args, NULL)` 만 호출한다.
- [ ] len/abs 등 builtin 구현 함수의 시그니처는 변경하지 않는다.

---

## 8. 이후 확장 (이번 마이그레이션 범위 아님)

- **METH_KEYWORDS**  
  - `kwargs_id`를 받아서 `ml_meth`에 넘기는 경로를 나중에 추가할 때, 위 3인자 규약을 그대로 쓰면 된다.
- **CALL_FUNCTION_KW**  
  - 스택에서 키워드 이름·값을 모아 dict를 만든 뒤, `py_object_call(func_obj_id, args, kwargs_dict_id)` 로 넘기는 opcode를 별도 마이그레이션에서 추가하면 된다.

이 문서가 “CPython 고증에 맞게 tp_call에 kwargs를 붙이는 구체적인 실행 계획” 역할을 한다.
