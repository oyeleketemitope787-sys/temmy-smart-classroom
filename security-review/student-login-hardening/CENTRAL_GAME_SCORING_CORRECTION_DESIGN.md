# Central Game Scoring — Correction Design and Implementation Plan

**Status:** Design only; not an approved migration or deployment instruction.  
**Branch:** `security-review/student-login-hardening`  
**Scope:** Game-result Gateway, proposed scoring RPCs, attempt schema, rate limiting, and isolated verification.  
**Safety:** No SQL in this document is executable. Do not apply this design to shared TEST or production. Keep both game-result Gateway readiness flags unset.

## 1. Decisions carried forward

The user has approved the following request-idempotency design decisions for detailed specification:

- The browser client generates a fresh UUID `request_id` for each logical start or answer operation and reuses that same ID for retries of that operation.
- A committed deterministic outcome is stored and returned for an identical retry; it is never applied twice.
- Idempotency records have an explicit retention/cleanup policy. A 30-day minimum retention is proposed for review, but the final duration must be at least as long as the supported client retry window and must be approved before implementation.

These are approved design directions. They do not mean that the request-ID contract, table, or database behavior has been implemented.

The existing product scoring contract is retained:

- Correctness is derived from the private answer key stored for the attempt.
- The planned browser request contract contains only action, a per-operation `request_id`, session token, game ID, mode (start), and question/choice indexes (answer). The current Gateway validator/RPC signatures do not yet accept `request_id`; this is a required future contract change, not an implemented feature.
- Scores, maximum scores, student/teacher identity, points, and correctness are never trusted from the browser.
- Number Challenge v1 remains 15 questions with a maximum score of 41, including its existing streak and final-question bonuses.
- A completed attempt awards exactly its verified score once. A zero-score completion records the attempt but creates no zero-point ledger row, consistent with the current schema proposal.
- Identical retries are idempotent; changed duplicate answers and out-of-order submissions are rejected.
- Database changes must be atomic: answer state, attempt totals/status, session consumption, and the single points-ledger insert commit or roll back together.

These are design decisions, not evidence that the proposed SQL routines exist in the live database.

## 2. Required correction A — approved global lock order, request idempotency, and membership revalidation

### Problem

The classroom transaction review approves this global lock order for sensitive transactions:

1. Idempotency request row.
2. Relevant class row(s), sorted by stable UUID.
3. Student row.
4. Operation-specific activity, original transaction, or reward rows.
5. Writes.

The current game SQL draft has no request-idempotency table or request ID in either RPC contract. It locks the game-session row first, then attempt/question rows, and reads class/student active state and membership without locking those rows. The previous game-specific correction list omitted the globally required idempotency row. Merely moving class/student locks ahead of the session would therefore still leave the design inconsistent with the approved global rule.

### Required request-idempotency contract

Before changing the SQL functions, the request contract must be extended with a caller-generated UUID `request_id` for each logical start or answer operation. The caller must reuse the same ID when retrying that operation after a timeout or uncertain network result, and generate a new ID for a genuinely new operation.

A proposed durable table, subject to schema review, is `public.game_scoring_idempotency_requests`. It should have a unique request ID, operation/action, a canonical request fingerprint, a completion state, a safe stored response/outcome, and timestamps/retention metadata. It must not store the raw session token, answer key, or other unnecessary secrets. The fingerprint must bind the request ID to the operation and all security-relevant request inputs, including the session credential, game, mode or question/choice indexes. The canonical encoding and hashing primitive must be selected and verified in the disposable database; the existing audit specifically flags unverified SHA-256 helper availability and canonical encoding.

The idempotency row must not have foreign keys that cause it to acquire class, student, or session locks before the approved order. A request ID is only a retry-correlation key; it is not proof of student identity or session authorization.

Required semantics:

- Create-or-find the idempotency row and lock it first. A concurrent reuse of the same request ID must serialize on this row.
- If the stored operation or request fingerprint differs, reject key reuse without changing game state.
- If the row already contains a committed outcome for the identical request, return that stored outcome without reapplying scoring, session consumption, or ledger writes.
- For a new request, persist its final safe outcome in the same transaction as the game-state mutation. A transaction rollback must roll back both the game mutation and the idempotency outcome so a legitimate retry can safely try again.
- A repeated identical answer submitted with a different request ID must still be protected by the existing question-row/attempt-state idempotency rule. A changed answer for an already answered question remains a conflict.
- Retention, cleanup, maximum key age, and behavior for durable rejected outcomes require explicit design and operational review. Do not silently delete keys while a retry may still be valid.

