# Migration 덮어쓰기/분산 정의 정리 (수정 없음)

프로젝트 지향: **기존 내용 수정이 필요할 때 새 migration으로 덮어쓰지 않고, 기존 정의를 직접 수정하는 방식.**  
아래는 현재 migration들을 쭉 보면서 “나중 파일이 이전 정의를 덮어쓰거나, 한 정의가 여러 파일에 나뉘어 있는” 부분만 정리한 것이다. **파일/코드 수정은 하지 않았다.**

---

## 1. 함수: 여러 migration에서 CREATE OR REPLACE로 덮어쓰기

### 1.1 `py_get_opcode_size`

| 순서 | 파일 | 역할 |
|------|------|------|
| 1 | `20260114230000_ceval_core.sql` | 최초 정의 (현재: Python 3.11 uniform 2-byte) |

**정리:** 한 함수 정의가 3개 파일에 나뉘어 있고, “최종 형태”는 마지막 파일에만 있음. 지향에 맞추려면 정의는 한 곳(예: ceval_core)에만 두고 그 파일을 직접 수정하는 방식이어야 함.

---

### 1.2 `py_eval_frame`

| 순서 | 파일 | 추가/변경 내용 |
|------|------|----------------|
| 1 | `20260114232000_ceval_eval_frame.sql` | **py_eval_frame** 전체 정의 (LOAD_CONST, STORE_NAME, LOAD_NAME, BINARY_ADD/SUBTRACT/MULTIPLY, COMPARE_OP, JUMP_*, POP_TOP, RETURN_VALUE 등 모든 opcode 분기) |

**정리:** 한 함수가 8개 파일에서 CREATE OR REPLACE로 이어서 “확장”되고 있음. 지향에 맞추려면 `py_eval_frame`의 최종 본문은 한 파일(예: ceval_eval_frame)에만 두고, opcode 분기 추가 시 그 파일을 직접 수정하는 방식이어야 함.

---

### 1.3 `py_object_richcompare`

| 순서 | 파일 | 역할 |
|------|------|------|
| 1 | `20260114236000_tp_richcompare_slot.sql` | 최초 정의 (디스패치 + 타입별 호출) |
| 2 | `20260114240000_compare_op.sql` | reflected op 로직 추가 (NotImplemented 시 반대 타입 시도) |

**정리:** richcompare “정의”가 36000과 40000 두 곳에 나뉘어 있음. 반영 로직 추가는 36000 쪽 정의를 직접 수정하는 편이 지향에 맞음.

---

### 1.4 `py_unicode_richcompare`, `py_long_richcompare`

| 순서 | 파일 | 역할 |
|------|------|------|
| 1 | `20260114236000_tp_richcompare_slot.sql` | 최초 정의 (Py_LT 등 일부 op) |
| 2 | ~~237000_tp_richcompare_full_ops~~ | 제거됨. 236000 한 곳에서 전 구간 op 지원.

**정리:** 타입별 richcompare 구현이 36000 → 37000에서 덮어쓰기로 “확장”됨. 지향에 맞추려면 36000(또는 37000) 한 곳에서만 정의하고 그 파일을 직접 수정하는 방식이어야 함.

---

### 1.5 `py_call_cfunction`

| 순서 | 파일 | 역할 |
|------|------|------|
| 1 | `20260114233000_ceval_opcodes_basic.sql` | 최초 정의 (현재: args 위주, kwargs 처리 포함 여부는 해당 파일 참고) |
| ~~2~~ | ~~tp_call_kwargs~~ | 별도 파일은 제거·병합됨. |

**정리:** 호출 규약 확장이 새 migration으로 덮어쓰기. 지향에 맞추려면 33000(또는 34500) 한 곳 정의를 직접 수정하는 방식이어야 함.

---

### 1.6 `py_opcode_CALL_FUNCTION`

| 순서 | 파일 | 역할 |
|------|------|------|
| 1 | `20260114233000_ceval_opcodes_basic.sql` | **py_opcode_CALL_FUNCTION** 정의 (py_object_call 호출 형태는 해당 파일 참고) |

**정리:** CALL_FUNCTION 정의는 `233000_ceval_opcodes_basic` 한 파일에 둠.

---

### 1.7 `py_object_call`

| 순서 | 파일 | 역할 |
|------|------|------|
| 1 | `20260114234000_tp_call_slot.sql` | 최초 정의 (obj_id, args 2인자) |
| ~~2~~ | ~~234500_tp_call_kwargs~~ | 제거·병합됨. 234000에서 call 규약 정의.

**정리:** `py_object_call` 정의는 `234000_tp_call_slot` 한 곳에 둠.

---

### 1.8 `py_dict_get_item`, `py_dict_set_item`

| 순서 | 파일 | 역할 |
|------|------|------|
| 1 | `20260114235000_tp_hash_slot.sql` | 최초 정의 (hash 기반, 키 동등은 tp_name 등으로 비교) |
| 2 | `20260114236000_tp_richcompare_slot.sql` | py_object_richcompare_eq 사용하도록 재정의 (키 동등을 richcompare로 통일) |

**정리:** dict API “정의”가 35000 → 36000에서 덮어쓰기로 바뀜. 지향에 맞추려면 한 파일에서만 정의하고 그 파일을 직접 수정하는 편이 맞음.

