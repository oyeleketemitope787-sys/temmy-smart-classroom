# Transaction Function Design — Review Only

**Status:** Design review; not executable SQL  
**Version:** 0.1  
**Branch:** `security-review/student-login-hardening`  
**Depends on:** Test Specification v1.0, Trusted Actor Identity Design, synthetic fixture schema v0.2

> This document describes a proposed implementation for the disposable classroom transaction fixture. It is not production SQL, not a Supabase migration, and not authorization to execute SQL. Names and columns refer only to the synthetic `classroom_test` fixture.

## 1. Design objectives

Implement five narrow business operations:

1. `award_points`
2. `deduct_points`
3. `reverse_transaction`
4. `score_activity`
5. `purchase_reward_for_student`

Every successful operation must:
- derive its actor from the restricted test gateway boundary;
- validate ownership and active-state relationships in the database;
- claim and bind an idempotency key;
- serialize balance changes;
- write the ledger and related records atomically;
- record a success audit event in the same transaction;
- return the actual mutation and resulting balance.

No browser role receives direct table-write access. The functions are proposed as SECURITY DEFINER routines owned by `temmy_ctest_data_owner`, with fixed search_path and schema-qualified references. Only `temmy_ctest_gateway` receives EXECUTE after the ACL test design is complete.

## 2. Shared identity and ownership validation

Each test entrypoint receives `p_actor_teacher_id` as a test-only actor parameter. It is trustworthy only because:
- the function is executable only by `temmy_ctest_gateway`;
- anon/authenticated test roles have no membership in that role;
- the privileged test runner enters the gateway role only after selecting a known synthetic teacher identity.

This is not the production API contract. A real gateway must derive the teacher ID from a verified authentication context and never trust a browser-supplied teacher UUID.

Common validation:
- actor teacher row exists;
- target student exists and is active;
- student's class exists and is active;
- class belongs to actor teacher;
- any referenced activity/reward/original transaction belongs to the same actor and valid student/class context;
- no ownership relationship is inferred from a caller-supplied teacher ID alone.

Return stable application error codes. Do not expose raw SQL errors or internal schema details.

## 3. Idempotency protocol

### 3.1 Canonical request binding

Each operation builds a canonical payload from typed business fields in a fixed order. Examples:

- award: actor, student, amount, normalized reason;
- deduction: actor, student, requested amount, normalized reason;
- reversal: actor, original transaction ID;
- activity score: actor, record ID, new score, normalized notes;
- purchase: actor, one student ID, one reward ID.

The request key is bound to:
- request UUID;
- actor teacher ID;
- operation name;
- canonical payload hash.

The database computes or verifies the hash from typed values; it must not trust a hash supplied by the browser. JSONB canonical serialization can be considered for the fixture, but the exact hash routine and extension availability must be pinned in the test environment. A fixed-field text encoding with unambiguous separators/length-prefixing is an alternative.

### 3.2 Claim and replay

Within the same database transaction:

1. Attempt to insert the request row for the UUID.
2. On conflict, select the existing row FOR UPDATE.
3. If actor, operation, or payload hash differs, return/reject `idempotency_key_reused`.
4. If status is completed, return the stored result without any mutation.
5. If status is rejected, return the stored rejection if rejected outcomes are designed to be durable.
6. If status is processing, treat it as an explicit recovery state; do not execute a second mutation blindly.
7. For a new request, perform validation and mutation, then store the final result before commit.

Because the request claim and business mutation share one transaction, a concurrent duplicate request blocks on the unique key. After the first transaction commits, the second sees the completed result. If the first transaction rolls back, the second may claim and execute the key.

### 3.3 Rejected outcomes and rollback

A database exception aborts the transaction, including an inserted idempotency row and any audit event. Therefore:
- For expected business rejections that should be replayable (e.g. above cap, insufficient funds, out of stock), return a structured rejection and commit its request result without applying business mutations.
- For unexpected internal failures, raise/rollback; no success audit or partial business change may survive.
- Rejected-attempt telemetry requiring independent durability must use a separate safe logging mechanism. Do not claim an insert in a rolled-back transaction persists.

The exact list of durable versus retryable rejections must be defined in the function contract.

## 4. Balance serialization and global lock order

### 4.1 One stable per-student mutex

All operations that can change a student's ledger balance must lock the same stable student row before reading the ledger balance. The approved global order now requires the relevant class row to be locked first.

### 4.2 Approved global order