### Required transaction lock protocol

Both `begin_game_attempt` and `record_game_attempt_answer` must follow this sequence, compatible with the approved global lock order:

1. Validate the request envelope and create/find then lock its idempotency request row (`FOR UPDATE`). Verify the operation and canonical request fingerprint. Do not treat the request ID as authentication.
2. Perform a non-locking lookup of the candidate session's student and class identifiers. This lookup is discovery only, not authorization.
3. Lock all relevant class row(s) in stable UUID order (`FOR UPDATE`). For this game flow, the candidate session's class is the initial target; if a transition can involve old and new classes, lock both in sorted order as required by the existing transfer protocol.
4. Lock the student row (`FOR UPDATE`).
5. Lock the game-session row (`FOR UPDATE`).
6. Re-read and revalidate the session/student/class relationships and state while the rows are locked.
7. Lock the attempt row (`FOR UPDATE`), if it exists.
8. Lock the relevant attempt-question row (`FOR UPDATE`), when needed.
9. Perform scoring, answer/attempt/session writes, and any point-ledger insert atomically. No later code path may acquire a class or student lock after an operation-specific lock.

After acquiring locks, verify at minimum:

- The session still references the same student and class discovered during lookup.
- The student's current `class_id` still equals the session's `class_id`.
- The class and student are still active.
- The session's game ID matches the request; expiry and `used_at` are checked while the session is locked.
- The attempt belongs to that session and retains the same game, mode, scoring-rule version, and expected sequence.
- The scoring-rule version is immutable once referenced by an attempt. Prefer append-only versioned catalogue rows so scoring does not need to lock a mutable catalogue row out of order.
- If any identifier or relationship changed between lookup and lock acquisition, fail closed with no score, attempt, session, or ledger mutation.

The exact PostgreSQL lock modes, implicit foreign-key locks, trigger behavior, and interactions with every transfer/deactivation/reward transaction must be checked against the target database version. In particular, the point-ledger insert and its foreign keys/triggers must not introduce a reverse lock dependency. If the global order cannot be preserved, stop and revise the global design rather than introducing a game-specific exception.

### Required race and idempotency tests

- Student transfer races with attempt start.
- Student transfer races with answer submission.
- Class deactivation races with start and answer.
- Student deactivation races with start and answer.
- Same request ID and same payload concurrently: one execution; all callers receive the same committed outcome.
- Same request ID with a different action or payload: reject key reuse; no game mutation.
- Different request IDs for the same start/session: at most one attempt; same game/mode resumes the existing attempt; incompatible mode/game conflicts.
- Two different request IDs submit the same answer concurrently: one scoring mutation; the other receives the stored duplicate-answer outcome.
- Two different request IDs submit conflicting choices for one question: one wins; the other conflicts without mutation.
- Final answer races with retry/replay/finalization.
- Inject rollback after each write boundary; verify no partial answer, attempt, session, idempotency, or point-ledger state.
- Confirm no duplicate point transaction, no deadlock, and no partial attempt/session mutation.

## 3. Required correction B — strict public response projection

### Problem

The Gateway validates the database response but currently spreads the raw object into the browser response (`...result`). Validation of known fields does not make unknown future database fields safe to expose.

### Required design

Do not spread or serialize the raw RPC object. Construct a fresh response from an explicit allowlist after validation.

For an in-progress response, return only:

- `status`
- `game_id`
- `mode`
- `question_count`
- `questions_answered`
- `correct_count`
- `lives_remaining`
- `score`
- `max_score`
- `score_rule_version`
- `question`, containing exactly `question_index`, `prompt`, `options`, and `hint`
- the Gateway-generated `score_display`

For a completed response, return only:

- `status`
- `game_id`
- `mode`
- `question_count`
- `questions_answered`
- `correct_count`
- `lives_remaining`
- `score`
- `max_score`
- `points_awarded`
- `score_rule_version`
- the Gateway-generated `score_display`

