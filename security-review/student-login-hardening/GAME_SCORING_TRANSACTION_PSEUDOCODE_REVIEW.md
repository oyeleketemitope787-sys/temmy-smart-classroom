# Central Game Scoring — Transaction-Level Pseudocode Review

**Status:** Design and review artifact only. Not executable SQL, not a migration, and not implementation approval.  
**Branch:** `security-review/student-login-hardening`  
**Companion design:** `CENTRAL_GAME_SCORING_CORRECTION_DESIGN.md`  
**Safety boundary:** Do not run SQL from this document. Do not alter `main`, `cloud-test`, the shared Supabase TEST project, or production. The existing local database `temmy_classroom_local` is not an approved scratch target. A separately provisioned disposable database with synthetic data must be explicitly approved before any SQL execution.

## 1. Purpose and scope

This document translates the approved request-idempotency direction and the classroom-wide lock order into reviewable transaction pseudocode for:

1. `begin_game_attempt`
2. `record_game_attempt_answer`
3. The shared request-idempotency protocol
4. Completion and the single points-ledger award

It intentionally does not supply executable SQL. The current RPC signatures do not yet accept `request_id`; no request-idempotency table or database behavior described here is claimed to exist.

## 2. Invariants that every path must preserve

### Trust and scoring

- The browser is an untrusted requester. It supplies no score, maximum score, correctness flag, student/teacher identity, points award, answer key, or question set.
- The trusted Gateway validates the browser envelope and derives the session/game operation. It generates the question set using server-owned logic; the database accepts that question set only through a trusted server-only execution path and validates it completely before writing.
- The correct choice remains private in the attempt-question row. The browser receives only the public question projection.
- Score is recomputed from the stored correct choice and persisted attempt state. Number Challenge v1 remains 15 questions and maximum score 41 under `number-challenge-streak-v1`.
- `points_awarded` equals the verified final score exactly. Award once only when the completed score is greater than zero. Do not create a zero-point ledger row.
- An attempt's game, mode, question count, maximum, and scoring-rule version are immutable after creation.

### Transaction and retry

- The idempotency row is the first row lock in the global sensitive-mutation order.
- Idempotency outcome and game mutation commit together. A transient failure aborts both.
- An identical retry returns the original committed safe outcome and performs no second mutation.
- Reusing a request ID with a different operation or payload never executes the alternate payload.
- Different request IDs do not bypass attempt/question/session uniqueness and state checks.
- The final-answer transition, session consumption, and one ledger insert are atomic.

### Global lock order

The approved order is:

1. Idempotency request row.
2. Relevant class row(s), sorted by stable UUID.
3. Student row.
4. Operation-specific rows, in a documented consistent order: game session, attempt, then question; point-ledger insert follows the locked state rows.
5. Writes.

The non-locking session lookup before class/student locks is discovery only. It is not authorization. Re-read and revalidate relationships after acquiring locks. No code path may acquire a class/student lock after it has acquired a session, attempt, question, or ledger-related lock.

## 3. Shared request-idempotency protocol

### 3.1 Browser/Gateway contract

For each logical start or answer operation:

- Browser generates a fresh UUID `request_id`.
- Browser retains that ID across timeout, reconnect, and retry of that same logical operation.
- Browser generates a new ID only for a genuinely new operation.
- Gateway validates UUID syntax and request shape. The UUID is a retry key, not authentication.
- Gateway derives the session credential from the request and never trusts a student identity supplied by the browser.
- Gateway computes the canonical request fingerprint with a server-held HMAC key. Raw credentials are not persisted or logged.

The canonical fingerprint input is versioned and unambiguous and binds: domain separator/version, operation, request ID, session credential (or an equivalently secure keyed session-token digest), game ID, and operation-specific fields (mode for start; question index and choice index for answer). Use explicit type tags and length-prefixing. Do not rely on unspecified JSON serialization or string concatenation. The HMAC key version is stored with the record.

