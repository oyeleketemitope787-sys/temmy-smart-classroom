# Central Game Scoring — Correction Design and Implementation Plan

**Status:** Design only; not an approved migration or deployment instruction.  
**Branch:** `security-review/student-login-hardening`  
**Scope:** Game-result Gateway, proposed scoring RPCs, attempt schema, rate limiting, and isolated verification.  
**Safety:** No SQL in this document is executable. Do not apply this design to shared TEST or production. Keep both game-result Gateway readiness flags unset.

## 1. Decisions carried forward

The existing product scoring contract is retained:

- Correctness is derived from the private answer key stored for the attempt.
- Browser requests contain only action, session token, game ID, mode (start), and question/choice indexes (answer).
- Scores, maximum scores, student/teacher identity, points, and correctness are never trusted from the browser.
- Number Challenge v1 remains 15 questions with a maximum score of 41, including its existing streak and final-question bonuses.
- A completed attempt awards exactly its verified score once. A zero-score completion records the attempt but creates no zero-point ledger row, consistent with the current schema proposal.
- Identical retries are idempotent; changed duplicate answers and out-of-order submissions are rejected.
- Database changes must be atomic: answer state, attempt totals/status, session consumption, and the single points-ledger insert commit or roll back together.

These are design decisions, not evidence that the proposed SQL routines exist in the live database.

## 2. Required correction A — consistent lock order and membership revalidation

### Problem

The current SQL draft locks the game-session row first and reads class/student active state and membership without locking those rows. This conflicts with the classroom transaction review's global **class-before-student** lock order and leaves a race with student transfer or class/student deactivation.

### Required transaction protocol

Both `begin_game_attempt` and `record_game_attempt_answer` must use one documented lock order compatible with every existing classroom transaction:

1. Resolve the candidate session/student/class identifiers without treating that read as authoritative.
2. Lock the class row first (`FOR UPDATE`).
3. Lock the student row second (`FOR UPDATE`).
4. Lock the game-session row third (`FOR UPDATE`).
5. Lock the attempt row fourth (`FOR UPDATE`), if it exists.
6. Lock the current attempt-question row fifth (`FOR UPDATE`), when needed.

After acquiring locks, re-read and validate the relationships and state. In particular:

- The session must still reference the same student and class discovered during lookup.
- The student's current `class_id` must still equal the session's `class_id`.
- The class and student must still be active.
- The session's game ID must match the request; expiry and `used_at` must be checked while the session is locked.
- The attempt must belong to that session and retain the same game, mode, rule version, and expected sequence.
- If any identifier or relationship changed between lookup and lock acquisition, fail closed and do not mutate score or ledger state.

The exact SQL implementation must be checked against the existing approved lock-order specification and every transaction that can transfer/deactivate a student or class. If any existing path uses a different order, stop and reconcile the global order before writing migrations. Do not introduce a local exception that can deadlock.

### Required race tests

- Student transfer races with attempt start.
- Student transfer races with answer submission.
- Class deactivation races with start and answer.
- Student deactivation races with start and answer.
- Two simultaneous starts for the same session.
- Two simultaneous submissions for the same question, both identical and conflicting.
- Final answer races with replay/finalization.
- Confirm no duplicate point transaction and no partial attempt/session mutation.

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

### C. Atomicity and replay
- Inject failures between answer update, attempt completion, ledger insert, and session consumption; assert complete rollback.
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
