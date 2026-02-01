# 마이그레이션 = CPython 코드 관점 정리

마이그레이션을 "DB 스키마 변경 이력"이 아니라 **CPython과 같은 코드**로 보는 관점에서 현재 구조를 정리한 문서다.

---

## 1. CPython 쪽 대응 구조 (참고)

| CPython | 역할 |
|--------|------|
| **Objects/** | 객체 모델: `PyObject`, `PyTypeObject`, 타입별 구조체, 슬롯 구현 (`tp_hash`, `tp_richcompare`, `nb_add` 등) |
| **Python/ceval.c** | 메인 인터프리터 루프 + opcode별 `switch` 분기 |
| **Include/cpython/object.h** | `PyTypeObject` 정의, 슬롯 타입 (`hashfunc`, `richcmpfunc` 등) |

즉, "객체/타입/슬롯"과 "바이트코드 실행 루프 + opcode 처리"가 레이어로 나뉜다.

---

## 2. 현재 마이그레이션을 CPython 코드처럼 매핑

파일명은 `supabase/migrations/` 기준 (접두사 `20260114` 생략 시 5자리로 부르는 경우도 있음).

### 2.1 앱 스키마

| 마이그레이션 | 역할 |
|--------------|------|
| `20260112141514_app_schema` | 사용자·워크스페이스·RLS 등 애플리케이션 인프라 |

### 2.2 객체 모델 (Objects/에 대응)

| 마이그레이션 | CPython 관점에서의 역할 |
|--------------|-------------------------|
| `20260114220000_python_object_schema` | `PyObject`, `PyTypeObject`, `py_dict_entry`, method 슬롯 테이블 등 **구조체 정의** |
| `20260114223000_python_bootstrap` | 내장 타입/객체 **인스턴스 생성** (object, type, str, int, list, dict, tuple, None, ...) |
| `20260114224000_function_object_schema` | `PyFunctionObject`, `PyCodeObject`, `PyFrameObject` **구조체** |
| `20260114224100_exception_schema` | `py_exception_state`, `py_traceback_object` 등 **예외 스키마** (builtin/슬롯에서 사용) |
| `20260114224200_exception_helpers` | `py_err_occurred`, `py_err_set_*` 등 **예외 헬퍼** |
| `20260114224300_exception_setters` | 예외 세터 함수 (builtin/슬롯에서 호출) |
| `20260114225000_builtin_functions` | `len`, `abs` 등 **builtin 함수** 구현·등록 |
| `20260114226000_type_method_slots` | `PySequenceMethods`/`PyMappingMethods` **슬롯 구현·등록** (sq_length, mp_length, len) |
| `20260114234000_tp_call_slot` | `tp_call` 슬롯 + `py_object_call` |
| `20260114235000_tp_hash_slot` | `tp_hash` 슬롯 + hash 기반 dict (`py_dict_get_item`, `py_dict_set_item`) |
| `20260114235500_nb_absolute_slot` | `nb_absolute` 슬롯 + int/float 등록 |
| `20260114236000_tp_richcompare_slot` | `tp_richcompare` 슬롯 + `py_object_richcompare` |
| `20260114238000_binary_add` | `nb_add`/`sq_concat` 슬롯 + `py_object_add` + opcode 23 |
| `20260114238500_binary_subtract` | `nb_subtract` 슬롯 + `py_object_subtract` + opcode 24 |
| `20260114239000_binary_multiply` | `nb_multiply`/`sq_repeat` 슬롯 + `py_object_multiply` + opcode 20 |
| `20260114240000_compare_op` | `py_object_richcompare` reflected op + **COMPARE_OP** opcode 107 |
| `20260114240300_py_object_istrue` | **PyObject_IsTrue** (truth value for JUMP_*) |
| `20260114240400_jump_opcodes` | **JUMP_FORWARD, POP_JUMP_IF_FALSE/TRUE** opcode 핸들러 + eval_frame 분기 |
| `20260114240600_pop_top` | **POP_TOP** (opcode 1) opcode 핸들러 |

### 2.3 VM / ceval (Python/ceval.c에 대응)

| 마이그레이션 | CPython 관점에서의 역할 |
|--------------|-------------------------|
| `20260114230000_ceval_core` | 스택·프레임 유틸, **py_get_opcode_size** (Python 3.11 uniform 2-byte) |
| `20260114232000_ceval_eval_frame` | **py_eval_frame** = 메인 루프 + opcode `CASE` 전부 (LOAD_CONST, BINARY_ADD, COMPARE_OP, JUMP_*, POP_TOP, RETURN_VALUE 등) |
| `20260114233000_ceval_opcodes_basic` | **LOAD_CONST, STORE_NAME, LOAD_NAME, CALL_FUNCTION** opcode 핸들러 |
| `20260114240700_exception_schema` | `co_exceptiontable` 등 **예외 테이블 스키마** (code object 확장) |
| `20260114240800_exception_helpers` | exception table 파싱용 **헬퍼** |
| `20260114240900_exception_table_parsing` | **exception table** 파싱 (3.11 방식) |
| `20260114241000_ceval_exception_dispatch` | **py_eval_frame** 내 예외 디스패치 (had_err, unwinding, RAISE_VARARGS, RERAISE, POP_EXCEPT, PUSH_EXC_INFO, CHECK_EXC_MATCH) |
| `20260114241100_python_exception_setters` | 예외 세터 확장 (traceback 등) |

→ **py_eval_frame**과 그 안의 **CASE 전부**는 `20260114232000_ceval_eval_frame` 한 파일에 정의되며, 예외 디스패치·unwinding은 `20260114241000_ceval_exception_dispatch`에서 같은 루프를 수정해 반영한다.  
opcode **핸들러 함수**는 basic(233000) + binary_*(238000 등) + compare_op(240000) + jump(240400) + pop_top(240600)에 나뉜다.

---

## 3. 정리된 점 (이전 대비)

### 3.1 no-op 마이그레이션 제거

- ~~`238400_binary_add_phase5_eval_frame`~~ – 제거됨.
- ~~`238900_binary_subtract_phase5_eval_frame`~~ – 제거됨.
- ~~`239400_binary_multiply_phase5_eval_frame`~~ – 제거됨.
- ~~`240200_compare_op_phase3_eval_frame`~~ – 제거됨.
- ~~`240700_have_argument_uniform_2bytes`~~ – 제거됨.

### 3.2 파일명·구조 정리

- **이름**: `phase1`/`phase2` 대신 **ceval_core**, **binary_add**, **compare_op**, **jump_opcodes**, **pop_top** 등 CPython 개념 기준.
- **병합**: BINARY_ADD/SUBTRACT/MULTIPLY는 각각 슬롯·디스패치·opcode를 한 파일에 통합. COMPARE_OP는 richcompare reflected + opcode를 `240000_compare_op` 한 파일에. Jump는 PyObject_IsTrue(240300) + opcode·eval_frame 분기(240400) 두 파일로 정리.
- **함수 정의**: `py_get_opcode_size`는 `230000_ceval_core` 한 곳. `py_eval_frame`은 `232000_ceval_eval_frame` 한 곳에서만 CREATE OR REPLACE하며, opcode 추가 시 그 파일을 직접 수정.

---

## 4. "코드" 관점에서 보면

1. **객체/타입/슬롯**  
   구조체·테이블(220000, 224000), bootstrap(223000), 예외 스키마·헬퍼·세터(224100–224300), builtin(225000), type method slots(226000)  
   그 위에 **tp_call, tp_hash, tp_richcompare, nb_*, sq_*** 가 슬롯 단위·기능 단위로 한 파일씩 정리됨.

2. **VM (ceval)**  
   **메인 루프 + 전체 opcode switch** 는 `232000_ceval_eval_frame` 한 파일에 모여 있음.  
   **opcode 핸들러**는 ceval_opcodes_basic(233000) + binary_*(238000 등) + compare_op(240000) + jump_opcodes(240400) + pop_top(240600) 로 기능별로 나뉨.  
   **예외 처리**는 exception_schema(240700), exception_helpers(240800), exception_table_parsing(240900), ceval_exception_dispatch(241000), python_exception_setters(241100)에서 스키마·파싱·디스패치·세터가 순서대로 쌓임.

3. **참고 문서**  
   - [EXCEPTION_HANDLING_DESIGN.md](EXCEPTION_HANDLING_DESIGN.md): 예외 처리 설계 (CPython 3.11 고증).  
   - [DICT_LOOKUP_DESIGN.md](DICT_LOOKUP_DESIGN.md): dict lookup hash·동등성 설계.
