# Static Review Findings — Transaction Function Drafts

**Status:** Review-only findings; no SQL executed  
**Reviewed branch:** security-review/student-login-hardening  
**Files reviewed:** Phase 1, Phase 2, Phase 3 function drafts; fixture schema; ACL tests; concurrency plan; smoke and edge-case drafts.

## 1. Overall assessment

The drafts have a coherent starting structure: narrow business entrypoints, SECURITY DEFINER functions, a non-login data-owner role, a shared student-row balance lock, signed-ledger mutations, request-key replay protection, and transactional success auditing.

They are **not ready to execute or approve**. The synthetic harness and function drafts still have design questions that must be resolved and then tested in a fresh disposable PostgreSQL environment. This review is static; it does not prove syntax, runtime behaviour, authorization, isolation or concurrency.

## 2. Findings requiring resolution before execution

### F1 — Gateway actor identity is a test-only assumption

The functions accept p_actor_teacher_id as an argument. In this fixture, the argument is trusted because only the non-login Gateway test role is intended to execute the entrypoints. That proves neither who the real teacher is nor that a production caller cannot choose another teacher ID.

**Required decision:** Define the production trust chain: authenticate the teacher at the trusted server boundary, derive the teacher ID from verified identity claims, and pass only that verified ID into the database operation. Never accept a teacher ID supplied by the browser as proof of identity.

The current current_setting('role') check is also a test-specific assumption. Verify it through the complete nested SECURITY DEFINER call chain. Do not treat the ACL catalog test as proof of runtime role-context behaviour.

### F2 — Student ownership check does not lock the class row

Phase 1's _lock_student_and_get_balance locks the student row and reads its class/teacher relationship through a join, but it does not lock the class row. Phase 2's activity validation also reads class ownership/active state without locking the class row.

A concurrent class deactivation or ownership-changing operation could race with a transaction after the check. Whether this is exploitable depends on the actual class-management permissions and update paths, which have not been fully reconciled.

**Required decision:** Inventory every class/student administration path. Decide whether class rows must be locked (for example, a compatible shared lock) while validating ownership and active state, and establish one global lock order for class, student, activity record, original transaction and reward rows. Then test the chosen order under concurrent class changes and student transactions.

### F3 — Expected rejections are not durably idempotent or audited

The current functions raise exceptions for expected business outcomes such as insufficient balance, out of stock, inactive reward, above-cap award and undo-after-spend. Those exceptions roll back the request claim and any same-transaction audit insert.

Consequently, the same request ID can be retried after a rejection as if it were a new request, and the rejection is not durably recorded. This is already acknowledged in the individual drafts but remains an API/business contract gap.

**Required decision:** Choose one explicit contract before implementation:
- Expected business rejections return a structured result and commit a rejected request record (and safe rejection audit) without applying business mutations; or
- Rejections remain exceptions and retryable, with no durable rejection audit/idempotency claim.

If choosing the first option, ensure unexpected database/system failures still abort and roll back. Do not catch every exception and turn it into a committed rejection.

### F4 — Class and student administration lock ordering is not yet specified

The transaction drafts use student-first locking for balance operations; purchases then lock the reward row; activity scoring locks the student then activity record and activity. The current concurrency plan does not cover a class deactivation/transfer racing with a transaction, nor all administrative update paths.

**Required decision:** Publish one lock-order matrix covering all functions that can update classes, students, activities, rewards, point transactions and activity records. Add concurrency cases for class deactivation/ownership changes and activity edits while a score is being assigned.

### F5 — Activity score and ledger atomicity needs the failure-injection proof

The score function currently writes the ledger delta, updates the activity record, writes a success audit and completes the request within one function call/transaction. That is the intended shape, but it has not been executed or tested.

**Required test:** Use the atomicity plan to inject failures after each preceding write and prove that no ledger delta, activity score, audit row or completed request remains after failure.

### F6 — Zero-balance deduction audit semantics need a precise statement

The approved business rule says a zero-balance deduction is a no-op with no zero-value ledger transaction. The current draft completes the idempotency request but writes no success-audit row for that no-op.

**Required decision:** Confirm whether an accepted no-op should create a safe audit event (for traceability) even though it creates no point-ledger transaction. Keep ledger semantics unchanged either way.

## 3. Additional checks and observations

1. **Request payload binding:** The canonical payload hashes include actor, target and material operation inputs. Verify canonicalization is stable for all accepted input types and explicitly decide whether trimmed/normalized text is treated as the same request payload.
2. **Request key scope:** The fixture uses a global UUID primary key, which is stricter than a composite (actor, operation, request_id) scope. This is acceptable if intentional, but document that one UUID cannot be reused for a different operation or actor.
3. **Successful replay:** A completed replay returns the stored result with replayed: true. Verify exact response compatibility with the future Gateway and UI contract.
4. **Balance source:** Functions sum the signed ledger after locking the student. Verify the production ledger has no legacy invalid rows or negative-net balances before cutover; the frontend's displayed balance clamp must not mask bad ledger state.
5. **Undo eligibility:** The draft reverses only positive teacher awards and rejects when the current balance is below the full original award. This matches the approved full-reversal/no-partial-reversal rule for that defined transaction class. Other transaction types remain out of scope.
6. **Marketplace snapshot:** The synthetic purchase stores reward name and price at purchase time. Confirm whether the final history contract needs other snapshots; do not infer production schema from this fixture.
7. **Reward deactivation:** The purchase function checks active while holding the reward row lock. Verify the eventual management function uses compatible locking and deactivates rather than deletes.
8. **Activity duplicate semantics:** The fixture intentionally has no unique (activity_id, student_id) constraint. Preserve this until the existing duplicate-submission behaviour is fully verified.
9. **ACL test scope:** The catalog assertions check grants, ownership and configured search path. They do not prove that nested SECURITY DEFINER identity checks work, nor do they test actual denied DML in a live session.
10. **Concurrency test scope:** The plan is useful but still needs activity-score/class-administration races, lock-order validation and a documented retry policy for deadlocks/serialization errors.
11. **Database helper:** Confirm the pinned PostgreSQL version provides the referenced pg_catalog.sha256(bytea) function and validate the exact canonical-hash expression during compile tests.
12. **Test fixtures:** The zero-balance edge-case setup has been corrected to add a valid -50 synthetic ledger entry against the seeded +50 balance. The ledger constraint forbids zero-valued transaction rows.

## 4. Execution gates

Do not execute any draft until:

- Production identity propagation is designed independently from the test-only role argument.
- Class/student administration paths and global lock order are reconciled.
- Durable rejected-request semantics are decided.
- Zero-balance no-op audit semantics are decided.
- The fixture, seed and SQL are statically reviewed together.
- PostgreSQL version and SHA-256 availability are pinned/confirmed.
- The full function set compiles and passes role-context, ACL, smoke, edge, concurrency and failure-injection tests in a fresh disposable database.

## 5. Safety status

No SQL was run during this review. No triggers were created. No hosted Supabase project, shared database, main branch or cloud-test branch was changed. These findings do not authorize any deployment or hosted database operation.