The public response must never contain `ok`, database error text, session/student/class/teacher IDs, session tokens, attempt IDs, answer keys, submitted-answer internals, transaction IDs, or arbitrary extra properties. The in-progress question must be copied field by field after exact nested-key validation.

Add tests that inject unexpected top-level and nested fields into a mocked RPC response and assert that they are rejected or omitted. Prefer rejecting unexpected response keys at the contract boundary and still build a fresh projection as a second defensive layer.

## 4. Required correction C — durable rate limits and abuse controls

The current rate-limit document is directionally sound but not implemented. Before activation:

- Select a platform-supported shared ingress limiter or durable shared service; do not use per-process in-memory counters.
- Do not trust caller-provided `X-Forwarded-For`, `Forwarded`, or identity headers. Use only documented metadata overwritten by trusted ingress.
- Add atomic database/session controls for start attempts, answer pacing, and invalid-request abuse. Quota check/update must be one transaction, not read-then-write in Edge code.
- A same-answer idempotent retry must return the stored answer result without a second reward and without being treated as a new accepted answer quota event.
- Conflicting duplicate, skipped, expired, consumed, or invalid-session requests must not change score or award points.
- Apply a cheap start-admission check before expensive question generation, then retain the database uniqueness constraint as the final authority.
- Return HTTP 429 with a safe `Retry-After` value when a limit is reached.
- If the shared limiter is unavailable, reject new starts (fail closed); never fall back to local counters.
- Never log raw session tokens, student access codes, answer keys, service-role credentials, or full request bodies. Use a keyed rotating HMAC pseudonym only if session correlation is required.

**Open decision:** Numeric thresholds (start requests, answer pacing, invalid requests, global capacity), selected ingress mechanism, retention period, and alert ownership require explicit product/operations approval. Do not invent production thresholds in code.

## 5. Required correction D — safe error taxonomy

The current handler maps all RPC failures to HTTP 400. Replace this with a small documented mapping:

- Malformed or unsupported client request: 400 / 415 / 413 as appropriate.
- Invalid, expired, consumed, or mismatched session: one generic client-safe rejection (avoid session enumeration).
- Rate limit: 429 plus bounded `Retry-After`.
- Known business conflict (e.g. conflicting duplicate answer): stable safe conflict response.
- Transient database/network/timeout failure: retryable 5xx, without exposing Postgres text.
- Missing schema/function, catalogue mismatch, malformed trusted RPC response, or configuration fault: fail closed with generic 503 and server-side structured diagnostic.

Do not expose raw SQLSTATE, table/function names, session tokens, or database messages. Preserve idempotent retry behavior where the database can safely return the already-committed answer result.

## 6. Required correction E — schema, constraints, ACLs, and function hardening

Before any migration is drafted for execution, verify the actual disposable-database schema and add tests for:

- Unique one-attempt-per-session constraint.
- Unique session token and attempt-question primary key.
- One active scoring rule per game and immutable/versioned rule semantics.
- Valid score bounds, question count, progress, completion, and points-awarded consistency.
- A unique link from completed attempt to its one point transaction.
- No browser-role SELECT/INSERT/UPDATE/DELETE access to answer-key/attempt tables.
- No browser-role EXECUTE on privileged scoring functions; only the intended backend role can execute.
- RLS enabled on private tables, while recognizing that service-role bypasses RLS.
- Function owner, SECURITY DEFINER status, fixed empty search_path, schema-qualified object references, and least authority.
- No accidental grants inherited from PUBLIC/default privileges.

The service-role key remains server-only. A service-role function path is privileged; ACL tests must demonstrate the intended boundary rather than treating RLS alone as sufficient.

Do not revoke privileges from existing legacy scoring RPCs until every active caller (including separate game sites) has been identified, migrated, and tested. A new Gateway is not an effective boundary while an old direct RPC route remains reachable.

## 7. Isolated verification plan

Use a disposable local/CI PostgreSQL + Supabase-compatible environment only. Do not connect these tests to shared TEST or production.

### A. Schema and ACL
- Apply the reviewed schema/function migrations to a fresh disposable database.
- Run ACL assertions for anon, authenticated, and service_role.
- Verify answer-key table is inaccessible to browser roles.
- Inspect function owner, SECURITY DEFINER, search_path, grants, RLS, constraints, and indexes.

