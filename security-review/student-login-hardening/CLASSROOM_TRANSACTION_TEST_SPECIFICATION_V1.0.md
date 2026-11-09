# Classroom Transaction Test Specification v1.0

**Status:** Approved business rules; review-only test specification  
**Branch:** `security-review/student-login-hardening`  
**Scope:** Trusted teacher point transactions, activity scoring, marketplace purchases, idempotency, authorization, auditability, and concurrency.  
**Environment:** Disposable PostgreSQL CI/local database only. No hosted Supabase connection.  
**Explicit exclusions:** This is not a migration, deployment plan, or authorization to change Supabase. Do not modify `main` or `cloud-test`.

## 1. Purpose

Specify the business behaviour and acceptance tests for moving sensitive Classroom ledger operations out of browser-controlled writes and into a narrow trusted transaction layer. The ledger remains the source of truth for point balances. The browser may request an operation but may not directly create point transactions or alter protected scoring fields.

The existing game platform is retired from this plan. Classroom security and launch readiness are the priority. Temmy Gateway is a future integration boundary; this specification does not authorize implementing or deploying it.

## 2. Approved business rules

### 2.1 Teacher awards

- Only an authenticated teacher who owns the student's active class may award or deduct points.
- Awards are positive whole numbers.
- A configurable maximum award amount must be enforced by the trusted transaction layer. The configuration value and its operational owner must be decided before production implementation; no fixed numeric cap is invented by this specification.
- A request above the configured maximum is rejected without a ledger write.
- The server derives the acting teacher identity from the trusted authenticated request context; it must not trust a teacher ID supplied by the browser.
- Award and deduction requests are idempotent. Replaying the same request ID and same payload returns the recorded outcome; reusing the request ID with a different payload is rejected.

### 2.2 Deductions and balance clamping

- A deduction cannot reduce a student's available balance below zero.
- If the requested deduction exceeds the available balance, deduct only the available balance and record the actual deducted amount.
- If the available balance is zero, return a zero-balance/no-op outcome and create no point transaction.
- Balance calculation is derived from the ledger; no independently editable balance is authoritative.
- Concurrent deductions must serialize safely so that the total actual deduction never exceeds the balance available at the time each operation is applied.

### 2.3 Undo

- Undo means a full reversal of the original eligible transaction, not a partial reversal.
- A transaction may be reversed at most once.
- The reversal must reference the original transaction and be recorded as a compensating ledger entry; do not edit or delete the original ledger row.
- If the student has spent some of the awarded points and the full reversal would take the balance below zero, reject the undo completely. Do not partially reverse and do not create a negative balance.
- Undo must be authorized to the teacher who is permitted to reverse the original action under the final ownership policy.
- Concurrent/repeated undo requests must not create multiple reversals.

### 2.4 Activity scoring

- The activity record stores the teacher-assigned score.
- Point transactions record the change (delta) from the previous score, not the new total score.
- Example: score 6 to 9 produces +3; score 9 to 5 requests -4.
- A downward score change is subject to the approved deduction clamp: record only the points actually deducted if the student's available balance is lower than the requested deduction. The activity record still stores the teacher-assigned score.
- The activity record update and corresponding ledger entry must be atomic: both commit or neither commits.
- A zero delta or zero actual deduction creates no zero-value point transaction.
- Teacher must own the activity's class and the student's class relationship must be valid.
- Duplicate activity submission behaviour is not changed by this specification. Preserve the current verified behaviour until its exact deployed semantics are established. Include duplicate-submission tests; do not add a unique constraint on (activity_id, student_id) in this design.

### 2.5 Marketplace purchases

- Each student's purchase is processed independently; a failure for one student does not roll back another student's successful purchase.
- Each individual student's purchase, points deduction, purchase-history row, and finite-stock decrement (when applicable) must be atomic.
- A student with insufficient points is rejected without a points deduction, purchase row, or stock decrement.
- A student may not be charged twice for a retried request. Each per-student purchase uses a stable idempotency key and payload binding.
- Reward must belong to the acting teacher and be active at the time of purchase.
- A deactivated reward is unavailable for new purchases, but its purchase history and historical reward description/name remain preserved.
- Stock model: `NULL` means unlimited stock; a non-negative finite value means limited stock. A finite stock decrement and the purchase must occur atomically. If stock is zero, reject without charging points. Concurrent purchases must not oversell.
- For a multi-student selection, return an independent result for each student (e.g. purchased, insufficient_balance, out_of_stock, reward_unavailable, invalid_student, or retry_result). Do not use all-or-nothing batch semantics.

## 3. Shared transaction and security requirements

1. **Trusted identity:** Teacher identity comes from verified server-side authentication context. Never accept client-selected teacher identity as authority.
2. **Narrow entrypoints:** Expose only specific business operations; do not expose arbitrary table writes or arbitrary RPC names.
3. **Least privilege:** Browser roles must not directly INSERT into `point_transactions` or UPDATE protected `student_activity_records` columns. Exact grants must be designed only after full caller inventory and verified deployed ACL/schema metadata.
4. **Ownership checks:** Every operation checks teacher ownership, student-to-class membership, activity/reward ownership, and active-state requirements inside the trusted transaction boundary.
5. **Ledger integrity:** Use append-only compensating entries; never rewrite/delete prior point history to simulate corrections.
6. **Idempotency:** Store a unique request identity scoped to the operation/actor and bind it to a canonical payload hash. Same key/same payload returns the stored result. Same key/different payload is rejected.
7. **Concurrency:** Lock the relevant student/reward/request rows or use equivalent serializable/atomic conditional updates. Never rely on a browser-read balance.
8. **Atomicity:** All related state changes for one business operation commit together.
9. **Audit:** Successful business changes and their audit records commit atomically. Rejected attempts may require a separate safe audit path; do not claim a rolled-back transaction can preserve its own audit insert. Do not log access codes, tokens, secrets, or unnecessary student data.
10. **No hidden negative balances:** The ledger and server response must report actual amounts. UI clamping alone is not a security control.
11. **No unverified schema assumptions:** Current production schema for marketplace rewards, purchases, request records, audit records, and purchase RPC is not present in the reviewed repository snapshot. Treat all proposed objects as synthetic test design until independently verified.
12. **No client secrets:** Service-role credentials or other privileged secrets must never be shipped to the browser.

