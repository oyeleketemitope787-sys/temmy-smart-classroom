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

**Decision approved 2026-11-09:** Lock the relevant class row before the student row, then validate active state and teacher ownership while both are held. Use one global order: idempotency request → class row(s) sorted by UUID → student row → operation-specific activity/original-transaction/reward row(s) → writes. A preliminary non-locking student-to-class lookup must be revalidated after both locks are acquired; changed membership aborts with a retryable conflict. Student transfers lock old/new classes in sorted order before the student. Class administration locks class before changing it. The detailed rule is in TEMMY_CLASSROOM_GLOBAL_LOCK_ORDERING_RULE.md.\n\n**Remaining verification:** Inventory every actual class/student/activity administration path and verify the selected PostgreSQL row-lock modes, foreign-key/trigger interactions and global lock graph in a fresh disposable database. The current Phase 1–3 function drafts still use student-first locking and must be revised before execution.

### F3 — Expected rejections are not durably idempotent or audited

The current functions raise exceptions for expected business outcomes such as insufficient balance, out of stock, inactive reward, above-cap award and undo-after-spend. Those exceptions roll back the request claim and any same-transaction audit insert.

Consequently, the same request ID can be retried after a rejection as if it were a new request, and the rejection is not durably recorded. This is already acknowledged in the individual drafts but remains an API/business contract gap.

**Decision approved 2026-11-21:** Use durable idempotent outcomes for expected business rejections. Return a stable structured rejection and commit the request's rejected status/result plus a safe rejection audit, without applying a business mutation. Same-key/same-payload retries return the stored rejection; changed actor, operation or payload is rejected. Unexpected internal/system failures still raise and roll back. Never catch every exception and convert it into a committed rejection.

**Remaining verification:** Enumerate expected business rejections versus retryable infrastructure conflicts for each operation; prove replay and rollback semantics in the disposable fixture.

### F4 — Class and student administration lock ordering must be reconciled in the drafts

The transaction drafts use student-first locking for balance operations; purchases then lock the reward row; activity scoring locks the student then activity record and activity. The current concurrency plan does not cover a class deactivation/transfer racing with a transaction, nor all administrative update paths.

**Decision approved 2026-11-09:** The lock-order matrix is now published in TEMMY_CLASSROOM_GLOBAL_LOCK_ORDERING_RULE.md. It requires class-before-student locking, sorted class UUIDs for multi-class operations, then operation-specific rows. The concurrency plan now includes class deactivation/ownership change, student transfer, activity edit/deactivation and reward deactivation races.\n\n**Remaining verification:** Reconcile all real administration paths and revise the current function drafts, which do not yet implement the approved order. Validate lock modes and implicit FK/trigger locks in a fresh disposable database.

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
- The approved class-before-student global lock order is implemented in revised drafts; actual class/student administration paths and lock modes are reconciled.
- Durable rejected-request semantics are decided.
- Zero-balance no-op audit semantics are decided.
- The fixture, seed and SQL are statically reviewed together.
- PostgreSQL version and SHA-256 availability are pinned/confirmed.
- The full function set compiles and passes role-context, ACL, smoke, edge, concurrency and failure-injection tests in a fresh disposable database.

## 5. Safety status

No SQL was run during this review. No triggers were created. No hosted Supabase project, shared database, main branch or cloud-test branch was changed. These findings do not authorize any deployment or hosted database operation.


## 6. Approved Teacher Manual Award Corrections — 2026-11-21

The user approved the corrections identified in the manual-award review:
- 50 points is the default maximum for an individual manual teacher award; the limit is protected and administrator-controlled. Teachers cannot change it.
- Above-cap ordinary awards are clearly rejected, never silently truncated, and produce no points-ledger mutation. Exceptional awards require a separate authorised and audited override workflow; its authority and approval contract remain open.
- Expected business rejections use durable idempotency: request status/result and safe rejection audit commit without business mutation. Identical retries replay the rejection; changed actor/operation/payload is rejected. Unexpected system failures still roll back.
- All award operations follow request -> sorted class row(s) -> student row -> operation-specific rows -> writes. Preliminary membership reads are revalidated after locks; changed membership is a retryable conflict.
- Award configuration changes are administrator-only, protected, audited and concurrency-safe.