### B. Scoring correctness
- All-correct Number Challenge: exact 41/41.
- Correct/incorrect mixtures: match the existing Number Challenge v1 formula.
- Challenge mode: terminate on the third incorrect answer and award exact score-to-date.
- Practice/class modes: continue through the configured question count.
- Zero-score completion: completed attempt, zero points, no ledger row.
- Non-bonus game: game-specific maximum (e.g. 16/20 awards 16, not a global cap).
- Reject invalid/negative/non-integer/over-maximum score states; never clamp.

### C. Atomicity, request idempotency, and replay
- Verify request-ID uniqueness, canonical fingerprint binding, same-key/same-payload replay, and same-key/different-payload rejection.
- Run concurrent duplicate requests with the same request ID; assert one execution and one stored outcome.
- Run identical-answer retries with different request IDs; assert question/attempt-level idempotency still prevents a second score mutation.
- Inject failures between answer update, attempt completion, ledger insert, session consumption, and idempotency outcome persistence; assert complete rollback.
- Repeat an identical answer after simulated timeout; return the stored result and award once.
- Submit a conflicting duplicate; reject with no mutation.
- Submit out-of-order, wrong-game, wrong-mode, expired, consumed, malformed-token, and invalid-choice requests; no mutation.
- Race parallel final submissions; at most one points-ledger row.

### D. Concurrency and lifecycle
- Run transfer/deactivation race cases listed in Section 2.
- Run concurrent start requests; at most one attempt per session.
- Run parallel answers across the same and different sessions.
- Confirm lock order is consistent with existing classroom transaction paths and no deadlocks occur under repeated stress.

### E. Gateway contract and abuse
- Unit-test explicit response projection, including unknown-key injection.
- Test HTTP method, CORS, content type, body limit, malformed JSON, missing Origin, and disallowed Origin.
- Test generic error mapping and retryable 5xx behavior.
- Test shared rate limits across multiple handler instances/restarts and limiter outage fail-closed behavior.
- Test no sensitive values appear in logs or responses.

### F. Client compatibility
- Inventory every active caller in the classroom and game-site repositories.
- Compare exact request/response shapes with current frontend expectations.
- Migrate callers behind the Gateway in a controlled, separately approved plan.
- Keep legacy direct RPC permissions until migration coverage is proven; then review revocation separately.

### 2.1 Proposed idempotency table contract (design only)

Proposed relation: `public.game_scoring_idempotency_requests`.

The table is deliberately independent of student, class, session, attempt, question, and point-ledger foreign keys. This prevents its insert/lookup path from taking implicit locks on those business rows before the approved global lock order.

| Column | Proposed type | Purpose / constraint |
|---|---|---|
| `request_id` | `uuid` | Primary key; client-generated per logical operation. |
| `operation` | `text` | Allowlisted operation such as `begin_attempt` or `submit_answer`; CHECK constraint. |
| `fingerprint` | `bytea` | Fixed-length keyed digest of the canonical request; never raw request data. |
| `fingerprint_key_version` | `smallint` | Identifies the server-side HMAC key version used to calculate the digest. |
| `outcome_state` | `text` | Only committed terminal states such as `completed` or `rejected`; CHECK constraint. |
| `outcome_code` | `text` | Stable internal result code; no raw database error text. |
| `response_schema_version` | `smallint` | Version of the safe public response projection. |
| `response_payload` | `jsonb` | Allowlisted safe response/outcome only; no IDs or secrets not required by the client. |
| `created_at` | `timestamptz` | Server-generated creation time. |
| `completed_at` | `timestamptz` | Set when a deterministic terminal outcome is committed. |
| `expires_at` | `timestamptz` | Cleanup eligibility; never earlier than the supported retry horizon. |

Required constraints and indexes:

- Primary key on `request_id`.
- CHECK constraint restricting `operation` and `outcome_state` to documented values.
- CHECK constraints requiring the fingerprint to have the expected digest length and terminal rows to have `completed_at` and a response schema version.
- CHECK constraint and/or trigger ensuring `expires_at` is later than `created_at`; application policy must enforce the approved retention minimum.
- Index on `expires_at` for bounded cleanup batches. The primary key supports request lookup.
- No business-table foreign keys, no browser-role table privileges, and no direct client access.
- Do not store the raw session token, access code, answer, answer key, student/class/session/attempt identifiers, or full request body in this table. The safe response payload must follow the Gateway's explicit response allowlist.

