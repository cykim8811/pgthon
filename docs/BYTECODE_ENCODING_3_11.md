# CPython 3.11 바이트코드 인코딩 (Elytra)

Elytra VM이 따르는 바이트코드 형식은 CPython 3.11의 **wordcode** 규약과 동일하다. 임시방편 없이 문서·구현을 일치시킨다.

---

## 1. 명령어 형식 (wordcode)

- **단위:** 명령어당 **2바이트** (opcode 1바이트 + argument 1바이트).
- **순서:** `co_code[offset]` = opcode, `co_code[offset+1]` = arg.
- **오프셋:** **0-based byte offset** (CPython `f_lasti`, 점프 대상, 예외 테이블의 instruction index = `byte_offset / 2`).
- **저장:** `co_code`는 bytes 객체(`py_bytes_object.bytes_value`, PostgreSQL `bytea`)로 저장하며, 위 순서 그대로 저장한다.

CPython 3.6+에서 도입된 uniform 2-byte instruction과 동일하다. 3.11에서도 기본 명령어 크기는 2바이트이다.

---

## 2. EXTENDED_ARG (144)

- opcode 144: 다음 명령어의 arg를 확장한다. `arg_final = (extended << 8) | arg` (연쇄 가능).
- Elytra는 이미 eval 루프에서 EXTENDED_ARG를 처리하며, 확장 후 논리적 arg 한 개로 디스패치한다.

---

## 3. CACHE (opcode 0)

- **CPython 3.11:** opcode **0** = CACHE. 인라인 캐시용 2바이트 no-op이다.
- **동작:** 디스패치하지 않고, 오프셋만 2 증가시킨다. `f_lasti`는 갱신하지 않는다 (마지막으로 “실행한” 명령어는 CACHE가 아님).
- **이유:** 3.11 컴파일러가 일부 opcode 뒤에 CACHE 슬롯을 삽입한다. 이를 건너뛰지 않으면 다음 명령어를 잘못 읽는다.

---

## 4. PostgreSQL get_byte

- `get_byte(bytea, n)`: PostgreSQL 문서상 **n번째 바이트는 0-based** (“the first byte as byte 0”).
- Elytra eval 루프의 `i`는 0-based byte offset으로 사용하며, `get_byte(bytecode, i)`, `get_byte(bytecode, i+1)`로 opcode/arg를 읽는다.

---

## 5. 정리

| 항목           | 규약                          |
|----------------|-------------------------------|
| 명령어 크기     | 2바이트 (opcode + arg)        |
| 바이트 순서     | [opcode, arg] 반복            |
| 오프셋          | 0-based byte offset           |
| CACHE (0)       | 2바이트 건너뛰기, f_lasti 미갱신 |
| EXTENDED_ARG(144) | 기존대로 연쇄 arg 확장        |

이 문서는 코드 객체 구조(2단계), 예외 테이블(3단계), 캐시/특수 opcode(4단계)와 독립적으로 “명령어 스트림을 어떻게 읽는가”만 정의한다.
