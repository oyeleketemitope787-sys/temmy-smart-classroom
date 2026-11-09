# Expected Rejection and Idempotency Policy

**Status:** Approved business/security design  
**Approval date:** 2026-11-09  
**Scope:** Temmy Smart Classroom trusted transaction layer and future Temmy Gateway integration  
**Implementation status:** Not implemented; review documentation only

## 1. Purpose

Expected business rejections must be stable, traceable outcomes. They must not be confused with infrastructure failures, and they must never partially apply a business mutation.

## 2. Durable expected business rejections

The trusted transaction layer must return a structured result with status `rejected` for expected business-rule outcomes, including:

- Insufficient available points for a purchase or other non-clamping operation.
- Reward inactive or otherwise unavailable for a new purchase.
- Award request above the configured maximum.
- Out-of-stock reward.
- Other explicitly enumerated, deterministic business-rule failures approved for the operation.

For a durable expected rejection, the request outcome and a safe rejection-audit record must commit together. No business mutation may occur: no point-ledger entry, balance change, purchase history row, stock decrement, or activity-score mutation.

The stored result should include a stable machine-readable rejection code and only the minimum safe context needed to explain the outcome. Do not store access tokens, secrets, or unnecessary student data in audit details.

## 3. Idempotency behaviour

Every mutation request uses a request ID scoped to the operation and verified actor, and bound to a canonical payload hash.

| Retry condition | Required behaviour |
|---|---|
| Same scope, request ID, and canonical payload | Return the previously stored result, including the same durable rejection; do not re-evaluate or repeat the mutation. |
| Same scope and request ID, different canonical payload | Reject as an idempotency-key reuse conflict; do not execute the new payload. |
| New request ID | Evaluate as a new request under current business state. |

A stored rejection remains the result for that request ID even if the business state later changes. A caller wishing to try again after points are added or stock is replenished must submit a new request ID.

Canonicalization must be deterministic and operation-specific. It must include all fields that can change the meaning of the request and exclude transport-only fields. Hash algorithm availability and exact canonical encoding remain implementation-verification items.

## 4. Unexpected failures and retryable conflicts

Unexpected database or system failures must raise/propagate as failures and roll back the entire transaction. Do not convert arbitrary exceptions into ordinary business rejections.

Examples include database unavailability, unexpected constraint violations, internal programming errors, and failures while writing required success or rejection audit records.

Concurrency conflicts that mean the request must be retried against fresh state (for example, stale class membership detected during the approved class-before-student lock/revalidation protocol) must be distinguished from durable business rejections. They should return a retryable conflict/error and must not be permanently stored as a final business outcome under the request ID. Deadlocks and serialization failures should follow an explicit retry policy; they must not be silently mapped to insufficient balance or another business rejection.

## 5. Transaction and audit guarantees

- Claim or inspect the idempotency request within the transaction using concurrency-safe uniqueness/locking.
- For a durable expected rejection, persist the final rejected result and its safe audit event atomically.
- For a successful mutation, persist the business changes, final request result, and success audit atomically.
- If any required write fails, the transaction must roll back.
- Avoid catch-all exception handlers that suppress failures or leave ambiguous request states.
- A request ID reused with a different payload must never execute the second payload. Whether such key-reuse attempts receive a separate security audit event, and how that event is recorded without compromising transaction semantics, remains an implementation detail to resolve.

## 6. Initial expected rejection codes

The following codes are illustrative stable identifiers; the final API contract may refine naming while preserving the semantics:

- `INSUFFICIENT_POINTS`
- `AWARD_LIMIT_EXCEEDED`
- `REWARD_INACTIVE`
- `OUT_OF_STOCK`
- `IDEMPOTENCY_KEY_REUSED`

A retryable stale-state conflict must use a distinct retryable error category, not one of these durable rejection codes.

## 7. Required tests

The disposable test harness must verify:

1. Insufficient-points rejection is stored; no ledger debit or purchase is created.
2. Repeating the same request ID and payload returns the identical stored rejection, even after the student's balance changes.
3. A new request ID after the balance changes is evaluated against the new balance.
4. Above-cap award rejection is stored; no award ledger row is created.
5. Inactive-reward and out-of-stock rejections are stored; no debit, purchase, or stock decrement occurs.
6. Same request ID with a different payload is rejected and the alternate operation is not executed.
7. Concurrent duplicate requests with the same ID and payload produce one final outcome and no duplicate mutation.
8. Required audit-write failure rolls back both the request outcome and any business mutation.
9. Unexpected database/system errors propagate and roll back; they are not converted into business rejections.
10. Retryable stale-membership/concurrency conflicts are not persisted as durable business rejections and can be retried with fresh state.

## 8. Implementation gates

Before any execution or deployment:

- Reconcile this policy with the production schema and every existing caller.
- Revise the Phase 1–3 SQL drafts to follow the approved global lock order: request, sorted class row(s), student, operation-specific rows, then writes.
- Verify PostgreSQL/Supabase behaviour for nested SECURITY DEFINER functions, role identity, hash function availability, exception handling, and transaction rollback.
- Define the final rejection response schema and retryable error mapping.
- Resolve the separate audit treatment for idempotency-key reuse attempts.
- Run the full test suite only in a newly provisioned disposable database/cluster after explicit approval.

## 9. Safety boundary

This document records approved design only. It does not authorize SQL execution, hosted database changes, grants/revokes, migrations, Edge Function deployment, or changes to the classroom application. The production `main` branch and shared `cloud-test` branch remain out of scope.

## 10. Zero-balance deduction no-op audit — approved

**Approval date:** 2026-11-09

When a valid deduction request is made while the student's available balance is already zero:

- Treat the operation as an accepted no-op, not as a business rejection.
- Do not create a point-ledger transaction and do not change the balance.
- Record a lightweight audit event indicating that the deduction was attempted but no points were available.
- The audit event must be safely attributable to the verified actor and request, and should include only minimal necessary context.
- If the audit write is required for this outcome and fails, propagate the failure rather than claiming the no-op was successfully recorded.
- An idempotent retry with the same request ID and payload must return the same stored no-op outcome and must not create duplicate audit entries.

This is distinct from a deduction request made when a positive balance exists but the requested amount exceeds it: the approved clamp-to-available-balance rule still applies in that case.

The exact audit event name, fields, retention, and implementation are to be defined during implementation review. This approval does not authorize execution or deployment.