The exact column types, constraints, table owner, RLS, grants, and index definitions must be validated against the actual disposable schema before a migration is drafted.

### 2.2 Canonical request fingerprint

The fingerprint must distinguish every security-relevant input while avoiding storage of raw credentials.

Proposed algorithm: HMAC-SHA-256 using a server-held secret, with an explicit key version. The HMAC key must be available only to the trusted server-side scoring path, never to the browser, and must not be embedded in source control or returned by RPCs. Secret storage/rotation is an implementation gate; do not assume an existing secret or vault integration is configured.

Canonical input must be a versioned, unambiguous, typed encoding—not ad hoc string concatenation and not unspecified JSON serialization. It must include:

- A fixed domain separator and canonicalization version.
- Operation name.
- Request UUID.
- Session credential bytes (or a separately derived keyed session-token digest, provided the design proves equivalent binding).
- Game ID.
- Start mode for `begin_attempt`.
- Question index and choice index for `submit_answer`.

Use explicit field ordering, type tags, and length-prefixing (or another formally specified unambiguous encoding). Normalize only fields whose semantics are explicitly identical; do not silently coerce values such as strings to numbers. Reject malformed types before fingerprinting.

Key rotation must preserve replay verification for every retained record. Store the key version with each row and retain the corresponding verification key until all records using it have expired and been safely purged. If a key is compromised, define an explicit invalidation/recovery procedure; never silently recompute old fingerprints with a new key.

**Open implementation gate:** verify the selected PostgreSQL/runtime HMAC implementation and extension availability in a disposable environment. The existing review has not established that `pgcrypto` or a particular digest helper is installed. Do not add an extension to shared TEST or production as part of this design task.

### 2.3 Insert, lock, replay, and outcome semantics

The intended first-use algorithm is:

1. Validate the HTTP/request envelope and enforce cheap ingress limits before database work.
2. Compute the canonical fingerprint in the trusted server path.
3. Attempt to insert the request row with `request_id`, operation, fingerprint, key version, and timestamps using a uniqueness-safe insert that does not update an existing row.
4. Select that row by primary key `FOR UPDATE`. A concurrent first use of the same UUID must wait on the unique-key conflict/row lock and then observe the committed row.
5. Compare operation, fingerprint, and key version semantics. If the same UUID is bound to a different operation or payload, return a generic key-reuse conflict and do not touch game state.
6. If a terminal outcome already exists for the exact same request, return its stored safe outcome immediately without taking class/student/session/attempt/question locks or repeating any mutation.
7. If this transaction inserted a new row, continue to the approved class/student/session/attempt/question lock order, perform authorization and the operation, then write the terminal safe outcome in the same transaction as all scoring changes.

The exact SQL pattern for insert-on-conflict followed by row locking must be proven under the target PostgreSQL version with concurrent integration tests. Do not use an `ON CONFLICT DO UPDATE` shortcut unless its trigger/write side effects and lock behavior have been explicitly reviewed; the preferred design is no-op conflict handling followed by a separate locked read.

Transaction outcome policy:

- Successful start/answer results are terminal and stored.
- Deterministic business rejections that should remain stable for that request (for example, expired/consumed session, incompatible mode, conflicting duplicate answer, or request-key mismatch) may be stored as safe terminal outcomes only after the design defines their exact codes and response schema. Do not persist detailed authorization diagnostics.
- Transient database errors, timeouts, deadlocks, internal exceptions, unavailable dependencies, and unexpected failures must raise/abort so the entire transaction—including a newly inserted idempotency row—rolls back. The client may retry the same request ID.
- Do not commit a durable `processing` row in the first version. Because idempotency row and game mutation share one transaction, an uncommitted row is not a durable stuck-work state; concurrent requests wait for commit/rollback. If future asynchronous processing is introduced, it needs a separate lease/recovery design.
- A stored terminal response must be a safe, versioned public outcome. The Gateway must still validate and project it through the current response allowlist; do not return raw JSONB directly.
- A retry using the same ID and same fingerprint returns the original outcome, even if the session has since expired or been consumed. A genuinely new operation uses a new ID and is authorized against current state.
- A retry using the same ID with a different fingerprint never changes the original row or game state.