Follow the detailed rule in TEMMY_CLASSROOM_GLOBAL_LOCK_ORDERING_RULE.md. The order is:

1. Claim/lock the idempotency request row.
2. Lock relevant class row(s), sorted by stable UUID when more than one.
3. Lock the student row.
4. Lock operation-specific rows: activity record, original transaction, then reward, as applicable.
5. Write ledger, activity, purchase, request result and audit rows.

Never acquire a later-ranked business row and then request an earlier-ranked row.

### 4.3 Safe class lookup

Do not lock the student first to discover its class. Read its class ID without a lock, lock that class, then lock the student and re-read the class ID. If it changed, abort with a retryable stale-membership/conflict result. Only after both locks are held may the function validate active status and teacher ownership.

A normal business operation must hold a class lock that conflicts with class deactivation, ownership change and student-transfer administration. The exact PostgreSQL row-lock mode must be selected after verifying the lock conflict matrix for the pinned version and actual foreign keys/triggers.

### 4.4 Administration paths

Student transfer locks old and new class rows in ascending UUID order, then the student row, then revalidates the old membership before updating. Class deactivation/ownership changes lock the class before changing it. Activity administration locks class before activity. Reward maintenance must never lock a reward and then request a student lock; purchases lock class, student, then reward.

### 4.5 Balance result

After acquiring the class and student locks, calculate COALESCE(SUM(points), 0) from the signed ledger. Never accept a client balance. The returned balance is the ledger sum for that transaction.

## 5. Operation contracts

### 5.1 award_points

Inputs: actor teacher, student, positive integer amount, reason, request UUID.

Algorithm:
1. Claim request and validate actor/student/active class ownership.
2. Require amount > 0 and integral (integer-typed parameter).
3. Read the configured `maximum_teacher_award` from the protected config table.
4. If amount exceeds the configured maximum, return `award_limit_exceeded`; do not write ledger.
5. Lock the student row and calculate current ledger balance.
6. Insert exactly one positive ledger row with server-controlled action/source values.
7. Persist request result containing transaction ID, awarded amount, and resulting balance.
8. Insert success audit event; commit all together.

The fixture's seed value 100 is test data only. It is not a production cap recommendation.

### 5.2 deduct_points

Inputs: actor teacher, student, positive integer requested amount, reason, request UUID.

Algorithm:
1. Claim request and validate ownership.
2. Require requested amount > 0.
3. Lock student and calculate balance.
4. Set actual deduction to the lesser of requested amount and nonnegative balance.
5. If actual deduction is zero, store a `zero_balance_noop` result; create no ledger row and no success audit claiming a point mutation.
6. Otherwise insert one negative ledger row for the actual amount.
7. Store resulting balance and actual deduction; insert success audit; commit.

The result must distinguish requested amount from actual deducted amount.

### 5.3 reverse_transaction

Inputs: actor teacher, original transaction ID, request UUID.

Algorithm:
1. Read original transaction to identify student; claim request and validate actor relationship.
2. Lock student, then re-read and lock original transaction FOR UPDATE.
3. Confirm original is eligible for reversal and belongs to the permitted teacher/student context.
4. Check the unique reversal link; if already reversed, return the prior reversal outcome or a stable already-reversed result.
5. Calculate current balance under the student lock.
6. Calculate the full compensating amount. For an original positive award of A points, reversal is -A.
7. If balance < A, return `undo_insufficient_balance` with no partial reversal and no ledger write.
8. Otherwise insert exactly one reversal row with `reverses_transaction_id = original.id`, negative A points, and controlled action/source.
9. Store result and success audit; commit.

The unique reversal reference is a final database backstop against concurrent duplicate reversals. The original transaction is immutable.

The eligibility rule for reversing negative deductions or other transaction types must be explicitly enumerated; do not infer it from the award example. Initial test implementation should support only the approved teacher-award reversal case unless further business rules are approved.

### 5.4 score_activity

Inputs: actor teacher, activity record ID, new integer score, notes, request UUID.

Algorithm:
1. Read record's student ID without locking; claim request.
2. Lock student row; re-read and lock activity record FOR UPDATE.
3. Verify actor owns the active class; activity belongs to that class; record belongs to the activity/student relationship; score is between zero and activity max.
4. Let old score be persisted `points_awarded`; delta = new score - old score.
5. If delta > 0, insert +delta.
6. If delta < 0, calculate available balance while holding student lock and deduct only min(abs(delta), balance). The activity record still stores the teacher-assigned new score.
7. If delta = 0, create no ledger row.
8. Update activity record and ledger, if any, in this same transaction.
9. Store result containing old score, assigned new score, requested delta, actual ledger delta, and resulting balance.
10. Write success audit for the score change; commit.

