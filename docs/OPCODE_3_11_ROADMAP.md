# CPython 3.11 opcode 구현 로드맵 (Elytra)

3.11 바이트코드를 지원하기 위해 **어떤 opcode를 구현해야 하는지**, **이미 구현된 것·미구현·수정 필요**를 정리한다.  
opcode 번호·이름은 CPython 3.11 `Lib/opcode.py`, `Include/opcode.h` 기준이다.

---

## 1. opcode 상태 요약

| 상태 | 의미 |
|------|------|
| ✅ 구현됨 | eval_frame에 CASE 있고, `py_opcode_*` 또는 인라인 처리됨. 3.11 시맨틱과 맞는지 점검만 하면 됨. |
| 🔲 미구현 | 3.11에서 사용. Elytra에 CASE 없음 → `Unknown opcode` 발생. 구현 필요. |
| ⚠️ 수정 필요 | Elytra에 구현돼 있으나 3.11과 번호·시맨틱 불일치 (예: DELETE_ATTR 96 vs 97). |
| 📌 특수 opcode | 3.11 specialized/cache 변형. docs/CACHE_AND_SPECIALIZED_3_11.md 정책에 따라 나중에 추가. |

---

## 2. opcode별 목록 (3.11 순서)

### 2.1 이미 구현된 opcode (✅)

| 번호 | 이름 | 비고 |
|------|------|------|
| 0 | CACHE | 2바이트 건너뛰기, f_lasti 미갱신 (docs/BYTECODE_ENCODING_3_11.md) |
| 1 | POP_TOP | |
| 100 | LOAD_CONST | |
| 101 | LOAD_NAME | |
| 90 | STORE_NAME | |
| 95 | STORE_ATTR | |
| 23 | BINARY_ADD | |
| 24 | BINARY_SUBTRACT | |
| 20 | BINARY_MULTIPLY | 3.11에서는 BINARY_OP(122)로 통합됨. Elytra는 23/24/20 유지 가능; 3.11 컴파일 결과 지원 시 BINARY_OP(122) 구현 필요. |
| 102 | BUILD_TUPLE | |
| 103 | BUILD_LIST | |
| 106 | LOAD_ATTR | |
| 107 | COMPARE_OP | |
| 110 | JUMP_FORWARD | |
| 114 | POP_JUMP_FORWARD_IF_FALSE | |
| 115 | POP_JUMP_FORWARD_IF_TRUE | |
| 166 | PRECALL | no-op |
| 171 | CALL | 위치+키워드, KW_NAMES 연동 |
| 172 | KW_NAMES | pending_kw_names_const_i |
| 83 | RETURN_VALUE | |
| 35 | PUSH_EXC_INFO | |
| 36 | CHECK_EXC_MATCH | |
| 89 | POP_EXCEPT | |
| 119 | RERAISE | |
| 130 | RAISE_VARARGS | |
| 144 | EXTENDED_ARG | eval 루프에서 연쇄 처리 |
| 9 | NOP | no-op; f_lasti 갱신 (CACHE 0과 구분). eval_frame 인라인. |
| 126 | DELETE_FAST | f_fastlocals[var_num] → NULL; 스택 미사용. 240325. |
| 140 | JUMP_BACKWARD | oparg = 목적지 instruction offset (bytes = arg*2). eval_frame 인라인. |
| 98 | DELETE_GLOBAL | f_globals에서 이름 삭제; 없으면 NameError. 240328. |
| 173 | POP_JUMP_BACKWARD_IF_NONE | pop TOS; TOS가 None이면 target instruction offset으로 점프. 240330. |
| 174 | POP_JUMP_BACKWARD_IF_NOT_NONE | pop TOS; TOS가 not None이면 target instruction offset으로 점프. 240331. |
| 175 | POP_JUMP_BACKWARD_IF_FALSE | pop TOS; false면 target instruction offset으로 점프. 240326. |
| 176 | POP_JUMP_BACKWARD_IF_TRUE | pop TOS; true면 target instruction offset으로 점프. 240327. |
| 120 | COPY | stack[-depth]를 TOS에 복사(push). depth≥1, 스택 길이≥depth 검사. 240329. |
| 12 | UNARY_NOT | pop TOS; push True if not PyObject_IsTrue(TOS) else False. 240332. |
| 117 | IS_OP | oparg 0 = "is" (push True if left is right), oparg 1 = "is not". Identity = same object (UUID). 240333. |
| 128 | POP_JUMP_FORWARD_IF_NONE | pop TOS; TOS가 None이면 forward jump (current+2+oparg*2). 240334. |
| 129 | POP_JUMP_FORWARD_IF_NOT_NONE | pop TOS; TOS가 not None이면 forward jump (current+2+oparg*2). 240335. |
| 82 | LIST_TO_TUPLE | pop TOS(list); push tuple(동일 요소). 240336. |
| 111 | JUMP_IF_FALSE_OR_POP | TOS false → jump(leave TOS); else pop. 240337. |
| 112 | JUMP_IF_TRUE_OR_POP | TOS true → jump(leave TOS); else pop. 240338. |
| 92 | UNPACK_SEQUENCE | pop TOS(tuple/list); push count elements (first at stack[-count], last at TOS). 240339. |
| 118 | CONTAINS_OP | oparg 0 = "in", 1 = "not in". container, item → bool. tuple/list 지원. 240340. |
| 105 | BUILD_MAP | pop 2*count (key, value per pair; TOS=key). 새 dict push. 240341. |
| 25 | BINARY_SUBSCR | stack ..., obj, key → ..., result. tuple/list/dict, IndexError/KeyError/TypeError. 240342. |
| 60 | STORE_SUBSCR | stack ..., obj, key, value → .... list/dict; tuple → TypeError. 240343. |

