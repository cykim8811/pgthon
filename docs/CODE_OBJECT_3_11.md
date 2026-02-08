# CPython 3.11 코드 객체 (Elytra)

Elytra의 `py_code_object`는 CPython 3.11 `PyCodeObject` 필드와 대응한다. 임시방편 없이 문서·스키마를 3.11 규약에 맞춘다.

---

## 1. CPython 3.11 PyCodeObject 필드 요약

| CPython 필드 | Elytra 컬럼 | 비고 |
|--------------|-------------|------|
| co_code | co_code (uuid → py_bytes_object) | 바이트코드 (wordcode, docs/BYTECODE_ENCODING_3_11.md) |
| co_consts | co_consts (uuid → py_tuple_object) | 상수 tuple |
| co_names | co_names (uuid → py_tuple_object) | 이름 tuple (str) |
| co_varnames | co_varnames (uuid → py_tuple_object) | 지역 변수 이름 tuple |
| co_filename | co_filename (uuid → py_unicode_object) | 소스 파일명 |
| co_name | co_name (uuid → py_unicode_object) | 코드/함수 이름 |
| co_argcount | co_argcount (integer) | 위치 인자 개수 |
| co_posonlyargcount | co_posonlyargcount (integer, 3.8+) | 위치 전용 인자 개수, NULL=0 |
| co_kwonlyargcount | co_kwonlyargcount (integer) | 키워드 전용 인자 개수, NULL=0 |
| co_nlocals | co_nlocals (integer) | 지역 변수 개수, NULL이면 co_varnames 길이로 유도 가능 |
| co_stacksize | co_stacksize (integer) | 평가 스택 필요 크기, NULL이면 VM이 무시 가능 |
| co_flags | co_flags (integer) | CO_OPTIMIZED, CO_NEWLOCALS 등, NULL=0 |
| co_firstlineno | co_firstlineno (integer) | 첫 소스 라인 번호, NULL=0 (traceback용) |
| co_cellvars | co_cellvars (uuid → py_tuple_object) | 셀 변수 이름 tuple |
| co_freevars | co_freevars (uuid → py_tuple_object) | 자유 변수 이름 tuple |
| co_exceptiontable | co_exceptiontable (bytea) | 3.11 예외 테이블 (docs/EXCEPTION_HANDLING_DESIGN.md) |

---

## 2. Elytra 스키마 정책

- **기본 필드:** `py_code_object` CREATE TABLE(224000)에 co_code, co_consts, co_names, co_filename, co_name, co_argcount, co_varnames, co_cellvars, co_freevars 정의.
- **3.11 확장:** co_exceptiontable 및 선택 필드(co_posonlyargcount, co_kwonlyargcount, co_nlocals, co_stacksize, co_flags, co_firstlineno)는 **기존 마이그레이션 수정**으로 추가(224100 등). 새 마이그레이션 파일 추가 없음.
- **선택 필드:** NULL 또는 0 기본값. 기존 INSERT는 해당 컬럼을 지정하지 않아도 동작한다.

---

## 3. 이후 작업과의 관계

- **바이트코드 인코딩(1단계):** co_code 해석은 docs/BYTECODE_ENCODING_3_11.md 따름.
- **예외 테이블(3단계):** co_exceptiontable 형식·위치는 docs/EXCEPTION_HANDLING_DESIGN.md 및 224400 파싱 로직 따름.
- **캐시/특수 opcode(4단계):** co_code 스트림만 사용; 코드 객체 필드 추가 없음.

이 문서는 “코드 객체에 어떤 필드가 있고, Elytra에서 어떻게 저장하는가”만 정의한다.
