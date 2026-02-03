## Elytra

Elytra는 **CPython의 객체 모델을 PostgreSQL 위에 충실하게 구현**하는 프로젝트입니다.  
목표는 "파이썬을 DB 위에서 굴린다"가 아니라, **CPython이 파이썬을 성립시키는 핵심 아이디어들을** 구조적으로 올바른 방식으로 **최소(minimal) 단위부터 단계적으로** 구현하는 것입니다.

---

## 목적 (Goal)

- **CPython의 고증(fidelity)을 최대한 유지**한 채로, CPython의 내부 표현(구조체/포인터/상속/싱글턴)을 **관계형 데이터 모델로 옮깁니다.**
- 전체 CPython을 "완성품처럼" 재현하는 대신, 각 개념의 **핵심 아이디어를 드러내는 데 필요한 최소 구성**을 구현합니다.
- "동작만 맞추는 임시방편(hack)"은 허용하지 않습니다. 설계/스키마/테스트가 **깨끗하고 확장 가능한 정합성**을 가져야 합니다.

---

## 핵심 철학 (Principles)

- **Faithful**: CPython의 개념(객체/타입/상속/내장 싱글턴 등)을 왜곡하지 않습니다.
- **Minimal**: "필요한 만큼만" 구현합니다. 단, 생략은 **개념을 훼손하지 않는 범위**에서만 합니다.
- **Composable**: 이후 개념(예: descriptor, MRO, attribute lookup, opcode/frames 등)이 자연스럽게 쌓이도록, 기반을 단단히 합니다.

---

## 구현 방향 (CPython → PostgreSQL 매핑)

Elytra는 CPython의 "구조체 상속(헤더 + 확장)" 감각을 PostgreSQL에서 다음 방식으로 표현합니다.

- **모든 객체는 `PyObject`**: 한 row가 하나의 객체를 의미합니다.
- **타입도 객체**: `PyTypeObject` 역시 `PyObject`를 베이스로 갖습니다.
- **상속은 `tp_bases`(tuple)로 표현**: `tp_bases`는 튜플 오브젝트를 가리키며, 그 튜플은 베이스 타입들의 `PyObject`들을 담습니다.
- **내장 싱글턴/코어 타입 부트스트랩**: `type`, `object`, `None` 등은 초기 부트스트랩으로 "세계의 바닥"을 형성합니다.

---

## 데이터베이스 (Supabase / PostgreSQL)

`supabase/migrations/`는 다음 계층으로 구성됩니다. 상세한 파일 목록은 디렉터리 번호순을 참고한다.

- **앱 스키마** (`20260112141514_app_schema.sql`)
  - 사용자 프로필, 워크스페이스, 권한 관리 등 애플리케이션 레벨 인프라
  - RLS 정책 및 자동화 트리거 포함

- **CPython 구조체·부트스트랩** (`20260114220000`·`20260114223000`)
  - 구조체 정의: `py_object`, `py_type_object`, `py_unicode_object` 등 테이블 스키마 (C 헤더와 유사)
  - 부트스트랩: `object`, `type`, `str`, `int`, `list`, `dict`, `tuple`, `NoneType`, `None` 싱글턴 등 "세계의 바닥" 구축

- **실행 모델** (function/code/frame 스키마, builtin 함수, type method slots)
  - `py_function_object`, `py_code_object`, `py_frame_object` 등과 내장 함수(`len`, `abs`) 등록
  - `tp_as_sequence`/`tp_as_mapping`·`PyObject_Size` 등 타입 슬롯 기반 길이 연산

- **VM 코어·opcode** (스택, eval_frame, opcode 핸들러)
  - 스택 연산·바이트코드 해석·`py_eval_frame` 메인 루프
  - opcode 핸들러는 **파일당 1개** opcode만 정의 (`*_opcode_*.sql`); 슬롯/객체 계층과 분리

- **타입 슬롯** (tp_call, tp_hash, tp_richcompare)
  - 호출 가능·해시·비교를 슬롯으로 디스패치; dict lookup은 hash + tp_richcompare 기반으로 동작