The request's server-generated question set is not a browser field and is not part of the browser logical-request fingerprint. The first successful transaction persists the trusted generated set. If the transaction rolls back, a retry may regenerate it unless a deterministic, stable server-side generation seed is separately specified. Decide whether deterministic regeneration is required for product fairness before implementation.

### 3.2 Request row creation and locking

Conceptual sequence, inside the same database transaction as the game operation:

1. Validate non-null request ID, operation allowlist, and fingerprint shape.
2. Attempt an insert of a new request row with the UUID, operation, fingerprint, key version, and server timestamps. On unique conflict, do not update the existing row.
3. In a subsequent statement, select that row by primary key and lock it `FOR UPDATE`.
4. Compare operation and fingerprint using constant-time comparison where supported/appropriate.
5. If they differ, return a generic idempotency-key-reuse conflict. Do not mutate the original row and do not continue to game locks.
6. If a matching terminal outcome exists, return its stored safe outcome immediately. Do not acquire class/student/session/attempt/question locks and do not re-run scoring.
7. If this transaction inserted the new row, continue with the operation-specific protocol below.
8. Write the terminal outcome to the row in the same transaction as all operation changes.

**Concurrency requirement:** Under the selected PostgreSQL isolation level, prove that concurrent first-use requests with the same UUID serialize correctly: one insert wins; the other waits on the unique-key conflict; after the winner commits, the second statement sees and locks the committed row. If the winner rolls back, the waiting request must be able to become the first successful inserter. Test the exact pattern on the target PostgreSQL version. Do not use `ON CONFLICT DO UPDATE` without a separate trigger/write-side-effect and lock review.

**Isolation-level gate:** The intended two-statement visibility behavior must be verified under the actual transaction isolation level. Under snapshot-based stronger isolation, serialization failures may occur; they must abort cleanly and be retried with the same request ID. Do not assume READ COMMITTED without checking deployment configuration.

### 3.3 Outcomes

- **Committed success:** Store a safe, versioned response projection and stable outcome code; commit with the game mutation.
- **Deterministic business rejection:** Persist only after defining which rejection codes are durable and safe. It must not mutate game state. Examples for review: invalid/expired/consumed session, mode mismatch, already-answered conflicting choice. Do not store detailed authorization diagnostics.
- **Retryable conflict:** Abort/raise so the idempotency insert and all work roll back. The same request ID can be retried. Class/student membership changed during lock acquisition is a retryable conflict.
- **Transient/system failure:** Raise/abort. Do not commit an error response or a stuck `processing` row.
- **Key reused with different fingerprint:** Return a generic conflict without changing the existing idempotency record. Consider a separate privacy-safe security event, but do not let logging acquire business locks out of order.
- **Stored response:** Must be validated and projected through the current Gateway allowlist. Never return stored JSONB blindly.

There is no committed `processing` state in this design. A newly inserted row is uncommitted until the game operation and terminal outcome finish. Concurrent same-key requests wait for commit or rollback.

## 4. `begin_game_attempt` transaction pseudocode

Inputs (future contract): `request_id`, session token, game ID, mode, plus trusted server-generated question payload supplied only by the Gateway/service execution path. Browser must not provide the question payload.

1. **Idempotency first**
   - Run shared request-row insert/find/lock protocol for operation `begin_attempt`.
   - Fingerprint binds request ID, session credential, game ID, and mode.
   - If identical terminal outcome exists, return it immediately.
   - If key mismatch, stop without business-row locks.

2. **Discovery only**
   - Perform a non-locking lookup by session token to discover candidate session ID, student ID, and class ID.
   - If no candidate exists, produce the documented safe invalid-session outcome. Do not reveal whether a token belongs to a particular student.
   - Treat discovered identifiers as untrusted until revalidated under locks.

