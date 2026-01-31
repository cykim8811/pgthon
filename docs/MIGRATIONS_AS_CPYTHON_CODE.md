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

## 2. 현재 마이그레이션을 CPython 코드처럼 매핑 (20개 파일)

### 2.1 객체 모델 (Objects/에 대응)

| 마이그레이션 | CPython 관점에서의 역할 |
|--------------|-------------------------|
| `220000_python_object_schema` | `PyObject`, `PyTypeObject`, `PyDictEntry`, method 슬롯 테이블 등 **구조체 정의** |
| `223000_python_bootstrap` | 내장 타입/객체 **인스턴스 생성** (object, type, str, int, ...) |
| `224000_function_object_schema` | `PyFunctionObject`, `PyCodeObject`, `PyFrameObject` **구조체** |
| `225000_builtin_functions` | `len`, `abs` 등 **builtin 함수** 구현·등록 |
| `226000_type_method_slots` | `PySequenceMethods`/`PyMappingMethods` **슬롯 구현·등록** (sq_length, mp_length, len) |
| `234000_tp_call_slot` | `tp_call` 슬롯 + `py_object_call` |
| `235000_tp_hash_slot` | `tp_hash` 슬롯 + hash 기반 dict (`py_dict_get_item`, `py_dict_set_item`) |
| `235500_nb_absolute_slot` | `nb_absolute` 슬롯 + int/float 등록 |
| `236000_tp_richcompare_slot` | `tp_richcompare` 슬롯 + `py_object_richcompare` |
| `238000_binary_add` | `nb_add`/`sq_concat` 슬롯 + `py_object_add` + opcode 23 |
| `238500_binary_subtract` | `nb_subtract` 슬롯 + `py_object_subtract` + opcode 24 |
| `239000_binary_multiply` | `nb_multiply`/`sq_repeat` 슬롯 + `py_object_multiply` + opcode 20 |
| `240000_compare_op` | `py_object_richcompare` reflected op + **COMPARE_OP** opcode 107 |
| `240300_py_object_istrue` | **PyObject_IsTrue** (truth value for JUMP_*) |
| `240400_jump_opcodes` | **JUMP_FORWARD, POP_JUMP_IF_FALSE/TRUE** opcode 핸들러 + eval_frame 분기 |
| `240600_pop_top` | **POP_TOP** (opcode 1) opcode 핸들러 |

→ 한 줄로 보면: **"객체/타입/슬롯 정의 + builtin + 타입별 슬롯 구현·등록"** 이 기능별로 한 파일씩 정리되어 있음.

### 2.2 VM / ceval (Python/ceval.c에 대응)

| 마이그레이션 | CPython 관점에서의 역할 |
|--------------|-------------------------|
| `230000_ceval_core` | 스택·프레임 유틸, **py_get_opcode_size** (Python 3.11 uniform 2-byte) |
| `232000_ceval_eval_frame` | **py_eval_frame** = 메인 루프 + opcode `CASE` 전부 (LOAD_CONST, BINARY_ADD, COMPARE_OP, JUMP_*, POP_TOP, RETURN_VALUE 등) |
| `233000_ceval_opcodes_basic` | **LOAD_CONST, STORE_NAME, LOAD_NAME, CALL_FUNCTION** opcode 핸들러 |
| `238000`–`239000` (binary_*) | **BINARY_ADD, BINARY_SUBTRACT, BINARY_MULTIPLY** opcode 핸들러 (각 파일에 슬롯+opcode 통합) |
| `240000_compare_op` | **COMPARE_OP** opcode 107 핸들러 |
| `240400_jump_opcodes` | **JUMP_FORWARD, POP_JUMP_FORWARD_IF_FALSE/TRUE** + eval_frame의 `next_i` 처리 |
| `240600_pop_top` | **POP_TOP** opcode 1 핸들러 |

→ **py_eval_frame**과 그 안의 **CASE 전부**는 `232000_ceval_eval_frame` 한 파일에 있음.  
opcode **핸들러 함수**는 basic(233000) + binary_*(238000 등) + compare_op(240000) + jump(240400) + pop_top(240600)에 나뉨.

---

## 3. 정리된 점 (이전 대비)

### 3.1 no-op 마이그레이션 제거

- ~~`238400_binary_add_phase5_eval_frame`~~ – 제거됨.
- ~~`238900_binary_subtract_phase5_eval_frame`~~ – 제거됨.
- ~~`239400_binary_multiply_phase5_eval_frame`~~ – 제거됨.
- ~~`240200_compare_op_phase3_eval_frame`~~ – 제거됨.
- ~~`240700_have_argument_uniform_2bytes`~~ – 제거됨.

### 3.2 파일명·구조 정리

- **이름**: `phase1`/`phase2` 대신 **`ceval_core`**, **`binary_add`**, **`compare_op`**, **`jump_opcodes`**, **`pop_top`** 등 CPython 개념 기준.
- **병합**: BINARY_ADD/SUBTRACT/MULTIPLY는 각각 슬롯·디스패치·opcode를 한 파일에 통합. COMPARE_OP는 richcompare reflected + opcode를 `240000_compare_op` 한 파일에. Jump는 PyObject_IsTrue(`240300`) + opcode·eval_frame 분기(`240400`) 두 파일로 정리.
- **함수 정의**: `py_get_opcode_size`는 `230000_ceval_core` 한 곳. `py_eval_frame`은 `232000_ceval_eval_frame` 한 곳에서만 CREATE OR REPLACE하며, opcode 추가 시 그 파일을 직접 수정.

---

## 4. "코드" 관점에서 보면

1. **객체/타입/슬롯**  
   - 구조체·테이블(220000, 224000), bootstrap(223000), builtin(225000), type method slots(226000)  
   - 그 위에 **tp_call, tp_hash, tp_richcompare, nb_*, sq_*** 가 슬롯 단위·기능 단위로 한 파일씩 정리됨.

2. **VM (ceval)**  
   - **메인 루프 + 전체 opcode switch** 는 `232000_ceval_eval_frame` 한 파일에 모여 있음.  
   - **opcode 핸들러**는 ceval_opcodes_basic(233000) + binary_*(238000 등) + compare_op(240000) + jump_opcodes(240400) + pop_top(240600) 로 기능별로 나뉨.

3. **참고 문서**  
   - `docs/MIGRATION_OVERWRITE_AUDIT.md`: 과거 덮어쓰기/분산 정의 이력 (현재 구조 반영으로 갱신됨).