---

## 규칙 (Rules)

- **CPython 고증 우선, 임시구현 최소화**: 설계 결정 시 "CPython은 왜/어떻게 하는가"가 최우선 기준입니다. CPython보다 기능이 적은 것은 허용하지만, CPython과 다른 방향의 구현은 허용하지 않습니다. 임시방편을 최소화하고 구조적으로 올바른 방향으로 진행합니다.
  - 만약 이것이 PostgreSQL의 한계이거나 다른 방향의 구현이 더 낫다는 판단이 들면, 사용자에게 확인을 받습니다. 구조적 오류나 설계상 문제가 발견되면 사용자에게 알립니다.
- **테스트 파일은 run_tests.sh에 반드시 추가**: 새로운 테스트 파일을 작성할 때는 반드시 `run_tests.sh`에 추가해야 합니다. 테스트 파일은 `supabase/tests/` 디렉토리에 생성하고, `run_tests.sh`의 적절한 위치에 Phase 번호와 함께 추가합니다. 테스트가 통과하지 않으면 다음 단계로 진행하지 않도록 설계되어 있으므로, 모든 테스트가 순서대로 실행되도록 보장해야 합니다.
- **임시방편 금지**: 테스트를 통과시키기 위한 "특례/하드코딩/우회"는 금지합니다. 테스트 성공을 목표로 임시구현이 들어가기 쉬우므로 경계합니다.
- **단계적 구축**: 큰 기능을 한 번에 넣지 않습니다. 핵심 개념을 작은 단위로 쪼개고, 각 단위를 완성(테스트 포함)한 뒤 다음으로 진행합니다.
- **핵심 아이디어를 기록**: 구현 디테일은 코드에, "기억해야 할 아이디어"는 README에 짧게 남깁니다.
- **Migration은 최대한 작게 유지**: 기존 스키마 수정이 필요할 때, 변경하는 migration을 추가하는 것이 아닌, 기존의 스키마 생성 코드를 수정하는 방향으로 진행합니다. 단, backfill이나 제약(예: NOT NULL) 활성화는 그것이 의존하는 구현(tp_hash 등)이 들어온 뒤의 migration에서 수행할 수 있다.
- **SQL 식별자 규칙**: PostgreSQL에서 대문자/따옴표 식별자는 케이스-센서티브로 동작해 사용성이 떨어집니다. 따라서 테이블/컬럼/제약 이름은 **소문자 스네이크 케이스**(`py_object`)로 작성합니다. 이는 PyObject와 같은 CPython의 구조체명과 대응됩니다.

---

## 핵심 아이디어 로그 (짧게 유지)

- **(현재)** CPython의 객체/타입/상속/싱글턴 부트스트랩을 PostgreSQL 스키마로 최소 구현한다.
- **모든 정체성/참조는 `PyObject.id`로 통일**: "포인터 타입은 전부 `PyObject*`"라는 CPython의 감각을 DB에서는 단일 FK 타입으로 유지한다.
- **공유 PK 상속(확장 구조체)**: 각 구체 타입 테이블의 PK는 `PyObject.id`(= `ob_base`)이며, 별도의 독립 ID를 만들지 않는다.
- **스키마 명명과 개념 명을 분리한다**: DB 객체명은 `py_object`처럼 쓰되, 이는 CPython의 `PyObject`를 구현한다는 의미임을 주석/문서로 명시한다.
- **Bound Method 객체**: 인스턴스 메서드 호출을 위해 함수와 인스턴스를 함께 저장하는 `py_method_object`를 구현한다. `im_self`가 NULL이면 unbound method이다.

---

## TODO