## 4. Required test fixture model (synthetic only)

A separate classroom transaction fixture must be created; do not extend or repurpose the existing game-scoring fixture. The fixture may define synthetic versions of:

- teacher profiles, classes, and students;
- point transaction ledger;
- student activity records and class activities;
- marketplace rewards and purchase history;
- idempotency/request records;
- audit events;
- narrowly scoped test roles and transaction entrypoints.

Every fixture object must be labelled test-only. Do not present the synthetic definitions as verified production schema. Do not impose a unique (activity_id, student_id) constraint pending duplicate-semantics verification. Add only constraints required by the explicitly approved contract and clearly label assumptions.

The test harness must model the trusted Gateway identity boundary. A client must not be able to choose another teacher's identity by setting an ordinary request parameter or user-writable session variable. Any test-only identity injection must be confined to a privileged harness and documented as such; it must not become a production pattern.

## 5. Acceptance test matrix

### Authorization and privilege boundaries
- Unauthenticated/anonymous caller cannot execute transaction entrypoints.
- Authenticated browser role cannot directly insert point transactions.
- Authenticated browser role cannot update protected score, student, teacher, activity, or points fields.
- Teacher A cannot award/deduct for Teacher B's student.
- Teacher A cannot score an activity outside Teacher A's class.
- Teacher A cannot purchase or modify Teacher B's reward.
- A browser-supplied teacher ID cannot override trusted actor identity.
- Gateway/test execution role has only the privileges needed for the transaction functions.

### Awards and deductions
- Positive integer award within configured cap succeeds once.
- Zero, negative, fractional/non-integer, malformed, and above-cap award requests are rejected.
- Repeated same request key and payload does not duplicate the ledger entry.
- Same request key with changed amount/student/reason is rejected.
- Deduction below balance deducts requested amount.
- Deduction above balance deducts only the remaining balance.
- Deduction at zero balance returns no-op and creates no zero-value transaction.
- Concurrent deductions never produce a negative balance or over-deduct.

### Undo
- Full undo succeeds when the full reversal is affordable.
- Second undo of the same original transaction is rejected/idempotently returns the first result.
- Undo is rejected completely when the student has spent enough points that full reversal would make the balance negative.
- Concurrent undo attempts create at most one reversal.
- Original ledger row remains unchanged.

### Activity scoring
- Score increase writes the positive delta and updates the activity record atomically.
- Score decrease writes the actual clamped deduction and updates the teacher-assigned score atomically.
- Zero delta creates no point transaction.
- Forced ledger failure rolls back the activity record update.
- Forced activity-record failure leaves no ledger transaction.
- Duplicate submission scenarios are tested against documented current semantics; no uniqueness constraint is added by this specification.
- Concurrent score changes serialize and leave a consistent activity record and ledger.

### Marketplace
- Each selected student receives an independent outcome.
- One student's insufficient balance does not cancel another student's successful purchase.
- Successful purchase deducts points and writes purchase history atomically.
- Failed purchase does not deduct points or decrement stock.
- `NULL` stock permits purchases without decrement.
- Finite stock decrements exactly once per successful purchase.
- Stock zero rejects purchase.
- Concurrent purchases cannot oversell finite stock.
- Deactivated reward rejects new purchase and retains historical purchase rows.
- Retry of a successful student's purchase does not charge twice or decrement stock twice.
- Same idempotency key with altered reward/student/payload is rejected.

### Audit and failure handling
- Successful operation and success audit event commit together.
- Failed/rolled-back operation leaves no success audit event.
- Rejected-operation telemetry, if implemented, does not expose secrets or rely on a rolled-back insert.
- Unknown outcome can be resolved by retrying/querying the same idempotency key; clients must not invent a new key after a timeout.

## 6. Test execution and release gates

- Run only against disposable local PostgreSQL or isolated CI PostgreSQL with synthetic data and no hosted Supabase credentials/network.
- Preserve existing game-scoring workflows unchanged; classroom transaction tests must have a separate fixture and workflow.
- Test sequential, failure-injection, privilege, concurrency, and idempotency behaviour.
- Record PostgreSQL version and test command/output.
- Static SQL review and passing disposable tests do not authorize production deployment.
- Before any production change, separately verify actual deployed schema, constraints, triggers, effective grants, all application callers, and current marketplace function/table definitions.
- Production rollout requires a separate explicit approval of exact migration/function/grant changes and rollback plan.

## 7. Known unresolved implementation inputs

- Configured maximum teacher award amount and who may change it.
- Verified deployed definitions/columns/constraints for marketplace rewards and purchases.
- Exact current duplicate activity submission semantics and all deployed callers.
- Trusted Gateway-to-database identity propagation and role model.
- Exact audit retention and rejected-attempt telemetry policy.
- Whether the deployed system permits negative point transactions and any legacy transaction types beyond those seen in the reviewed frontend.

## 8. Approval record

The user approved all three final business-rule recommendations on 2026-11-09:
- configurable maximum for positive whole-number teacher awards;
- unlimited/finite stock with atomic stock and purchase handling, deactivation preserving history;
- preserve existing duplicate activity submission behaviour pending verification, with tests and no new uniqueness constraint.

This document is a test specification only. It is not a production schema or migration.