3. **Global authorization locks**
   - Lock candidate class row.
   - Lock candidate student row.
   - Lock candidate game-session row.
   - Re-read session and verify it still references the same class/student; verify student's current class matches session class; verify class and student are active.
   - Verify session game ID matches requested game, session is unexpired and unused (unless a documented resume rule applies).
   - If membership or candidate identity changed, abort as retryable conflict; do not continue with stale identifiers.

4. **Attempt lookup/lock**
   - Look up attempt by unique session ID and lock it if present.
   - If an attempt exists, verify its game, mode, rule version, question count and state.
   - If completed, produce the safe completed response from persisted attempt state. Do not create a second attempt or award again.
   - If in progress, lock the current question row after the attempt row; verify the expected question exists; return the current safe question projection.
   - If an existing attempt has incompatible game/mode or invalid state, return the defined safe deterministic rejection; do not mutate it.

5. **New attempt path**
   - Confirm the server-generated question set is present, trusted, complete, and valid against the immutable registered scoring rule.
   - Confirm question count, contiguous indexes, prompt/hint lengths, exactly four distinct string options, and correct choice index range.
   - Confirm no browser-supplied answer key is accepted by any public endpoint.
   - Insert one attempt row with immutable game/mode/rule version/count/max score and initial totals/state.
   - Insert all private question rows, including correct choice indexes, in deterministic question-index order.
   - Read question zero and construct the safe in-progress response.
   - Store the terminal idempotency outcome.
   - Commit all attempt/question/idempotency writes atomically.

6. **No second award**
   - Starting/resuming an attempt does not insert a point-ledger row.
   - The unique attempt-per-session constraint remains a second line of defense against different request IDs racing to create an attempt.

### Start race expectations

- Same request ID + same payload concurrently: one transaction creates the attempt; the other returns the stored start outcome after waiting.
- Same request ID + different payload: key-reuse conflict; no second operation.
- Different request IDs + same session/game/mode concurrently: session/attempt serialization and unique constraint yield at most one attempt; the later operation resumes the same attempt according to the documented contract.
- Different request IDs + incompatible mode: one attempt wins; the other receives a deterministic conflict and cannot replace mode.
- Student transfer or class deactivation during start: class/student locks and post-lock revalidation determine the winner; no start may proceed on stale membership or inactive state.

## 5. `record_game_attempt_answer` transaction pseudocode

Inputs (future contract): `request_id`, session token, game ID, question index, choice index.

1. **Idempotency first**
   - Run shared request-row insert/find/lock protocol for operation `submit_answer`.
   - Fingerprint binds request ID, session credential, game ID, question index and choice index.
   - If identical terminal outcome exists, return it immediately without any further locks or writes.
   - If same request ID is bound to another answer/operation, stop with key-reuse conflict.

2. **Discovery only**
   - Non-locking lookup by session token discovers candidate session/student/class IDs.
   - No discovery result is authorization.

3. **Global authorization locks**
   - Lock class, then student, then session.
   - Re-read and revalidate session/class/student relationships and active state.
   - Verify game ID, expiry, session/attempt eligibility and that the session belongs to the authenticated student context derived from the session record.
   - On transfer/deactivation race or changed relationships, abort as retryable conflict.

4. **Attempt and question locks**
   - Lock attempt for the session.
   - Verify attempt is in progress or in a documented terminal state; verify immutable game/mode/rule version/count/max score.
   - Lock the requested attempt-question row after the attempt row.
   - Verify requested index is exactly the expected next question unless it is an already-recorded identical duplicate handled by a documented duplicate-answer rule.
   - Reject out-of-range, skipped, or conflicting submissions without score mutation.

5. **Verify answer and derive score**
   - Compare submitted choice index with the private stored correct choice index.
   - Never accept a browser correctness flag or score.
   - Derive correct count, current streak, lives, verified score and next question index from locked persisted state plus this one verified answer.
   - Apply the immutable rule version. Number Challenge v1 retains its defined streak and final-question bonus rules and maximum 41.
   - In challenge mode, an incorrect answer decrements lives; the third incorrect answer ends the attempt early. A completed/early-completed attempt records the exact verified score-to-date.
   - Store answer outcome and update attempt totals/state atomically.