- **Dict lookup hash 1단계**: 완료. `LOAD_NAME`/`STORE_NAME`과 dict 조회는 hash·동등성 기반(`py_dict_get_item`/`py_dict_set_item`)으로 동작한다. 설계는 **[docs/DICT_LOOKUP_DESIGN.md](docs/DICT_LOOKUP_DESIGN.md)** 참고.
- **Dict lookup 2단계**: 완료. 키 동등성은 `tp_richcompare` 슬롯 경유 `py_object_richcompare_eq` 사용. True/False/NotImplemented는 부트스트랩에 있으며, `20260114236000_tp_richcompare_slot.sql`에서 슬롯·타입별 함수·디스패치·dict 연동 및 str/int에 대한 Py_LT·Py_LE·Py_NE·Py_GT·Py_GE 구현.
- **같은 해시 다른 문자열 테스트**: `18_dict_lookup_hash.sql` Test 10은 서로 다른 str이 같은 `py_object_hash`인 쌍을 써서, 같은 `me_hash` 다른 키에 대해 `get_item`이 equality로 올바른 값을 반환하는지 검증한다. 충돌 쌍은 **`supabase/scripts/find_hash_collision.sql`**을 한 번 실행해 얻고, 출력된 두 문자열을 Test 10의 `COLLISION_A`/`COLLISION_B`에 하드코딩해 두었다. 테스트는 매번 탐색하지 않으므로 가볍게 동작한다.

---

## 문서

- **[VM_DESIGN.md](VM_DESIGN.md)**: VM·opcode·예외 처리 설계 및 구현 요약.
- **docs/[DICT_LOOKUP_DESIGN.md](docs/DICT_LOOKUP_DESIGN.md)**: dict lookup hash·동등성 설계.
- **docs/[EXCEPTION_HANDLING_DESIGN.md](docs/EXCEPTION_HANDLING_DESIGN.md)**: 예외 처리 설계 (CPython 3.11 고증).
- **docs/[MIGRATIONS_AS_CPYTHON_CODE.md](docs/MIGRATIONS_AS_CPYTHON_CODE.md)**: 마이그레이션을 CPython 코드 구조에 대응한 매핑.
- **docs/[TP_CALL_KWARGS_DESIGN.md](docs/TP_CALL_KWARGS_DESIGN.md)**: tp_call·kwargs: 3인자 규약, CALL_FUNCTION_KW, METH_KEYWORDS 구현 완료.
- **docs/[FLOAT_IMPLEMENTATION_DESIGN.md](docs/FLOAT_IMPLEMENTATION_DESIGN.md)**: float 타입 nb_add/nb_subtract/nb_multiply·tp_hash·tp_richcompare 설계·구현 완료.
- **docs/[BYTES_OPERATIONS_DESIGN.md](docs/BYTES_OPERATIONS_DESIGN.md)**: bytes 타입 sq_length/sq_concat/sq_repeat·tp_richcompare 설계·구현 완료 (CPython 고증·임시구현 없음).
- **docs/[BUILD_TUPLE_LIST_DESIGN.md](docs/BUILD_TUPLE_LIST_DESIGN.md)**: BUILD_TUPLE(102)·BUILD_LIST(103) opcode 설계 (CPython 고증·임시구현 없음, 작업 의존관계·실행 순서 포함).
- **docs/[LOAD_ATTR_DESIGN.md](docs/LOAD_ATTR_DESIGN.md)**: LOAD_ATTR(106)·속성 조회 설계 (PyObject_GetAttr, tp_dict, 디스크립터 __get__, AttributeError, 작업 의존관계·실행 순서 포함).
- **docs/[STORE_ATTR_DESIGN.md](docs/STORE_ATTR_DESIGN.md)**: STORE_ATTR(95)·속성 저장 설계 (PyObject_SetAttr, 디스크립터 __set__, 인스턴스 __dict__, 작업 의존관계·실행 순서 포함).
- **docs/[BOUND_METHOD_DESIGN.md](docs/BOUND_METHOD_DESIGN.md)**: Bound Method 설계 (인스턴스에서 메서드 조회 시 __get__ → bound method, 호출 시 im_func(im_self, *args), 작업 의존관계·실행 순서 포함).
