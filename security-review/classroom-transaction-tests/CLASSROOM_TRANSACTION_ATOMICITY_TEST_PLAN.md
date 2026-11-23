# Classroom Transaction Atomicity and Failure-Injection Test Plan

**Status:** Review-only test protocol; not executable SQL  
**Scope:** Synthetic fixture and transaction-function drafts only  
**Target environment:** A fresh, dedicated, disposable local/CI PostgreSQL database  
**Prohibited targets:** Hosted Supabase, shared databases, `main`, `cloud-test`, and the existing game-scoring fixture

## 1. Purpose

Prove that each trusted classroom mutation is atomic: either every required database change commits, or none of the changes from that operation remain.

The tests deliberately force failures between steps that would otherwise be separate writes. They must demonstrate rollback of earlier writes when a later step fails.

This plan does not authorize running tests, installing triggers, changing hosted objects, or deploying functions.

## 2. Test-only failure injection

Use a disposable-database-only failure injector. Preferred approach:

1. Add a small test-only trigger function in the isolated test schema.
2. Attach narrowly scoped triggers to the synthetic tables involved in the scenario.
3. Have the trigger raise a deliberate exception only when a session-local custom setting matches its configured failpoint, for example `temmy_test.failpoint`.
4. Set the failpoint with `SET LOCAL` inside the test transaction immediately before calling the function.
5. Clear it or let the transaction end before running the next scenario.

The injector must be inert when no matching failpoint is set. It must not be included in production migrations, deployed functions, browser code, or the eventual gateway implementation.

Alternative: create test-only function variants with explicit failpoint parameters. Do not add a hidden production parameter or production GUC hook merely to support tests.

Each injected exception must be caught outside the function call's transaction boundary (for example, by a test harness savepoint or an exception-catching test block). After catching it, query the fixture tables and compare them with the exact pre-call snapshot.

## 3. Required failure scenarios

### A. Activity score update and point-ledger insertion

Use a synthetic activity record with a known score and a student with a known ledger balance.

| Test | Injected failure point | Required post-failure state |
|---|---|---|
| A1 | After the proposed ledger entry is inserted, when the activity-record update is attempted | No new ledger entry; activity score, status, completion time and notes unchanged |
| A2 | After the activity record has been updated, when the success-audit row is inserted | No new ledger entry; activity record fully restored to its pre-call values; no success-audit row; no completed request result |
| A3 | After the success-audit row is inserted, when the idempotency request is marked completed | No ledger entry, activity update, audit row, or completed request remains |

For A1, the injected failure should be raised by a test-only trigger on the activity-record UPDATE, so the earlier ledger INSERT has already occurred inside the function transaction.

For A2, fail the audit INSERT after the activity record and any required ledger delta have been written.

For A3, fail the final request-completion UPDATE after the audit insert. This checks that the audit row does not survive if the operation cannot finish its idempotency record.

Also test a score decrease where the requested reduction exceeds the student's available balance. The score record must still store the teacher-assigned score, while the ledger records only the permitted clamped deduction. If a later write fails, both the score update and any actual debit must roll back together.

### B. Point-ledger debit and marketplace purchase-history insertion

Use a student with sufficient points and a reward with finite stock.

| Test | Injected failure point | Required post-failure state |
|---|---|---|
| B1 | After the point debit is inserted, when the purchase-history INSERT is attempted | No debit ledger row; no purchase row; student balance unchanged; stock unchanged |
| B2 | After the purchase row is inserted, when stock decrement is attempted | No debit ledger row; no purchase row; stock unchanged |
| B3 | After debit, purchase and stock update, when success-audit insertion is attempted | All three mutations rolled back; no audit or completed request remains |
| B4 | After audit insertion, when the idempotency request is marked completed | Debit, purchase, stock change and audit all rolled back |

Use a separate request ID for each independent test. After a deliberately failed attempt, verify that retry behaviour matches the approved request-state contract; do not assume that a rolled-back request claim is durable.

### C. Purchase-history insertion and finite-stock decrement

This is a focused assertion of the ordering and rollback boundary, not a substitute for section B.

1. Start with exactly one finite-stock item and sufficient student balance.
2. Allow the purchase-history INSERT to occur.
3. Inject an exception on the reward stock UPDATE.
4. Verify that the purchase row, debit ledger row, audit row and completed request are all absent, and the stock remains exactly one.
5. Repeat with stock greater than one and verify that no partial decrement occurs.

Also test the successful path separately: one purchase creates exactly one purchase row, exactly one debit, and exactly one finite-stock decrement. A `NULL` stock value remains `NULL` for unlimited-stock rewards.

### D. Successful mutation and success-audit recording

For each operation family—award, deduction, reversal, activity scoring and marketplace purchase—inject a failure at the success-audit INSERT after the business mutation has been attempted.