---

### 1.9 `py_builtin_abs`

| 순서 | 파일 | 역할 |
|------|------|------|
| 1 | `20260114225000_builtin_functions.sql` | 최초 정의 (단순 래퍼 등) |
| 2 | `20260114235500_nb_absolute_slot.sql` | py_object_absolute 디스패치 사용하도록 재정의 |

**정리:** builtin 구현이 25000 → 35500에서 덮어쓰기. 지향에 맞추려면 25000(또는 35500) 한 곳 정의를 직접 수정하는 방식이어야 함.

---

## 2. 테이블: 나중 migration에서 ALTER TABLE로 컬럼 추가

### 2.1 `py_type_object`

| 파일 | 내용 |
|------|------|
| `20260114220000_python_object_schema.sql` | 최초 CREATE TABLE (tp_call, tp_hash, tp_richcompare 등 포함) |
| `20260114226000_type_method_slots.sql` | ADD COLUMN tp_as_sequence, tp_as_mapping; DROP COLUMN IF EXISTS tp_as_sequence_sq_length, tp_as_mapping_mp_length |
| `20260114235500_nb_absolute_slot.sql` | ADD COLUMN tp_as_number |

**정리:** 타입 객체 스키마가 220000에 있고, 260000·35500에서 “확장”으로 컬럼을 추가함. 지향에 맞추려면 220000(또는 타입 스키마를 한 번에 정의하는 파일 하나)에 필요한 컬럼을 처음부터 넣고, 나중에는 그 파일만 수정하는 방식이 맞음.

---

### 2.2 `py_number_methods`

| 파일 | 내용 |
|------|------|
| `20260114235500_nb_absolute_slot.sql` | CREATE TABLE py_number_methods (nb_absolute 등) |
| `20260114238000_binary_add.sql` | ADD COLUMN IF NOT EXISTS nb_add |
| `20260114238500_binary_subtract.sql` | ADD COLUMN IF NOT EXISTS nb_subtract |
| `20260114239000_binary_multiply.sql` | ADD COLUMN IF NOT EXISTS nb_multiply, sq_repeat 관련 |

**정리:** number method 스키마가 35500에서 생성된 뒤, 38000·38500·39000에서 ALTER로 컬럼이 추가됨. 지향에 맞추려면 py_number_methods 정의를 한 파일에 모으고, 컬럼 추가 시 그 파일을 직접 수정하는 편이 맞음.

---

### 2.3 `py_sequence_methods`

| 파일 | 내용 |
|------|------|
| `20260114226000_type_method_slots.sql` | CREATE TABLE py_sequence_methods (sq_length 등) |
| `20260114238000_binary_add.sql` | ADD COLUMN IF NOT EXISTS sq_concat |
| `20260114239000_binary_multiply.sql` | ADD COLUMN IF NOT EXISTS sq_repeat |

**정리:** sequence method 스키마가 260000에서 생성된 뒤, 38000·39000에서 ALTER로 컬럼 추가. 지향에 맞추려면 한 파일에서 정의하고 그 파일을 직접 수정하는 방식이어야 함.

---

### 2.4 `py_dict_entry`

| 파일 | 내용 |
|------|------|
| `20260114220000_python_object_schema.sql` | CREATE TABLE 시 이미 me_hash bigint 포함 |
| `20260114235000_tp_hash_slot.sql` | ADD COLUMN me_hash IF NOT EXISTS, backfill, SET NOT NULL, 인덱스 생성 |

**정리:** 220000에 이미 me_hash가 있으면 35000의 ADD COLUMN IF NOT EXISTS는 중복/조건부 확장 패턴. “정의는 한 곳에서”라는 지향에 맞추려면 me_hash는 220000에서만 다루고, backfill/인덱스는 필요 시 같은 파일 또는 명확히 “데이터/인덱스만” 다루는 곳에서 처리하는 편이 일관됨.

---

## 3. 요약

- **함수:** `py_get_opcode_size`, `py_eval_frame`, `py_object_richcompare`, `py_unicode_richcompare`/`py_long_richcompare`, `py_call_cfunction`, `py_opcode_CALL_FUNCTION`, `py_object_call`, `py_dict_get_item`/`py_dict_set_item`, `py_builtin_abs`가 **두 개 이상의 migration에서 CREATE OR REPLACE로 덮어쓰기**되며 정의가 여러 파일에 나뉘어 있음.
- **테이블:** `py_type_object`, `py_number_methods`, `py_sequence_methods`, `py_dict_entry`가 **나중 migration에서 ALTER TABLE(ADD COLUMN 등)로 확장**되거나, 조건부 추가로 스키마가 나뉘어 있음.

지향대로 하려면:  
- **함수**는 “이 함수의 최종 정의를 소유하는 migration 하나”를 정하고, 변경 시 그 파일만 직접 수정.  
- **테이블**은 “이 테이블의 스키마를 소유하는 migration 하나”를 정하고, 컬럼 추가/변경 시 그 파일만 직접 수정.

이 문서는 **수정 없이** 위와 같이 “잘못된(지향과 맞지 않는) 부분”만 나열·정리한 것이다.
