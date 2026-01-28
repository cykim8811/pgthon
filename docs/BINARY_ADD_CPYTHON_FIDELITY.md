# BINARY_ADD 구현 — CPython 고증 점검

CPython `PyNumber_Add` / `binary_op1` / BINARY_ADD(opcode 23)와 Elytra 구현을 대조한 결과.

---

## 1. 맞는 부분 (고증 유지)

| 항목 | CPython | Elytra | 비고 |
|------|---------|--------|------|
| **PyNumber_Add 흐름** | (1) BINARY_OP1(nb_add) (2) 실패 시 left의 `tp_as_sequence->sq_concat(v,w)` (3) 둘 다 실패 시 `binop_type_error(v,w,"+")` | `py_object_add`: `py_object_add_via_nb` → `py_sequence_concat(left,right)` → `RAISE TypeError` | 순서 및 의미 동일 |
| **sq_concat 사용** | left(`v`)의 `sq_concat`만 사용, right의 sq_concat은 호출하지 않음 | `py_sequence_concat(left_id, right_id)` — left의 `tp_as_sequence->sq_concat`만 호출 | 동일 |
| **nb_add 재시도** | left의 nb_add 실패 시 right의 nb_add(right, left) 시도 | `py_object_add_via_nb`: left의 nb_add → NotImplemented 시 right의 nb_add(right, left) | 동일 |
| **BINARY_ADD 스택** | `TOS = TOS1 + TOS`, 즉 left=TOS1, right=TOS | `right_id := stack_pop; left_id := stack_pop; py_object_add(left, right)` | pop 순서·인자 순서 일치 |
| **타입 판별** | 슬롯/구체 타입 기반 | `py_long_object` / `py_unicode_object` 존재 여부만 사용, `tp_name` 분기 없음 | 프로젝트 원칙에 맞게 슬롯·구체 테이블만 사용 |
| **동적 슬롯 호출** | C 함수 포인터 호출 | `pg_proc`에서 (nspname, proname) 조회 후 `format('%I.%I', ...)`로 동적 호출 | 슬롯 → regproc 매핑에 맞는 구현 |

---

## 2. 의도적 축소 / 알려진 격차

### 2.1 nb_add 호출 순서 — 서브클래스 우선 없음

**CPython (binary_op1):**

```
Order: w.op(v,w)[*], v.op(v,w), w.op(v,w)
 [*] only when Py_TYPE(v) != Py_TYPE(w) && Py_TYPE(w) is a subclass of Py_TYPE(v)
```

- `w`가 `v`의 **서브클래스**일 때, **w의 nb_add(v,w)를 v의 nb_add(v,w)보다 먼저** 시도한다.

**Elytra (`py_object_add_via_nb`):**

- 항상 **left → right** 순서만 사용: left의 nb_add(left, right) → NotImplemented 시 right의 nb_add(right, left).
- `PyType_IsSubtype(Py_TYPE(w), Py_TYPE(v))`에 따른 “서브클래스 쪽을 먼저 시도”는 **구현되어 있지 않다.**

**영향:**  
서브클래스가 없거나, 같은 타입끼리만 더하는 경우에는 CPython과 동일하게 동작한다.  
서브클래스가 nb_add를 오버라이드하고 “서브클래스 인스턴스 + 부모 인스턴스” 순서로 더할 때, CPython은 서브클래스 쪽 연산을 먼저 기회를 주지만, Elytra는 단순 left→right 순서만 적용한다.

**정리:** 고증 격차. 향후 `tp_bases`/서브타입 판별을 도입하면 CPython과 동일한 호출 순서로 확장 가능.

---

### 2.2 그 외

- **float, list 등:** nb_add/sq_concat 미구현은 “지원 타입 범위 축소”이며, int/str만 지원하는 단계에서의 의도적 범위 한정이다.
- **에러 메시지:** `TypeError: unsupported operand type(s) for +: 'int' and 'str'` 형식은 CPython `binop_type_error`와 동일한 의미이며, `py_unicode_sq_concat`의 `can only concatenate str (not "X") to str`도 CPython과 같은 맥락이다.

---

## 3. 임시 구현 여부

- **타입 이름 분기:** 없음. 타입 판별은 구체 테이블/슬롯만 사용.
- **하드코딩된 타입별 분기:** 없음. int/str의 nb_add·sq_concat는 슬롯 등록으로만 연결됨.
- **TODO/FIXME/임시 주석:** BINARY_ADD 관련 마이그레이션에서 사용되지 않음.

---

## 4. 요약

| 구분 | 내용 |
|------|------|
| **고증 유지** | PyNumber_Add 흐름(nb_add → sq_concat(left) → TypeError), BINARY_ADD 스택 의미, sq_concat은 left만, nb_add fallback은 right(left, right) 호출, 타입 판별 방식(구체 테이블·슬롯만 사용) |
| **고증 격차** | nb_add 시 **“w가 v의 서브클래스일 때 w.op(v,w)를 먼저 시도”** 하지 않음. 동일/단순 타입만 있을 때는 CPython과 같음. |
| **임시방편** | 없음. 슬롯·구체 테이블 기반으로만 구현되어 있으며, 별도 임시 분기나 타입 이름 분기는 사용하지 않음. |
