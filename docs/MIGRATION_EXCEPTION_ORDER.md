# 예외 처리 마이그레이션 의존성 순서

마이그레이션을 코드 파일처럼 관리할 때, **의존하는 함수/스키마는 호출자보다 먼저 정의**되어야 한다.

## 1. 의존 관계

- **225000 (builtin_functions)**: `py_builtin_len`이 `py_object_size` 호출 후 실패 시 `py_err_occurred()`를 봐야 함 → `py_err_occurred` 필요.
- **226000 (type_method_slots)**: `py_object_size`가 unsupported type 시 `py_err_set_type_error` + RETURN NULL → `py_err_set_type_error` 필요. slot 함수들(`py_unicode_sq_length` 등)도 `py_err_set_type_error` 사용.
- **235000 (tp_hash_slot)**: `py_object_hash`가 unhashable 시 `py_err_set_type_error` + RETURN NULL, `py_dict_get_item`/`py_dict_set_item`이 `py_err_occurred()` 확인, `py_opcode_LOAD_NAME`이 name not found 시 `py_err_set_name_error` 사용 → `py_err_set_type_error`, `py_err_set_name_error`, `py_err_occurred` 필요.

따라서 **예외 스키마 + 헬퍼 + setters**는 **225000 / 226000 / 235000보다 앞**에 적용되어야 한다.

## 2. 적용 순서 (타임스탬프)

| 순서 | 마이그레이션 | 역할 |
|------|--------------|------|
| 224000 | function_object_schema | py_code_object 등 (co_exceptiontable 추가 대상) |
| **224100** | **exception_schema** | py_exception_state, py_base_exception_object, py_traceback_object, co_exceptiontable, 예외 타입 bootstrap |
| **224200** | **exception_helpers** | py_err_set_object, py_err_clear, py_err_occurred, py_err_get_raised, py_traceback_here |
| **224300** | **exception_setters** | py_str_from_text, py_tuple_from_1, py_err_set_type_error, py_err_set_name_error, py_err_set_value_error |
| 225000 | builtin_functions | py_builtin_len (py_err_occurred 사용) |
| 226000 | type_method_slots | py_object_size, slot 함수들 (py_err_set_type_error 사용) |
| ... | ... | ... |
| 235000 | tp_hash_slot | py_object_hash, py_dict_*, py_opcode_LOAD_NAME (py_err_* 사용) |

## 3. 파일 전략 (덮어쓰기 제거)

- **224100, 224200, 224300**: 예외 스키마/헬퍼/setters를 **한 번만** 정의하는 새 마이그레이션. 224000 직후, 225000 직전에 실행.
- **240700, 240800**: 원래 예외 스키마/헬퍼 내용은 224100/224200로 이동했으므로 **no-op** (주석만 또는 빈 실행)으로 두어, 이미 적용된 DB에서 마이그레이션 이력은 유지하고 중복 실행만 방지.
- **241100**: `py_str_from_text` 등 setters는 224300으로 이동. 241100에는 **py_eval_frame 재정의만** 유지 (예외 디스패치 루프는 241000 이후에만 의미 있음).
- **241200, 241300, 241400**: "재정의" 전용 마이그레이션 제거. 225000/226000/235000 **기존 파일 수정**으로 동일 동작 구현.

## 4. 기존 파일 수정 내용

- **225000**: `py_builtin_len` — `length_value := py_object_size(...)` 다음에 `IF length_value IS NULL AND py_err_occurred() THEN RETURN NULL; END IF;` 추가.
- **226000**: `py_object_size` — NoneType / no len() 경로에서 `py_err_set_type_error` + RETURN NULL. sq_length/mp_length 호출 후 `IF length_value IS NULL AND py_err_occurred() THEN RETURN NULL;` 추가.
- **235000**: `py_object_hash` — unhashable 시 `py_err_set_type_error` + RETURN NULL. `py_dict_get_item`/`py_dict_set_item` — `h := py_object_hash(...)` 다음에 `IF h IS NULL AND py_err_occurred() THEN RETURN NULL / RETURN;` 추가. `py_opcode_LOAD_NAME` — name not found 시 `py_err_set_name_error` + RETURN.

이렇게 하면 **한 번 정의하고, 호출하는 쪽에서만 수정**하는 코드 파일 스타일을 유지할 수 있다.
