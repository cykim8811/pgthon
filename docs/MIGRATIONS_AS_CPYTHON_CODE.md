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

### 2.1 객체 모델 (Objects/에 대응)

| 현재 마이그레이션 | CPython 관점에서의 역할 |
|------------------|-------------------------|
| `220000_python_object_schema` | `PyObject`, `PyTypeObject`, `PyDictEntry`, method 슬롯 테이블 등 **구조체 정의** |
| `223000_python_bootstrap` | 내장 타입/객체 **인스턴스 생성** (object, type, str, int, ...) |
| `224000_function_object_schema` | `PyFunctionObject`, `PyCodeObject`, `PyFrameObject` **구조체** |
| `225000_builtin_functions` | `len`, `abs` 등 **builtin 함수** 구현·등록 |
| `226000_type_method_slots` | `PySequenceMethods`/`PyMappingMethods` **슬롯 구현·등록** (sq_length, mp_length, len) |
| `234000_tp_call_slot` | `tp_call` 슬롯 + `py_object_call` |
| `234500_tp_call_kwargs` | `tp_call` kwargs 처리 |
| `235000_tp_hash_slot` | `tp_hash` 슬롯 + hash 기반 dict (`py_dict_get_item`, `py_dict_set_item`) |
| `235800_tp_hash_extended` | bytes/bool/none/tuple 등 **추가 타입**에 대한 tp_hash 등록 |
| `235500_nb_absolute_slot` | `nb_absolute` 슬롯 + int/float 등록 |
| `236000_tp_richcompare_slot` | `tp_richcompare` 슬롯 + `py_object_richcompare` |
| `237000_tp_richcompare_full_ops` | str/long용 **Py_LT..Py_GE** 전부 구현 |
| `238000`–`239200` (BINARY_ADD/SUBTRACT/MULTIPLY) | `nb_add`/`nb_subtract`/`nb_multiply`, `sq_concat`/`sq_repeat` **슬롯 구현·등록** + `py_object_add`/`subtract`/`multiply` |
| `240000_compare_op_phase1_richcompare_reflected` | `py_object_richcompare`의 **reflected op** 로직 (객체 쪽 보강) |
| `240300_jump_phase1_py_object_istrue` | **PyObject_IsTrue** (truth value) |

→ 한 줄로 보면: **"객체/타입/슬롯 정의 + builtin + 타입별 슬롯 구현·등록"** 이 여러 파일로 쪼개져 있음.

### 2.2 VM / ceval (Python/ceval.c에 대응)

| 현재 마이그레이션 | CPython 관점에서의 역할 |
|------------------|-------------------------|
| `230000_vm_core` | 스택·프레임 유틸, **py_get_opcode_size** (instruction 형식) |
| `232000_vm_eval_frame` | **py_eval_frame** = 메인 루프 + opcode `CASE` 전부 (LOAD_CONST, BINARY_ADD, COMPARE_OP, JUMP_*, RETURN_VALUE 등) |
| `233000_vm_opcodes_basic` | **LOAD_CONST, STORE_NAME, LOAD_NAME, CALL_FUNCTION** opcode 핸들러 |
| `238300`, `238800`, `239300` | **BINARY_ADD, BINARY_SUBTRACT, BINARY_MULTIPLY** opcode 핸들러 |
| `240100_compare_op_phase2_opcode` | **COMPARE_OP** opcode 핸들러 |
| `240400_jump_phase2` | **JUMP_FORWARD, POP_JUMP_FORWARD_IF_FALSE** + eval_frame의 `next_i` 처리 |
| `240500_jump_phase3` | **POP_JUMP_FORWARD_IF_TRUE** opcode 핸들러 |
| `240600_pop_top_phase1` | **POP_TOP** opcode 핸들러 |

→ 실제 **코드**가 들어 있는 건 위 파일들.  
나머지 "Phase 5 / Phase 3 eval_frame" 마이그레이션들은 **eval_frame을 수정하지 않고**, 주석만 있음.

---

## 3. 문제점 정리 (코드 관점)

### 3.1 한 기능이 여러 마이그레이션으로 쪼개짐

- **BINARY_ADD**: 5개 파일 (238000 Phase1 ~ 238400 Phase5).  
  CPython이라면:  
  - Objects 쪽: `nb_add`/`sq_concat` 슬롯 + `PyNumber_Add` 디스패치 + 타입별 구현  
  - ceval 쪽: BINARY_ADD 한 줄 `CASE`  
  → 논리적으로는 **"객체 레이어 (슬롯/디스패치)"** + **"VM 레이어 (opcode 한 줄)"** 두 덩어리인데, 5단계로 나뉨.

