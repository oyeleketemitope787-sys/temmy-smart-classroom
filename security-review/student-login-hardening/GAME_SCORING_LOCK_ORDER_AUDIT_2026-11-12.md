# Game Scoring Lock-Order Audit — Findings and Required Revision

**Date:** 2026-11-12  
**Status:** Read-only source audit; design correction only.  
**Branch:** `security-review/student-login-hardening`  
**No database, SQL, function, grant, secret, feature-flag, or deployment changes were made.**

## 1. Sources inspected

- `security-review/classroom-transaction-tests/CONSOLIDATED_SECURITY_DECISION_AND_READINESS_REVIEW_2026-11-09.md`, Section 6.
- `security-review/classroom-transaction-tests/PHASE_A_LIVE_DATABASE_SECURITY_VERIFICATION_2026-11-10.md`, Sections 5.2 and 18.2.
- `security-review/student-login-hardening/GAME_RESULT_ATOMIC_FUNCTIONS_PROPOSAL.sql.txt`, both proposed RPC bodies.
- `security-review/student-login-hardening/GAME_RESULT_ATTEMPT_SCHEMA_PROPOSAL.sql.txt`.
- `security-review/student-login-hardening/POSTGRES_CENTRAL_SCORING_CONCURRENCY_SETUP.sql`.
- `security-review/student-login-hardening/POSTGRES_CENTRAL_SCORING_ACL_TESTS.sql`.

## 2. Approved global lock order

The approved classroom transaction rule is:

1. Idempotency request row.
2. Relevant class row(s), sorted by stable UUID.
3. Student row.
4. Operation-specific activity, original transaction, or reward rows.
5. Writes.

For a student's class, the documented pattern is an initial non-locking class lookup, then class lock, then student lock, followed by membership revalidation. Transfers lock old/new class rows in stable UUID order, then student, then revalidate. Exact PostgreSQL lock modes and FK/trigger interactions remain a database-version verification item.

## 3. Game scoring proposal does not comply yet

Both `begin_game_attempt` and `record_game_attempt_answer` currently:

- join session, class and student;
- select the session and lock only `student_game_sessions` with `FOR UPDATE OF sgs`;
- read class active, student active and student class membership without locking those rows;
- then lock attempt and, for answer submission, question rows.

This is session-first, not the approved class-before-student protocol. It also permits a transfer/deactivation race between the active/membership read and the score mutation unless the rows are locked and revalidated.

The Phase A report independently records this as an unresolved release gate. The live inventory at that audit date did not contain the proposed scoring RPCs, so this finding concerns the draft design; it is not a claim about a deployed implementation.

## 4. Corrected lock protocol for the scoring design

For both RPCs, the revised sequence should be:

1. Perform a non-locking lookup by the unique session token to discover candidate session ID, student ID, and class ID. Treat these values as provisional only.
2. Lock the candidate class row.
3. Lock the candidate student row.
4. Lock the game-session row.
5. Re-read and verify the session still identifies the same student/class; verify the student's current class membership; verify class/student active state; verify game ID, expiry and unused status.
6. Lock the attempt row, if present.
7. Lock the relevant question row, for answer submission.
8. Validate attempt state, rule version, expected question sequence, idempotent retry/conflict and answer choice.
9. Perform answer, attempt, session and point-ledger writes atomically.

If any row disappears or the relationships differ after locks are acquired, return a safe retryable conflict or generic invalid-session result without score/ledger mutation.

### Idempotency-order mapping remains an explicit design question

The global protocol begins with an idempotency request row. The current game-scoring schema does not define a separate idempotency-request table or request ID. The unique session row and one-attempt-per-session constraint provide a session-scoped idempotency anchor, but the design must explicitly decide whether that session row is the applicable idempotency row for this workflow, or whether a separate request-idempotency record is required.

Do not claim full compliance with step 1 until this mapping is reviewed and approved. Do not add a new idempotency table speculatively.

## 5. Additional concurrency observations

- Student transfer must lock old and new class rows in sorted UUID order before locking the student. The game RPC must not acquire the student first.
- Class deactivation/ownership changes must lock the class before updating it. The game RPC's class lock therefore serializes eligibility checks with those changes.
- The game session has no student/class foreign keys in the Phase A constraint inventory. The RPC must explicitly revalidate the relationship; a join alone is not a substitute.
- Attempt and question rows are operation-specific locks and belong after class and student locks.
- Existing row-lock modes, foreign-key checks and any triggers must be checked on the disposable PostgreSQL version before treating the sequence as deadlock-safe.

## 6. Required isolated concurrency tests

1. Transfer student from class A to class B racing with `begin_game_attempt`.
2. Same transfer racing with `record_game_attempt_answer`.
3. Deactivate class racing with start and answer.
4. Deactivate student racing with start and answer.
5. Two simultaneous start calls using one session token.
6. Two identical concurrent submissions for one question.
7. Two conflicting concurrent submissions for one question.
8. Two final-answer/replay requests racing to complete and award.
9. Repeated multi-session stress test to detect deadlocks and confirm no duplicate point transactions.

Assertions: no answer or score mutation on failed eligibility checks; at most one attempt per session; at most one ledger award; no partial transaction; safe retry/conflict result where applicable.

## 7. Audit conclusion

**Finding confirmed: the proposed SQL lock order must be revised before any SQL implementation.**

The safe next action is to update the correction design with this exact global order and resolve the idempotency-row mapping. Then, separately, implement and unit-test the Gateway response allowlist. All database work remains confined to a disposable isolated environment after explicit approval. Shared TEST and production remain out of scope.
