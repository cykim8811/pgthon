# CPython 3.11 캐시·특수 opcode (Elytra)

Elytra VM이 3.11 CACHE 및 (향후) 특수 opcode를 어떻게 다루는지 틀만 정한다. 임시방편 없이 문서만 선행하고, 구현은 단계적으로 맞춘다.

---

## 1. CACHE (opcode 0)

- **의미:** 3.11 인라인 캐시용 2바이트 no-op. 컴파일러가 일부 opcode 뒤에 CACHE 슬롯을 삽입한다.
- **Elytra 동작:** 디스패치하지 않고, 오프셋만 2 증가. `f_lasti`는 갱신하지 않는다 (docs/BYTECODE_ENCODING_3_11.md).
- **구현:** `py_eval_frame` CASE WHEN 0 THEN NULL, f_lasti 갱신 시 opcode != 0 조건.

---

## 2. 특수 opcode (specialized opcodes)

- **3.11:** LOAD_ATTR, CALL 등에 “캐시 슬롯 + 특수 opcode 번호”가 붙는 경우가 있음 (PEP 659, adaptive interpreter). 예: CALL 뒤에 CACHE 2개 등.
- **Elytra 현재:** 기본 opcode 세트만 처리 (LOAD_ATTR 106, CALL 171 등). 특수 opcode 번호는 미구현 시 `Unknown opcode`로 폴란다.
- **틀:** (1) 명령어 형식은 wordcode 유지 (2바이트 per instruction). (2) CACHE(0)는 계속 2바이트 건너뛰기. (3) 특수 opcode를 추가할 때는 CPython `Include/opcode.h`, `Lib/opcode.py`, `_inline_cache_entries` 등에 맞춰 “기본 opcode와 동일 시맨틱 + 캐시 무시” 또는 “캐시 사용” 중 하나로 정책을 정한다. (4) 새 마이그레이션 대신 기존 eval_frame·opcode 마이그레이션 수정으로 반영.

---

## 3. 정리

| 항목 | 규약 |
|------|------|
| CACHE (0) | 2바이트 건너뛰기, f_lasti 미갱신 (이미 구현) |
| 특수 opcode | 향후 단계에서 추가; wordcode 유지, CACHE 슬롯은 건너뛰기 또는 문서 정책 따름 |
| 마이그레이션 | 기존 파일만 수정, 새 migration 없음 |

이 문서는 4단계 “캐시/특수 opcode” 틀을 고정하고, 구체적 특수 opcode 번호·시맨틱은 CPython 고증에 맞춰 이후 단계에서 채운다.