- **COMPARE_OP**: 3개 (240000 richcompare 반사, 240100 opcode, 240200 eval_frame).  
  그중 **240200**은 **코드 변경 없음**, "py_eval_frame은 232000에 있고 107 포함" 주석만 있음.

- **Jump**: 3개 (240300 PyObject_IsTrue, 240400 opcode+eval_frame, 240500 POP_JUMP_IF_TRUE).  
  eval_frame의 JUMP 분기는 이미 **232000**에 다 들어 있음.

### 3.2 실제로 아무 코드도 넣지 않는 마이그레이션 (no-op) — **완료: 5개 제거함**

- ~~`238400_binary_add_phase5_eval_frame`~~ – 제거됨.
- ~~`238900_binary_subtract_phase5_eval_frame`~~ – 제거됨.
- ~~`239400_binary_multiply_phase5_eval_frame`~~ – 제거됨.
- ~~`240200_compare_op_phase3_eval_frame`~~ – 제거됨.
- ~~`240700_have_argument_uniform_2bytes`~~ – 제거됨.

### 3.3 이름이 "마이그레이션 단계" 기준

- `phase1_schema`, `phase2_dispatch`, `phase3_py_object_add`, `phase4_opcode`, `phase5_eval_frame`  
  → CPython 코드 구조를 읽을 때는 **"PyNumberMethods nb_add"**, **"ceval BINARY_ADD"** 같은 **개념/위치**가 더 맞음.

### 3.4 opcode·eval_frame이 여러 파일에 흩어짐

- **ceval.c**라면: 한 파일 안에  
  - 메인 루프  
  - opcode 번호별 `switch`  
  - (또는 같은 파일에서 호출하는) opcode 핸들러  
  가 같이 있거나, 최소한 "실행 루프"는 한 곳에 모여 있음.

- 현재:  
  - **py_eval_frame**과 그 안의 **CASE 전부**는 `232000` 한 파일.  
  - opcode **핸들러 함수**는 233000, 238300, 238800, 239300, 240100, 240400, 240500, 240600에 나뉨.  
  → "eval_frame = ceval의 switch" 는 한 군데 있지만, "opcode 구현"은 기능별로 흩어져 있어서, **한 opcode의 동작을 보려면 여러 마이그레이션을 넘나들어야 함.**

---

## 4. 정리: "코드" 관점에서 보면

1. **객체/타입/슬롯**  
   - 구조체·테이블 정의(220000, 224000), bootstrap(223000), builtin(225000), type method slots(226000)  
   - 그 위에 **tp_call, tp_hash, tp_richcompare, nb_*, sq_*** 등이 슬롯 단위로 여러 파일에 나뉘어 있음.  
   → CPython의 **Objects/** + **Include/** 에 대응하는 "한 덩어리"로 보면, 지금은 **기능(ADD/SUBTRACT/MULTIPLY 등)별·Phase별**로 잘려 있음.

2. **VM (ceval)**  
   - **메인 루프 + 전체 opcode switch** 는 `232000` 한 파일에 잘 모여 있음.  
   - 반면 **opcode 핸들러**는 basic(233000) + BINARY_*(238300 등) + COMPARE_OP(240100) + Jump(240400, 240500) + POP_TOP(240600) 로 나뉨.  
   → "ceval.c 한 파일"처럼 읽으려면 **opcode 관련 코드를 더 모으는** 방향이 자연스러움.

3. **no-op 마이그레이션**  
   - 238400, 238900, 239400, 240200, 240700은 **실제 코드 변경이 없음**.  
   → 코드 저장소라면 **삭제하거나**, 정말로 남길 이유가 있으면 "문서/이력용"으로만 두는 게 맞음.

4. **이름**  
   - `phase1`/`phase2`/… 보다는 **`tp_call`**, **`nb_add`**, **`ceval_binary_add`** 처럼 **CPython 식별자/역할**에 맞춘 이름이 "코드" 읽기에는 유리함.

---

## 5. 다음 단계 제안 (선택)

- **no-op 마이그레이션 정리**: 238400, 238900, 239400, 240200, 240700을 제거하거나, "문서만" 역할로 축소.
- **이름 정리**: 파일명/헤더를 CPython 개념 기준으로 (예: `tp_call_slot`, `nb_add_slots`, `ceval_opcodes_binary` 등).
- **구조 재구성 (큰 작업)**:  
  - "Objects" 블록: 스키마 + 슬롯 정의/등록을 **슬롯 단위** 또는 **타입 단위**로 묶어서 파일 수 축소.  
  - "ceval" 블록: opcode 핸들러를 **한 마이그레이션(또는 소수)** 에 모아서, 232000의 `CASE`와 대응 관계가 한눈에 보이게.

원하면 no-op 제거나 이름 변경부터 단계별로 적용할 수 있다.
