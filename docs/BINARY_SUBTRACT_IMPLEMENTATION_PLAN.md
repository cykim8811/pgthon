# BINARY_SUBTRACT 구현 단계 계획 (BINARY_ADD와 동일 방식)

CPython PyNumber_Subtract는 **nb_subtract만** 사용하며, sq_* 폴백은 없다.  
BINARY_ADD와 같은 “스키마 확장 → 타입별 함수 → 디스패치 → 슬롯 등록 → py_object_* → opcode → eval_frame” 순서로 진행한다.

---

## 1. 작업 식별 및 의존 관계

| ID | 작업 | 의존 작업 | 비고 |
|----|------|-----------|------|
| **A** | `py_number_methods`에 `nb_subtract regproc` 컬럼 추가 (ALTER) | 없음 | 238000에서 nb_add 추가한 테이블에 컬럼만 추가 |
| **C** | `py_long_nb_subtract(left_id, right_id)` 함수 정의 | 없음 | int - int만, 나머지 NotImplemented |
| **F** | `py_object_subtract_via_nb(left_id, right_id)` 정의 | **A** | left의 nb_subtract(left,right), NotImplemented 시 right의 nb_subtract(right,left) |
| **I** | 슬롯 등록: int의 `nb_subtract` 설정 | **A, C** | |
| **H** | `py_object_subtract(left_id, right_id)` 정의 (PyNumber_Subtract 대응) | **F** | via_nb만 호출, 실패 시 TypeError |
| **J** | `py_opcode_BINARY_SUBTRACT(frame_id)` 정의 | **H** | stack pop/push + py_object_subtract 호출 |
| **K** | `py_eval_frame`에 opcode 24 분기 추가 | **J** | 24일 때 py_opcode_BINARY_SUBTRACT 호출 |

참고: str은 뺄셈 미지원이므로 py_unicode_nb_subtract 없음. sq_* 폴백 없음.

---

## 2. CPython 동작

- `PyNumber_Subtract(v, w)` = `binary_op(v, w, nb_subtract, "-")` → BINARY_OP1 → 실패 시 `binop_type_error(v, w, "-")` 만.  
- `binary_op1` 호출 순서: v.op(v,w), w.op(v,w) (서브클래스 우선은 BINARY_ADD와 동일하게 생략 가능).

---

## 3. 마이그레이션 배치

| 마이그레이션 | 포함 작업 | 설명 |
|--------------|-----------|------|
| `20260114238500_binary_subtract.sql` | A–K 통합 | nb_subtract 컬럼·py_long_nb_subtract·py_object_subtract·py_opcode_BINARY_SUBTRACT·eval_frame opcode 24 분기 한 파일에 반영 |