### 2.4 Retention and cleanup policy

Proposed starting policy for review:

- Retain terminal idempotency records for **at least 30 days** after completion, and longer if any supported client retry/recovery window, offline-client behavior, support workflow, or audit requirement exceeds 30 days.
- The final configured retention must be approved by product/operations and documented in the client retry contract before implementation.
- Cleanup may delete only terminal rows whose `expires_at` is in the past and whose retention window has fully elapsed. Cleanup must be a privileged, bounded batch job with monitoring; it must not run in a browser path.
- Cleanup must not delete in-progress/uncommitted work (there should be no committed processing state), records under active transaction locks, or records still inside the supported retry horizon.
- Define maximum accepted age for a newly presented request ID separately from record retention. An old ID with no existing row must not be allowed to create an indefinitely retained record; reject it only under a documented server policy.
- Record counts, cleanup failures, oldest retained expiry, and HMAC key-version coverage should be observable without logging raw request data or credentials.
- Never reuse a request UUID intentionally. After record expiry/deletion, an old replay must still be rejected by session/attempt/question state and must never award twice.

### 2.5 Required database and API contract changes

These changes are future work, not implemented:

- Add `request_id` to the start and answer request validators and TypeScript request types; require a valid UUID.
- Pass `request_id` to both scoring RPCs and ensure the same logical operation reuses it on client retries.
- Inventory every client and network retry path. Generate a new UUID only when the user initiates a new logical operation; preserve the ID across timeout, reconnect, and retry.
- Define safe response payloads and stable outcome codes for completed, in-progress, duplicate, and deterministic rejected outcomes.
- Add the idempotency table and RPC logic only in a disposable local/CI PostgreSQL environment after schema and secret handling are approved.
- Ensure no browser role can read or write the idempotency table; only the intended backend execution role can access it.
- Keep the Gateway feature flags default-deny until all database, ACL, concurrency, rate-limit, and client compatibility gates pass.

### Design decisions still required before SQL implementation

- Confirm the final request-ID retry lifecycle and client storage behavior, including reload/offline scenarios.
- Approve the HMAC key storage and rotation mechanism, canonical encoding version, and the verified implementation location (Edge Function or database). The secret must not be supplied by the browser.
- Approve the exact safe terminal outcome codes and response schema versions, including which deterministic rejections are persisted.
- Approve the final retention duration (30 days is a proposed minimum, not yet a production setting), maximum age for first-seen IDs, cleanup cadence, and operational owner.
- Confirm whether every sensitive mutation path that touches the same student/class resources observes the same global lock order, including ledger triggers and foreign-key effects.
- Verify that the chosen idempotency-row creation/locking method serializes concurrent first use without acquiring class/student/session locks first.
- Do not treat the existing unique `student_game_attempts.session_id` or `student_game_attempt_questions(attempt_id, question_index)` constraints as substitutes for the globally required request-idempotency row. They protect game-level uniqueness/replay, but they do not provide request-level idempotency at the first lock position.

## 8. Work sequence and approval gates

1. **Design review:** approve lock-order protocol, response contract, error taxonomy, rate-limit provider and numeric thresholds.
2. **Isolated schema implementation:** convert draft SQL into migrations only on a disposable branch/database; no shared project.
3. **Database verification:** run scoring, rollback, replay, concurrency, lifecycle, ACL and RLS tests.
4. **Gateway hardening:** implement response projection, safe error mapping, limiter integration and handler contract tests.
5. **Client compatibility:** inventory/migrate every caller and prove legacy bypasses are addressed.
6. **Independent review:** review the final diff, test output, grants, schema and threat model.
7. **Separate deployment authorization:** only after all gates pass; deployment, secrets, feature flags, shared TEST, and production each require explicit separate approval.

## 9. Current release decision

**NO-GO for SQL execution, shared TEST changes, deployment, or enabling either Gateway flag.**

This document is a correction plan only. It does not approve the proposal SQL, assert that the RPCs exist in the live database, or authorize any hosted changes. The existing 34 pure-function tests and Deno checks are useful local evidence but do not substitute for PostgreSQL integration, ACL, rollback, rate-limit, HTTP, client-compatibility, or concurrency tests.
