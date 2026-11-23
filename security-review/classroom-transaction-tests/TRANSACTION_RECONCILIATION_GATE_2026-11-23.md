# Classroom Transaction Reconciliation Gate — 2026-11-23

**Status:** Reconciliation baseline; design/documentation only. No SQL is authorized by this file.
**Branch:** `security-review/student-login-hardening`
**Scope:** Disposable PostgreSQL transaction fixture only. Production `main`, shared `cloud-test`, hosted Supabase, and the SGIS local Supabase stack are out of scope.

## Confirmed approved behaviour

1. Global lock order for request-based operations:
   `idempotency request → sorted class row(s) → student row → operation-specific row(s) → business/result/audit writes`.
2. Student class membership is first read without a lock only to discover the class ID. Lock the class, then the student, re-read membership, and validate active state and teacher ownership while locks are held. A changed membership is a retryable conflict, not a durable business rejection.
3. Manual teacher award default cap is 50 points per individual award, enforced from protected configuration. Above-cap requests reject in full; no truncation or ledger write.
4. Expected business rejections are durable idempotent outcomes: stable structured `rejected` result and safe rejection audit commit together, with no business mutation. Same-key/same-payload retry replays the stored result. Changed actor, operation, or payload cannot execute.
5. Unexpected database/system failures propagate and roll back the request, audit, and business writes. Do not use catch-all exception handling to turn system failures into rejections.
6. Zero-balance deduction is an accepted no-op: no ledger row and no balance change, but one lightweight attributable audit event and a completed idempotent result. A same-key retry must not create a second audit event.
7. A positive-balance deduction larger than the balance is clamped to the available balance. This is distinct from a zero-balance no-op.
8. Preserve activity duplicate-submission semantics; do not add a unique `(activity_id, student_id)` constraint.
9. Marketplace purchase remains one student per request, one transaction per student, with the existing purchase snapshot and stock-locking rules preserved.

## Static findings from the current branch

- The fixture schema configuration is already seeded with `maximum_teacher_award = 50`.
- The inspected seed file contains 50-point opening balances; no obsolete 100-point award-cap seed was found. The README statement claiming the seed still contains 100 must be corrected after a full repository-wide search.
- The edge-case script tests the 50-point award cap and zero-balance no-op, but its current harness expects an exception for above-cap awards and does not assert the approved durable rejection/audit replay contract.
- Phase 1–3 function SQL files explicitly mark themselves superseded. Their implementations still use student-first locking and exception-based expected rejections. They must remain non-executable until replaced.
- The design document currently conflicts with the approved no-op audit rule by saying no success audit should be written for the zero-balance no-op.
- The concurrency and atomicity plans still contain obsolete exception-based rejection guidance.
- No SQL syntax, runtime, role-context, ACL, concurrency, or atomicity test has been run.

## Required implementation contract before any SQL execution

### Shared request handling
- Bind each request UUID to actor, operation, and canonical typed payload hash.
- Claim/lock the request row before business locks.
- Return stored `completed` or `rejected` outcomes on an identical retry without re-running business logic or duplicating audit.
- Reject request-key reuse with changed actor, operation, or payload.
- Keep retryable stale-membership/deadlock/serialization conflicts distinct from durable business rejections.
- Do not commit a stranded `processing` request state.

### Class/student lock helper
- Perform only a preliminary non-locking lookup to discover the student's class ID.
- Acquire the class row lock using a mode verified to conflict with deactivation, ownership changes, and transfer administration.
- Acquire the student row lock next.
- Re-read class membership; changed membership must abort/retry without persisting a final business rejection.
- Validate student/class active state and teacher ownership only after both locks are held.
- Verify PostgreSQL row-lock compatibility, FK/trigger implicit locks, and the full lock graph in the pinned disposable PostgreSQL version.

### Expected rejection transaction shape
- Enumerate stable rejection codes per operation.
- Handle only known business-rule outcomes as structured rejections.
- Persist the rejected request result and safe rejection audit atomically, with no ledger, purchase, stock, or activity mutation.
- A required audit-write failure must roll back the rejection result.
- Unexpected SQL/system errors must propagate and roll back.
- Test identical replay after underlying state changes, and new request UUID evaluation against the new state.

### Zero-balance no-op
- Complete the request with a stable no-op result.
- Write one lightweight audit event with actor, request, operation, target and minimal safe metadata.
- Do not write a zero-value ledger row.
- Required audit failure must fail the operation.
- Identical retry replays the no-op result without another audit row.

## Required test changes

1. Update smoke and edge tests to assert structured results rather than catching expected business exceptions.
2. Assert durable above-cap, insufficient-balance, inactive-reward, and out-of-stock rejection rows and safe audit rows.
3. Retry each rejection with the same key/payload after changing business state; assert exact stored rejection replay and no mutation.
4. Reuse a request key with a changed payload/actor/operation; assert no alternate operation executes.
5. Assert zero-balance no-op produces one audit, zero ledger rows, and one completed request; retry produces no duplicate audit.
6. Add lock-order race tests for class deactivation, ownership change, student transfer, activity administration, reward deactivation, and opposite-direction transfers.
7. Retain atomicity failure injection after each business write, before/after audit, and before request completion.
8. Test real denied DML and the complete nested SECURITY DEFINER role-context chain; catalog ACL inspection alone is insufficient.
9. Pin PostgreSQL image/version and verify the exact SHA-256 helper and canonicalization expression before function installation.
10. Verify no obsolete 20- or 100-point manual-award assumptions remain, while preserving unrelated values such as the synthetic activity maximum of 20.

## Execution boundary

This reconciliation file is not executable SQL and does not authorize SQL execution, role creation, grants/revokes, migrations, hosted database access, or deployment. First revise and statically review the complete fixture/function/test set. Only then request explicit approval to run it in a freshly created, isolated disposable PostgreSQL 16 container. Do not connect it to or alter any existing container, especially the SGIS Applicant Portal stack.