**⚠️ 이항 연산:** CPython 3.11은 BINARY_ADD(23), BINARY_SUBTRACT(24), BINARY_MULTIPLY(20)를 제거하고 **BINARY_OP(122)** + 하위 opcode로 통합했다. Elytra는 현재 23/24/20을 구현해 두었고, 3.11 컴파일러가 생성하는 바이트코드는 122를 쓰므로 **3.11 생성 바이트코드**를 직접 실행하려면 BINARY_OP(122) 구현이 필요하다.

**⚠️ DELETE_ATTR:**  
Elytra는 **97**으로 디스패치하지만, CPython 3.11에서는 **96 = DELETE_ATTR**, **97 = STORE_GLOBAL**이다.  
3.11 맞추려면: 96 → DELETE_ATTR, 97 → STORE_GLOBAL 추가.

---

### 2.2 3.11 지원을 위해 구현해야 할 opcode (🔲)

| 번호 | 이름 | 우선순위 | 비고 |
|------|------|----------|------|
| 2 | PUSH_NULL | 높음 | 호출 규약. bound method / 메서드 호출. docs/CALL_PROTOCOL_3_11_DESIGN.md Phase 3. |
| 151 | RESUME | 중 | 함수 진입 시 no-op. 3.11 컴파일러가 맨 앞에 넣음. |
| 96 | DELETE_ATTR | 높음 | 3.11은 96. Elytra는 현재 97에 DELETE_ATTR 매핑 → 96으로 옮기고 97은 STORE_GLOBAL. |
| 97 | STORE_GLOBAL | 중 | 3.11에서 97. 전역 이름 저장. |
| 98 | DELETE_GLOBAL | — | ✅ 구현됨 (240328). |
| 124 | LOAD_FAST | 높음 | 로컬 변수 인덱스. 3.11 기본 로딩. |
| 125 | STORE_FAST | 높음 | |
| 126 | DELETE_FAST | — | ✅ 구현됨 (240325). |
| 116 | LOAD_GLOBAL | 높음 | globals+builtins. LOAD_NAME과 유사하나 3.11에서 별도. |
| 122 | BINARY_OP | 중 | 3.11 통합 이항 연산. 하위 opcode로 +, -, * 등. |
| 160 | LOAD_METHOD | 중 | 메서드 로드(bound/unbound). CALL 전에 사용. |
| 142 | CALL_FUNCTION_EX | 낮음 | *args/**kwargs 확장 호출. |
| 132 | MAKE_FUNCTION | 중 | 함수 객체 생성. |
| 9 | NOP | — | ✅ 구현됨 (eval_frame 인라인). |
| 10–12, 15 | UNARY_* | 낮음 | 12 UNARY_NOT ✅ 구현됨 (240332). 10, 11, 15 (POSITIVE, NEGATIVE, INVERT) 미구현. |
| 25 | BINARY_SUBSCR | — | ✅ 구현됨 (240342). |
| 60 | STORE_SUBSCR | — | ✅ 구현됨 (240343). |
| 61 | DELETE_SUBSCR | 낮음 | |
| 92 | UNPACK_SEQUENCE | — | ✅ 구현됨 (240339). tuple/list → stack. |
| 104 | BUILD_SET | 낮음 | |
| 105 | BUILD_MAP | — | ✅ 구현됨 (240341). dict 리터럴. |
| 108 | IMPORT_NAME | 낮음 | |
| 109 | IMPORT_FROM | 낮음 | |
| 111 | JUMP_IF_FALSE_OR_POP | — | ✅ 구현됨 (240337). |
| 112 | JUMP_IF_TRUE_OR_POP | — | ✅ 구현됨 (240338). |
| 117 | IS_OP | — | ✅ 구현됨 (240333). oparg 0=is, 1=is not. |
| 118 | CONTAINS_OP | — | ✅ 구현됨 (240340). tuple/list. |
| 120 | COPY | — | ✅ 구현됨 (240329). |
| 128–129 | POP_JUMP_FORWARD_IF_NONE/NOT_NONE | — | 128, 129 ✅ 구현됨 (240334, 240335). |
| 133 | BUILD_SLICE | 낮음 | |
| 135–139, 148 | MAKE_CELL, LOAD_CLOSURE, *DEREF, LOAD_CLASSDEREF | 낮음 | 클로저/자유 변수. |
| 140 | JUMP_BACKWARD | — | ✅ 구현됨 (oparg = target instruction offset). |
| 173–176 | POP_JUMP_BACKWARD_* | — | 173, 174 ✅ 구현됨 (240330, 240331). 175, 176 ✅ 구현됨 (240326, 240327). |
| 82 | LIST_TO_TUPLE | — | ✅ 구현됨 (240336). |
| 84–88 | IMPORT_STAR, SETUP_ANNOTATIONS, YIELD_VALUE 등 | 낮음 | 모듈/제너레이터. |

---

### 2.3 특수 opcode (📌)

3.11 adaptive/specialized opcode (예: CALL_PY_EXACT_ARGS, LOAD_ATTR_INSTANCE_VALUE 등).  
docs/CACHE_AND_SPECIALIZED_3_11.md: 먼저 기본 opcode를 채우고, 필요 시 CPython `_specializations` / `_inline_cache_entries`에 맞춰 추가.  
여기서는 **기본 opcode 구현이 선행**이므로 별도 표는 생략.

---

## 3. 3.11 지원을 위해 해야 할 작업 (비 opcode)

| 작업 | 내용 |
|------|------|
| **PUSH_NULL + CALL 연동** | CALL 실행 시 스택에 NULL이 있으면 pop 정리. NULL 객체(UUID 또는 전용 상수) 정의. |
| **DELETE_ATTR 96 / STORE_GLOBAL 97** | eval_frame에서 97 → DELETE_ATTR 제거, 96 → DELETE_ATTR, 97 → STORE_GLOBAL. 기존 테스트/바이트코드가 97로 DELETE_ATTR 쓰고 있으면 96으로 변경. |
| **BINARY_OP(122)** | 3.11은 이항 연산을 122 + 하위 opcode로 통합. 23/24/20만 쓰는 바이트코드는 그대로 두고, 3.11 컴파일 결과 지원 시 122 구현. |
| **co_posonlyargcount / co_kwonlyargcount** | CALL 또는 MAKE_FUNCTION에서 인자 검사·기본값 적용 시 사용 (docs/CODE_OBJECT_3_11.md). |
| **LOAD_FAST / STORE_FAST** | `co_varnames` 인덱스로 f_locals가 아닌 “빠른 로컬” 슬롯 사용. 3.11 컴파일러가 자주 사용. |
| **RESUME(151)** | 함수/제너레이터 진입 시 1바이트 인자만 읽고 no-op. 3.11 바이트코드 맨 앞에 자주 등장. |
| **로더/테스트** | Python 3.11 `compile()` 결과(co_code, co_consts 등)를 Elytra `py_code_object`에 넣고 실행하는 경로·테스트. |

---

## 4. 권장 구현 순서

1. **DELETE_ATTR 96, STORE_GLOBAL 97** — 3.11 번호 맞추기 + STORE_GLOBAL 추가.  
2. **PUSH_NULL(2)** — 호출 규약 완성 (docs/CALL_PROTOCOL_3_11_DESIGN.md).  
3. **RESUME(151)** — no-op, 3.11 바이트코드 맨 앞 대응.  
4. **LOAD_FAST(124), STORE_FAST(125)** — 로컬 변수 접근.  
5. **LOAD_GLOBAL(116)** — 전역/빌트인.  
6. **BINARY_OP(122)** — 3.11 이항 연산 통합 (필요 시).  
7. **LOAD_METHOD(160), MAKE_FUNCTION(132)** 등 — 사용 시나리오에 따라 추가.

---

## 5. 참고

- **opcode 번호·이름:** CPython 3.11 `Lib/opcode.py`, `Include/opcode.h`.  
- **호출 규약:** docs/CALL_PROTOCOL_3_11_DESIGN.md.  
- **인코딩·CACHE:** docs/BYTECODE_ENCODING_3_11.md.  
- **코드 객체 필드:** docs/CODE_OBJECT_3_11.md.  
- **캐시·특수 opcode:** docs/CACHE_AND_SPECIALIZED_3_11.md.

---

## 6. 진행 중 / 완료 체크

| 작업 | 담당 | 상태 |
|------|------|------|
| DELETE_ATTR 96, STORE_GLOBAL 97 (eval_frame·테스트·신규 STORE_GLOBAL) | agent | 완료 |
| PUSH_NULL(2) — 호출 규약 Phase 3 (NULL 싱글턴·opcode·CALL 연동) | agent-blue-seven-quick-fox | 완료 |
| RESUME(151) — no-op, 3.11 바이트코드 맨 앞 대응 | agent-blue-seven-quick-fox | 완료 |
| LOAD_FAST(124), STORE_FAST(125) — 빠른 로컬 슬롯·opcode·eval_frame | agent-amber-five-bold-hawk | 완료 |
| LOAD_GLOBAL(116) — globals+builtins, opcode·eval_frame | agent-silver-three-swift-wolf | 완료 |
| BINARY_OP(122) — 3.11 이항 연산 통합 (NB_* 디스패치) | agent-crimson-nine-nimble-otter | 완료 |
| NOP(9), JUMP_BACKWARD(140), DELETE_FAST(126) — no-op·backward jump·fast local 삭제 (CPython 3.11) | agent | 완료 |
| POP_JUMP_BACKWARD_IF_FALSE(175), POP_JUMP_BACKWARD_IF_TRUE(176) — backward 조건 점프 (CPython 3.11) | agent | 완료 |
| DELETE_GLOBAL(98) — del globals[name], NameError if missing (CPython 3.11) | agent | 완료 |
| COPY(120) — stack[-depth]를 TOS에 복사 (CPython 3.11) | agent | 완료 |
| POP_JUMP_BACKWARD_IF_NONE(173), POP_JUMP_BACKWARD_IF_NOT_NONE(174) — backward None 조건 점프 (CPython 3.11) | agent | 완료 |
| UNARY_NOT(12) — not x → True/False (CPython 3.11) | agent | 완료 |
| IS_OP(117) — is / is not, identity comparison (CPython 3.11) | agent | 완료 |
| POP_JUMP_FORWARD_IF_NONE(128), POP_JUMP_FORWARD_IF_NOT_NONE(129) — forward None 조건 점프 (CPython 3.11) | agent | 완료 |
| LIST_TO_TUPLE(82) — list → tuple (CPython 3.11) | agent | 완료 |
| JUMP_IF_FALSE_OR_POP(111), JUMP_IF_TRUE_OR_POP(112) — jump or pop (CPython 3.11) | agent | 완료 |
| UNPACK_SEQUENCE(92) — tuple/list unpack to stack (CPython 3.11) | agent | 완료 |
| CONTAINS_OP(118) — in / not in (tuple, list) (CPython 3.11) | agent | 완료 |
| BUILD_MAP(105) — build dict from stack (CPython 3.11) | agent | 완료 |
| BINARY_SUBSCR(25) — obj[key] tuple/list/dict, IndexError/KeyError (CPython 3.11) | agent | 완료 |
| STORE_SUBSCR(60) — obj[key]=value list/dict, tuple→TypeError (CPython 3.11) | agent | 완료 |

이 문서는 “어떤 opcode를 구현해야 3.11 지원이 되는지”와 “지금 무엇을 해야 하는지”를 한곳에 정리한 로드맵이다.