6. **If not complete**
   - Read the next question row only after the attempt/question locks are held, preserving row order.
   - Build a safe in-progress response containing only approved public fields.
   - Store this response as the terminal outcome for this request ID.
   - Commit answer, attempt state, and idempotency outcome together. Do not consume the session or award points yet.

7. **If complete**
   - Mark attempt completed and set completion timestamp.
   - Mark session consumed in the same transaction.
   - Compute points award from the verified final score. If score > 0, insert exactly one point-ledger row for the student and owning teacher, with a stable source/reference to the completed attempt and a database uniqueness guarantee preventing a second game-completion award for that attempt.
   - If score = 0, insert no ledger row and record points_awarded = 0 in attempt/result state.
   - Persist final score and points_awarded on the attempt.
   - Build safe completed response.
   - Store terminal idempotency outcome.
   - Commit answer, attempt completion, session consumption, one ledger award (if positive), and idempotency outcome atomically.

### Answer race expectations

- Same request ID + same answer concurrently: one execution; all identical callers receive the same committed result.
- Same request ID + different answer: key-reuse conflict; alternate answer is never evaluated.
- Different request IDs + same choice for same question concurrently: only one answer mutation. The second request receives the documented duplicate-answer result; no second score or award.
- Different request IDs + conflicting choices for same question: first committed answer wins; second receives conflict; no score overwrite.
- Final answer racing with replay/finalization: attempt lock and atomic completion ensure one finalization and at most one ledger award.
- Student transfer/deactivation races: no answer is accepted based on stale class membership or inactive state.

## 6. Point-ledger award: required safeguards

The completion path must not treat application-level "check then insert" as sufficient.

Required protections:

- A database uniqueness constraint or equivalent immutable award-reference rule ensures at most one game-completion ledger row per attempt.
- Ledger row student and teacher ownership are derived from the locked, revalidated session/class/student records, not request fields.
- Positive verified score is the exact ledger amount. No clamping, percentage conversion, or browser override.
- Zero score creates no zero-point transaction.
- Attempt completion, session consumption, idempotency outcome, and ledger row are in one transaction.
- Existing ledger triggers and foreign keys must be inspected for implicit lock acquisition and reverse lock dependencies. The insert's side effects must not acquire class/student locks after operation-specific locks.
- If required ledger insertion or audit fails, the entire completion transaction rolls back.
- The exact source/action columns and uniqueness key must be checked against the real schema before any migration is written.

## 7. Cross-cutting transaction hazards to resolve

1. **Session discovery and transfer race:** the initial lookup may see a session's old class while transfer is occurring. Class lock followed by student lock and post-lock relationship revalidation must detect this. Verify the session's class is immutable or define how transfer updates it.
2. **Class/student lock modes:** `FOR UPDATE` is a conservative placeholder. Confirm compatible modes with transfer, deactivation, ownership updates, FK checks and triggers. Do not weaken lock mode without proving serialization.
3. **Attempt/question ordering:** every function that touches both must lock attempt before question. No alternate path may lock question then attempt.
4. **Idempotency unique conflict:** test exact insert/conflict/read sequence under the configured isolation level, including winner commit and winner rollback.
5. **Durable rejection semantics:** decide which rejections are committed terminal outcomes and which are retryable aborts. Avoid persisting stale-state conflicts.
6. **HMAC availability:** verify secure key storage, runtime location, rotation, and constant-time comparison. Do not assume pgcrypto or a particular database extension is installed.
7. **Question generation:** decide whether a rolled-back start retry must regenerate byte-identical questions or whether the first committed generated set is authoritative. If deterministic, specify stable seed handling without exposing a secret.
8. **Response compatibility:** inventory every frontend caller and confirm that in-progress/completed/duplicate/rejected response fields and HTTP statuses match what clients expect.
9. **Rate limiting:** shared durable ingress and database controls remain unimplemented. Idempotency retries must not count as new accepted answer mutations.
10. **Lock graph completeness:** inspect all class/student transfer/deactivation, session creation, reward/ledger triggers, FK effects, and any maintenance function. A game-only review cannot certify global deadlock freedom.

