# CPython 3.11 예외 테이블 형식·위치 (Pgthon)

Pgthon의 예외 테이블은 CPython 3.11 `co_exceptiontable` 규약에 맞춘다. 형식·위치를 한 번 정해 두고 이후 수정 없이 유지한다.

---

## 1. 위치

- **저장:** `py_code_object.co_exceptiontable` (bytea).
- **의미:** NULL 또는 빈 bytea = 예외 처리 구간 없음. 비어 있지 않으면 아래 바이너리 형식으로 해석한다.

---

## 2. 오프셋 단위

- **instruction offset (코드 유닛):** 모든 start, end, target은 **2바이트 단위 인덱스** (instruction index).
- **Pgthon eval 루프:** `i`는 **byte offset** (0-based). 테이블 조회 시 `start_i / 2`를 instruction offset으로 넘기고, 핸들러 target은 `next_i := target_offset * 2`로 byte offset으로 환산한다.

---

## 3. 바이너리 형식 (CPython 3.11 정합)

- **엔트리 순서:** start → size → target → (depth, lasti 결합).
- **start:** 첫 바이트 7비트 (MSB=1은 “엔트리 시작” 표시, CPython과 동일). 단일 바이트.
- **size:** 6-bit varint (상위 1비트 = extend, 0이면 종료). end = start + size.
- **target:** 6-bit varint. 점프할 instruction offset.
- **depth + lasti:** 6-bit varint 한 개. 값 = (depth << 1) | (lasti ? 1 : 0). depth = 스택 trim 후 남길 개수, lasti = 예외 발생 시 lasti 설정 여부.
- **파싱:** `py_parse_exception_table(p_table bytea)` → (start_offset, end_offset, target_offset, depth, lasti) 행. `py_get_exception_handler(p_table, instruction_offset)` → 매칭되는 (target_offset, depth, lasti) 한 행.

---

## 4. 구현 위치

- **스키마:** `co_exceptiontable` 컬럼 추가 — `20260114224100_exception_schema.sql`.
- **파싱·조회:** `py_parse_exception_table`, `py_get_exception_handler` — `20260114224400_exception_table_parsing.sql`.
- **사용:** `py_eval_frame` — 예외 발생 시 `py_get_exception_handler(exc_table, start_i / 2)` 호출, `next_i := handler_target * 2`, `py_stack_trim(frame_id, handler_depth)`.

---

## 5. 정리

| 항목 | 규약 |
|------|------|
| 위치 | `py_code_object.co_exceptiontable` (bytea) |
| 단위 | instruction offset (2바이트 = 1 유닛) |
| 필드 | start, size, target, depth, lasti |
| 인코딩 | start 7비트, size/target/(depth,lasti) 6-bit varint |
| 수정 | 기존 마이그레이션(224100, 224400, 241100)만 수정, 새 migration 없음 |

이 문서는 docs/EXCEPTION_HANDLING_DESIGN.md와 동일한 설계를 “형식·위치” 관점에서 고정한다.
