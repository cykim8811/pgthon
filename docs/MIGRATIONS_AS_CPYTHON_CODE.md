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
| `20260114224400_exception_table_parsing` | **exception table** 파싱 (3.11 co_exceptiontable → start/end/target/depth/lasti) |
| `20260114225000_builtin_functions` | `len`, `abs` 등 **builtin 함수** 구현·등록 |
| `20260114226000_type_method_slots` | `PySequenceMethods`/`PyMappingMethods` **슬롯 구현·등록** (sq_length, mp_length, len) |
| `20260114234000_tp_call_slot` | `tp_call` 슬롯 + `py_object_call` |
| `20260114235000_tp_hash_slot` | `tp_hash` 슬롯 + hash 기반 dict (`py_dict_get_item`, `py_dict_set_item`) |
| `20260114235500_nb_absolute_slot` | `nb_absolute` 슬롯 + int/float 등록 |
| `20260114236000_tp_richcompare_slot` | `tp_richcompare` 슬롯 + `py_object_richcompare` |
| `20260114238000_binary_add` | `nb_add`/`sq_concat` 슬롯 + `py_object_add` |
| `20260114238500_binary_subtract` | `nb_subtract` 슬롯 + `py_object_subtract` |
| `20260114239000_binary_multiply` | `nb_multiply`/`sq_repeat` 슬롯 + `py_object_multiply` |
| `20260114240300_py_object_istrue` | **PyObject_IsTrue** (truth value for JUMP_*) |

### 2.3 VM / ceval (Python/ceval.c에 대응)

**순서**: 슬롯·지원(233000, 234000, …, 240300) → **opcode 블록 240301–240316** → 241000(예외 디스패치) → **예외 opcode 241001–241005** → 241100.

| 마이그레이션 | CPython 관점에서의 역할 |
|--------------|-------------------------|
| `20260114230000_ceval_core` | 스택·프레임 유틸, **py_get_opcode_size** |
| `20260114232000_ceval_eval_frame` | **py_eval_frame** = 메인 루프 + opcode `CASE` 전부 |
| `20260114233000_ceval_opcodes_basic` | **py_call_cfunction** (CALL_FUNCTION/CALL_FUNCTION_KW 지원만) |
| `20260114234000_tp_call_slot` | `tp_call` 슬롯 + `py_object_call` |
| `20260114235000_tp_hash_slot` | `tp_hash` 슬롯 + dict/getattr/setattr |
| … (235500, 236000, 238000, 238500, 239000, 240300: 슬롯·지원) | |
| **`20260114240301_opcode_load_const`** … **`20260114240316_opcode_pop_top`** | **opcode 블록** (100, 141, 142, 102, 103, 90, 101, 106, 95, 23, 24, 20, 107, 114, 115, 1) |
| `20260114241000_ceval_exception_dispatch` | **py_eval_frame** 예외 디스패치 루프 + py_err_restore, py_stack_trim, py_stack_peek, py_type_issubclass, py_tuple_from_3 |
| `20260114241001_opcode_raise_varargs` … `20260114241005_opcode_pop_except` | 예외 opcode (130, 119, 35, 36, 89) |
| `20260114241100_python_exception_setters` | 예외 세터 확장 (traceback 등) |

→ **opcode 핸들러**는 **파일당 1개**, **240301–240316**(일반 opcode) + **241001–241005**(예외 opcode) 두 블록으로 묶임.

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
- **계층 분리**: 슬롯/객체 마이그레이션에는 `py_object_*`·슬롯만 두고, **opcode 핸들러는 별도 파일에서 파일당 1개** opcode만 정의 (예: `233001_opcode_load_const.sql`, `238001_opcode_binary_add.sql`).
- **함수 정의**: `py_get_opcode_size`는 `230000_ceval_core` 한 곳. `py_eval_frame`은 `232000`·`241000`에서 CREATE OR REPLACE. **opcode 순서**: 슬롯/지원(234000–240300) 먼저, 그 다음 opcode 블록(240301–240316, 241001–241005). 새 opcode 추가 시: (1) `240317_opcode_<name>.sql` 등 블록 안에 새 파일 추가, (2) eval 루프 3곳(232000, 241000, 241100)에 CASE 분기 추가.

---

## 4. "코드" 관점에서 보면

1. **객체/타입/슬롯**  
   구조체·테이블(220000, 224000), bootstrap(223000), 예외 스키마·헬퍼·세터(224100–224300), builtin(225000), type method slots(226000)  
   그 위에 **tp_call, tp_hash, tp_richcompare, nb_*, sq_*** 가 슬롯 단위·기능 단위로 한 파일씩 정리됨.

2. **VM (ceval)**  
   **메인 루프 + 전체 opcode switch** 는 `232000_ceval_eval_frame`·`241000_ceval_exception_dispatch`·`241100_python_exception_setters` 에서 CASE 분기.  
   **opcode 핸들러**는 파일당 1개, **240301–240316**(일반 opcode 블록)과 **241001–241005**(예외 opcode 블록)에만 있음.  
   **예외 처리**는 exception_schema(224100, co_exceptiontable 포함), exception_helpers(224200), exception_setters(224300), exception_table_parsing(224400) → ceval_exception_dispatch(241000), opcode 5개(241001–241005), python_exception_setters(241100) 순.

3. **참고 문서**  
   - [EXCEPTION_HANDLING_DESIGN.md](EXCEPTION_HANDLING_DESIGN.md): 예외 처리 설계 (CPython 3.11 고증).  
   - [DICT_LOOKUP_DESIGN.md](DICT_LOOKUP_DESIGN.md): dict lookup hash·동등성 설계.