The synthetic fixture's old 100-point seed is stale and must be changed to 50 before execution. The test specification and design documents must not be mistaken for evidence that the fixture seed has already been changed. The function drafts, fixture seed, smoke/edge tests and concurrency tests remain unexecuted and must be reconciled together before a fresh disposable run.



## 7. V2 implementation reconciliation — 2026-11-23

The V1 findings above are retained as historical findings against the superseded Phase 1–3 drafts. A V2 review-only implementation has since been added:

- `CLASSROOM_TRANSACTION_FUNCTIONS_V2_FOUNDATION_REVIEW_ONLY.sql.txt`
- `CLASSROOM_TRANSACTION_FUNCTIONS_V2_PHASE1_REVIEW_ONLY.sql.txt`
- `CLASSROOM_TRANSACTION_FUNCTIONS_V2_PHASE2_REVIEW_ONLY.sql.txt`
- `CLASSROOM_TRANSACTION_FUNCTIONS_V2_PHASE3_REVIEW_ONLY.sql.txt`

The V2 drafts implement the agreed shape for request claiming/replay, durable expected rejection results and audits, zero-balance no-op audit, and class-before-student locking. The edge-case suite and supporting smoke/ACL/concurrency/atomicity documentation have been updated to refer to V2.

**This is not a pass/final review.** The following remain open and release-blocking:

The current V2 edge-case draft now includes above-cap durable rejection/replay, marketplace rejection audit counts, zero-balance no-op audit/replay, already-reversed award rejection, changed-payload conflict, and downward activity-score clamping. The V2 award function now reads the protected maximum-award configuration row FOR SHARE so an administrator update cannot race the cap decision. These are static design changes only; no test has been run.

### V2 fixture reconciliation — 2026-11-23

The complete V2 foundation and Phase 1–3 drafts were compared against
`CLASSROOM_TRANSACTION_FIXTURE_SCHEMA.sql` and
`CLASSROOM_TRANSACTION_TEST_SEED.sql.txt` on the review branch.

- The referenced tables and columns in the V2 functions exist in the synthetic
  fixture: request/audit/config tables, classes/students, signed point ledger,
  activity records/activities, rewards and purchase snapshots.
- The fixture's `transaction_config` row seeds
  `maximum_teacher_award = 50`; the seed's opening ledger values are 50, 5,
  50 and 50, with a separate 10-point teacher-award row for reversal.
- The V2 helper's class `FOR SHARE` then student `FOR UPDATE` sequence
  matches the approved high-level lock order. The V2 phase functions follow
  the helper with original-transaction, activity-record/activity or reward
  locks in their operation-specific paths.
- The V2 award-cap lookup now uses `FOR SHARE`, so a concurrent protected
  configuration update must serialize with the cap decision.
- No definite fixture-column or seed-ID mismatch was found in this pass.

This is a static schema comparison only. It does not prove that the scripts
compile, that all lock interactions are deadlock-free, or that the helper's
role-GUC and hash assumptions work on PostgreSQL 16. The fixture's synthetic
schema is not evidence of compatibility with the live Classroom database.

### Additional V2 correctness gates

1. The ACL test currently verifies catalogue privileges but does not attempt
   actual denied DML as anon/authenticated/gateway, nor a nested role-context
   call. Add separate isolated-session runtime tests.
2. Add durable-rejection replay tests after changing the underlying business
   state, and verify a new request UUID re-evaluates the current state.
3. Add same-request-ID tests for changed actor and changed operation, not only
   changed payload.
4. Add an explicit insufficient-balance full-reversal fixture case and assert
   that no reversal ledger row is created.
5. Inject failures at the audit and request-finalization writes and prove the
   business mutation, audit and request claim roll back together.
6. Pin the exact PostgreSQL 16 image digest/version and verify
   `pg_catalog.sha256(bytea)` and `current_setting('role', true)` through
   the nested SECURITY DEFINER call chain before trusting the functions.
7. Inventory real Classroom class/student/activity/reward administration
   paths and compare their row-lock modes with the synthetic global lock rule.