For a downward score adjustment where balance is insufficient, report both the assigned score and actual point deduction. Example: score 9 to 5 means requested delta -4; if balance is 2, record score 5 and ledger -2.

Do not add a unique activity/student constraint. Do not change duplicate submission behaviour in this transaction design.

### 5.5 purchase_reward_for_student

Inputs: actor teacher, one student ID, one reward ID, request UUID.

Algorithm:
1. Claim request; validate student and reward ownership.
2. Lock student row; then lock reward row FOR UPDATE.
3. Revalidate active reward and active student/class.
4. If finite stock is zero, return `out_of_stock` with no debit/purchase/decrement.
5. Calculate authoritative student balance. If below reward price, return `insufficient_balance` with no debit/purchase/decrement.
6. Insert one negative ledger row for reward price.
7. Insert purchase history snapshot with the reward name and price at purchase time.
8. If stock is finite, decrement exactly one under the row lock; NULL remains NULL.
9. Persist request result and success audit.
10. Commit all changes together.

Each student receives a separate request UUID and independent transaction. The UI may aggregate outcomes, but must not create an all-or-nothing batch transaction.

Deactivation blocks new purchases but must not delete purchase history. The fixture should test the retained purchase snapshot after reward deactivation.

## 6. Audit contract

- Successful business state changes and success audit rows commit together.
- A no-op or business rejection must not create a misleading success audit.
- If rejected-attempt logging is required, design it separately from the mutation transaction.
- Audit metadata must be allowlisted and avoid student access codes, tokens, secrets, or unnecessary personal details.
- A successful retry returns the stored outcome and must not create another success audit row.

## 7. Required function/ACL test cases

### Identity and privilege
- `temmy_ctest_anon` cannot execute any entrypoint.
- `temmy_ctest_authenticated` cannot execute any entrypoint.
- Neither client role can SET ROLE to `temmy_ctest_gateway`.
- Gateway can execute only the five approved operations.
- Gateway has no direct INSERT/UPDATE/DELETE on fixture tables.
- Function owner is non-login, non-superuser, NOBYPASSRLS, fixed search_path.

### Idempotency
- Same key + same actor + same operation + same payload returns stored result.
- Same key with a different actor is rejected.
- Same key with a different operation is rejected.
- Same key with changed amount/student/reward/record/notes is rejected.
- Concurrent duplicate requests create only one mutation and one success audit.

### Balance and concurrency
- Concurrent deductions serialize and never make balance negative.
- Concurrent purchase and deduction serialize on the same student row.
- Two purchases for the final stock unit cannot both succeed.
- Undo and a concurrent spend serialize on the student row; no partial undo.
- Score reduction and purchase/deduction cannot overspend the same balance.
- Deadlock/serialization retry uses the same request UUID and is bounded.

### Atomicity/failure injection
- Inject failure after ledger insert but before activity update; entire transaction rolls back.
- Inject failure after purchase debit but before stock update/history completion; entire transaction rolls back.
- Inject failure before audit insert; no partial mutation commits.
- Verify no success audit exists for rolled-back operations.
- Verify completed request replay never repeats ledger/purchase/stock changes.

## 8. Fixture corrections and implementation gates

Before function SQL is drafted:
- Use namespaced test roles (`temmy_ctest_*`) and refuse pre-existing role collisions.
- Create fixture objects while SET ROLE to `temmy_ctest_data_owner`; do not rely on later ALTER OWNER commands to repair ambiguous ownership.
- Pin PostgreSQL version and required extensions/functions for payload hashing.
- Decide exact stable error/result contract and which rejections are persisted.
- Confirm request-key uniqueness scope; fixture currently uses a globally unique UUID and binds actor/operation/hash in the request row.
- Keep purchase request uniqueness aligned with one request per student purchase.
- Confirm the synthetic fixture can support role and SECURITY DEFINER tests without granting gateway direct table access.

Before production:
- Verify actual deployed marketplace, purchase, activity and ledger schemas and all callers.
- Decide production identity propagation and server credential model.
- Complete isolated tests and explicit review of exact migration/rollback.
- Obtain separate explicit approval for any hosted database or deployment action.

**Current status: NO-GO for production SQL, hosted execution, grants, or deployment.**