## 8. Required isolated test matrix before migration approval

All tests must use a newly provisioned, explicitly approved disposable PostgreSQL environment with synthetic data only. The existing local database and hosted TEST/production are not authorized test targets.

### Idempotency

- Same UUID, same operation/payload, sequential retry.
- Same UUID, same operation/payload, concurrent first use.
- Same UUID, different operation.
- Same UUID, different session token.
- Same UUID, different game/mode.
- Same UUID, different question/choice.
- First transaction commits while duplicate waits.
- First transaction rolls back while duplicate waits.
- Process/network timeout after commit; retry returns stored response.
- Process/network timeout before commit; retry executes once.
- Key rotation while old unexpired rows remain.
- Expired record cleanup racing with a retry.

### Start/answer and scoring

- Two starts for one session with same and different request IDs.
- Same session requested with incompatible mode.
- Correct and incorrect answers across each scoring mode.
- Streak reset and each bonus boundary.
- Challenge mode reaches zero lives before all questions are answered.
- Final question and final-question bonus.
- Duplicate identical answer with same and different request IDs.
- Conflicting duplicate answer.
- Skipped and out-of-range question indexes.
- Completed attempt replay.
- Zero-score completion: attempt completes, no ledger row.
- Positive completion: exactly one ledger row with exact score.

### Concurrency, atomicity and global lock order

- Start versus student transfer.
- Answer versus student transfer.
- Start/answer versus student deactivation.
- Start/answer versus class deactivation/owner change.
- Two final answers/retries racing.
- Ledger trigger/FK interactions and competing student/class operations.
- Inject failure after each write boundary; verify no partial answer, attempt, session, idempotency, audit, or ledger state.
- Verify no deadlocks under repeated randomized concurrency runs and capture lock graphs on failure.

### Access control and response safety

- Browser/anon/authenticated roles cannot read or write idempotency rows or directly execute scoring RPCs.
- Only intended backend role can invoke the scoring operations.
- No service-role key or HMAC secret is exposed to the browser or logs.
- Unexpected database fields never reach public responses.
- Stored response is revalidated and projected by Gateway allowlist.
- Generic errors do not disclose whether a student/session exists.

## 9. Open decisions — do not draft migration until resolved

- Exact database isolation level and proven idempotency insert/lock pattern.
- HMAC key storage, runtime location, rotation and recovery.
- Whether request fingerprints use raw session token bytes transiently or a separately derived keyed session digest.
- Final request-ID maximum age and retry contract for reload/offline clients.
- Which deterministic rejections are durable terminal outcomes and their exact response codes/schema versions.
- Final retention period (30 days is a proposed minimum), cleanup cadence, monitoring and operational owner.
- Whether rolled-back start retries require deterministic question regeneration.
- Exact ledger source/reference fields and uniqueness constraint supported by actual schema.
- Exact FK/trigger lock behavior and compatibility with the global lock order.
- Full frontend response compatibility and retry-path inventory.
- Shared rate-limiting design and numeric thresholds.

## 10. Current status and explicit non-authorization

This is a transaction-level review specification only. No function, table, constraint, index, grant, policy, trigger, migration, Edge Function, feature flag, or database has been changed by this document.

**Do not execute SQL from this document. Do not deploy. Do not set Gateway readiness flags. Do not modify `main`, `cloud-test`, shared TEST, production, or `temmy_classroom_local`.**

The next permitted step is a read-only review of this pseudocode against the existing schema proposal, actual client call sites, and the global classroom lock graph. Any disposable database provisioning or SQL execution requires separate explicit approval.