1. Static review of every V2 function against the exact fixture DDL, including PostgreSQL syntax, nullability, constraint and type compatibility.
2. Verify the `current_setting('role')` behaviour through the complete nested SECURITY DEFINER call chain on the pinned PostgreSQL 16 image. Do not rely on the test identity guard until proven.
3. Verify `pg_catalog.sha256(bytea)` availability and exact canonical hash output on the pinned image.
4. Verify class row-lock compatibility with class deactivation/ownership changes and all implicit FK/trigger lock edges.
5. Verify function owner, fixed search_path, helper EXECUTE permissions, gateway entrypoint grants, and actual denied DML from client/gateway roles.
6. Add explicit tests for changed-payload/actor/operation request-key reuse, rejection replay after underlying business state changes, inactive student/class, reversal insufficient balance/already reversed, activity downward clamp, and audit failure rollback.
7. Correctly inventory and test all real activity/class/student/reward administration paths before considering production compatibility.
8. Run syntax, smoke, edge, ACL, concurrency and failure-injection tests only after separate explicit approval in a fresh isolated PostgreSQL 16 container.

No V2 SQL has been executed or syntax-tested. No production/hosted database, `main`, `cloud-test`, or SGIS container has been changed.


### Follow-up static coverage — 2026-11-23

Two additional review-only regression files have been added:

- `CLASSROOM_TRANSACTION_IDEMPOTENCY_REVERSAL_TESTS.sql.txt` checks that a durable cap rejection remains the stored result after the configuration changes, that a new request UUID re-evaluates the changed cap, that actor and operation reuse conflicts are independently rejected, and that an insufficient-balance full reversal creates no reversal ledger row.
- `CLASSROOM_TRANSACTION_RUNTIME_DENIAL_TESTS.sql.txt` attempts direct DML as the synthetic anon, authenticated and gateway roles and expects privilege denial.

These additions address the corresponding static test-coverage gaps; they do not establish that the tests compile or pass. The runtime-denial probes are not a substitute for the separate nested SECURITY DEFINER role-context test. Audit-insert and request-finalization failure injection is also still only specified in the atomicity plan, not implemented or executed.

The older V1 finding in section 6 referring to a stale 100-point fixture seed is historical and superseded: the current V2 fixture configuration row is 50, as confirmed by the 2026-11-23 fixture/seed reconciliation above. Do not treat the historical V1 note as a current fixture defect.

**Current boundary:** all V2 function drafts and all test SQL remain unexecuted. The next meaningful technical gate is a careful static review of the new test scripts and the remaining PostgreSQL 16 role/hash assumptions, followed—only with explicit user approval—by isolated disposable PostgreSQL 16 verification.


### PostgreSQL 16 SHA-256 documentation check — 2026-11-23

The PostgreSQL 16 official documentation lists `sha256(bytea) → bytea` under built-in binary string functions and shows the expected SHA-256 output for `abc`. The V2 expression using `pg_catalog.sha256` is therefore consistent with the documented PostgreSQL 16 built-in; it does not require the `pgcrypto` extension for this function. See the PostgreSQL 16 binary string functions reference: https://www.postgresql.org/docs/16/functions-binarystring.html.

This closes the documentation-availability question, not the pinned-image runtime gate. The exact PostgreSQL 16 image must still be recorded and the function expression/hash output exercised in the isolated disposable database.

### Additional runtime-test drafts — 2026-11-23

- `CLASSROOM_TRANSACTION_NESTED_ROLE_CONTEXT_TESTS.sql.txt` models a SECURITY DEFINER entrypoint calling a SECURITY INVOKER helper and asserts the role GUC remains the gateway role while effective `current_user` is the non-login data owner. This is a proposed runtime assertion only; its expected values have not been observed.
- `CLASSROOM_TRANSACTION_AUDIT_FINALIZATION_FAILURE_TESTS.sql.txt` installs transaction-scoped test-only failpoint triggers and checks rollback of the award ledger write/request claim on audit failure, then rollback of ledger/audit/request claim on request-finalization failure. This covers two award-operation boundaries only; intermediate-write and other-operation cases remain open.

Neither file has been executed. The nested identity result and all rollback assertions remain unverified.