Required result:
- No business mutation remains.
- No success-audit row remains.
- No completed idempotency result remains.
- The pre-call ledger balance and all affected domain rows are unchanged.

Then run the same operation without a failpoint and verify that the business mutation, audit row and completed idempotency result all commit together.

A success-audit failure must fail the whole operation. Do not silently commit a balance change without its required success audit.

## 4. State to capture before and after every test

Capture exact rows or deterministic hashes for:

- `point_transactions`: row count and rows for the target student, including IDs, signed points, action type, source and reversal link.
- `student_activity_records`: every field changed by the operation.
- `marketplace_rewards`: active state and stock.
- `purchases`: rows for the request ID and target student.
- `transaction_requests`: operation, actor, payload hash, state and stored result for the request ID.
- `transaction_audit`: rows for the request ID and operation.
- Derived student balance from the signed ledger.

Do not rely only on the frontend's displayed balance. Compare the ledger sum and all affected records directly in the isolated fixture.

## 5. Pass/fail rules

A test passes only when all of the following are true:

1. The injected failure is observed at the intended point—not earlier or later.
2. The function call reports failure to its caller.
3. Every write made by that function call is rolled back.
4. No partial purchase, debit, stock decrement, activity score, reversal, audit row or completed request remains.
5. A subsequent clean request can proceed and produces exactly one valid mutation.
6. The same-key retry behaviour is consistent with the final idempotency contract.

Any partial state is a release-blocking failure. Do not repair partial test rows manually and call the test passed; preserve the failing evidence, reset the disposable fixture, and investigate the transaction boundary.

## 6. Important distinction: successful-operation audit vs rejected-operation audit

V2 uses two intentional transaction outcomes:

- **Successful mutation:** business writes, success audit and completed request result commit together. Any later write/audit failure propagates and rolls back the entire operation.
- **Expected business rejection:** no business mutation is applied; a structured rejection result, request status `rejected`, and one safe rejection-audit row commit together. The function returns normally rather than raising an exception.

An identical retry of a rejected request must replay the stored rejection without adding another audit row. A changed actor, operation or payload for the same request UUID is a key-binding conflict and must not execute. Retryable stale-membership, deadlock and serialization failures remain exceptions so the request claim rolls back and the caller can retry the same request ID and payload.

The disposable suite must test all three paths separately: successful atomicity, durable expected rejection, and unexpected/retryable rollback.

## 7. Preconditions before execution

Do not execute this plan until all of these gates are satisfied:

- A fresh disposable database/cluster has been positively identified; do not use the existing local classroom database without separate explicit approval.
- Fixture schema and seed scripts have passed static review.
- Function drafts compile in the disposable environment.
- SECURITY DEFINER ownership, nested role-context checks, fixed search paths and EXECUTE ACLs have been verified.
- The request-state contract defines success replay, durable rejected replay, payload mismatch, concurrent duplicate requests and retryable rollback.
- Each failpoint has been shown to fire after the intended preceding mutation.
- The test harness can catch an injected exception while preserving the outer test session for post-failure inspection.
- The database version is recorded and the SHA-256 helper is confirmed.
- The test database contains synthetic data only and has no hosted credentials or network route to production.

## 8. Evidence to retain

For every scenario, retain:
- PostgreSQL version and fixture commit.
- Function draft revision/hash.
- Exact failpoint and SQLSTATE/message.
- Before/after row snapshots or deterministic hashes.
- Confirmation that the operation's writes were fully rolled back.
- Follow-up clean-retry result.
- Any deviation from the expected outcome.

Do not publish secrets, connection strings, access tokens or personal student data in test evidence.

## 9. Added review-only failpoint draft

`CLASSROOM_TRANSACTION_AUDIT_FINALIZATION_FAILURE_TESTS.sql.txt` now defines a disposable-schema-only trigger failpoint and two award-operation cases:

- Raise during the success-audit INSERT after the award ledger INSERT; assert the ledger mutation and request claim both roll back.
- Raise during the request finalization UPDATE after the ledger and audit writes; assert all three writes, including the request claim, roll back.

The failpoint is controlled by a session-local custom setting and is installed inside a transaction so the trigger objects are removed by the final rollback. It is not part of any V2 business function or production migration.

This draft covers only the award operation's audit and finalization boundaries. It does not yet cover the intermediate-write failpoints for activity scoring and marketplace purchase, nor audit/finalization failures for deduction, reversal and purchase. Those remain required before claiming broad operation-family atomicity coverage.

## 10. Current status

This remains a test protocol and review-only draft. No failpoint triggers have been created in a database, no SQL has been run, and no atomicity claim has been validated. The new failpoint file has only been committed as text on the isolated review branch. The SQL function drafts, smoke tests, edge-case tests, ACL assertions and concurrency protocol remain unexecuted until the disposable-environment gates above are satisfied.
