# Temmy Smart Classroom — Game Feature Reconciliation and Classroom Launch Gate

**Review date:** 2026-11-22  
**Status:** Authoritative reconciliation of prior decisions and source findings; design/documentation only. Not implementation approval, SQL execution approval, or deployment approval.  
**Repository:** `oyeleketemitope787-sys/temmy-smart-classroom`  
**Branch:** `security-review/student-login-hardening`  
**Protected branches:** `main` and `cloud-test` remain untouched.  
**Hosted database:** No queries, writes, migrations, grants/revokes, secrets, feature flags, or deployment were performed for this reconciliation.

## 1. Purpose and precedence

This document reconciles the existing Smart Classroom game-assignment and Student Portal code, the separate TEST repository, the November 2026 read-only security reviews, and the user-approved assigned-game scoring decisions.

It does not replace historical evidence. It establishes the current design interpretation where older examples conflict with later user-approved decisions.

Precedence for the current game/reward design:

1. User-confirmed product policy: only assigned games may generate Classroom points; only Challenge is assigned, and it is assigned to the whole class.
2. User-approved exact-score scoring contract and zero-score ledger policy.
3. User-approved request-idempotency design and transaction pseudocode.
4. Corrected global classroom lock order and subsequent security corrections.
5. Earlier protocol examples, schema drafts, test fixtures and legacy game code, which must be corrected where they conflict with the above.

The existing Classroom must be made independently launch-ready. The retired/legacy game client must not become a dependency for that launch. A new Temmy Smart Games product is a separate post-Classroom project and will connect through the future Temmy Gateway under a separately approved integration plan.

## 2. Repositories and sources inspected

### Main Smart Classroom repository

- `cloud-test/index.html`, blob SHA `9fc70a0ae617472904e0b96910940adab4553df9`, reviewed build header V8.9.2.
- The teacher-side `openGameLauncher` calls `start_teacher_game_session` separately for selected students and creates a game URL at `https://games.stgloriousschool.org/games/temmy-number-challenge.html` with the session token in the `session` query parameter.
- The Student Portal calls `get_student_game_sessions`, displays assigned sessions, and constructs an Open Game link using the returned session token.
- The reviewed classroom HTML does not itself call `record_student_game_result`.
- The deployed game URL could not be retrieved through the available source-inspection route in this review. Its exact live HTML, result caller and deployed build remain unverified.

Source: [cloud-test/index.html](https://github.com/oyeleketemitope787-sys/temmy-smart-classroom/blob/cloud-test/index.html).

### Separate TEST repository

Repository: `oyeleketemitope787-sys/temmy-smart-classroom-test`, inspected at commit `397047c2e38734d0551cf545cea5903defdc9d62`.

- `index.html` contains the per-student teacher game launcher and Student Portal assigned-game display.
- `test-games/grade3/temmy-number-challenge.html`, blob SHA `6473b0899942047df378179e639bf26b1e5d8745`, contains a local game score and a direct browser call to `record_student_game_result`.
- `supabase/migrations/202610090001_secure_game_result_recording.sql` is an earlier manual review script.
- `supabase/migrations/202610090002_harden_grade3_game_result_recording.sql`, blob SHA `b7b5acb8a8abeb7cb9b689c1a5ed3a3efd3bcc09`, explicitly says REVIEW FILE ONLY / DO NOT EXECUTE.
- `docs/TEST_ONLY_FINAL_GAME_LAUNCH_FLOW_REVIEW.md` is a static review, not launch approval.
- `docs/TEST_ONLY_DATABASE_FUNCTION_INVENTORY.md` is a source/function review, not a deployed permission audit.

Sources:
- [TEST-only final game launch review](https://github.com/oyeleketemitope787-sys/temmy-smart-classroom-test/blob/397047c2e38734d0551cf545cea5903defdc9d62/docs/TEST_ONLY_FINAL_GAME_LAUNCH_FLOW_REVIEW.md)
- [TEST game client](https://github.com/oyeleketemitope787-sys/temmy-smart-classroom-test/blob/397047c2e38734d0551cf545cea5903defdc9d62/test-games/grade3/temmy-number-challenge.html)
- [TEST-only hardening migration 002](https://github.com/oyeleketemitope787-sys/temmy-smart-classroom-test/blob/397047c2e38734d0551cf545cea5903defdc9d62/supabase/migrations/202610090002_harden_grade3_game_result_recording.sql)

### Review-branch scoring architecture

- [Assigned-games policy decision](https://github.com/oyeleketemitope787-sys/temmy-smart-classroom/blob/7e489e79c23815571ef2e1c0a7a5a3c2734a0111/security-review/student-login-hardening/CENTRAL_SCORING_ASSIGNED_GAMES_POLICY_DECISION_2026-11-12.md)
- [Transaction-level pseudocode review](https://github.com/oyeleketemitope787-sys/temmy-smart-classroom/blob/170c1ad/security-review/student-login-hardening/GAME_SCORING_TRANSACTION_PSEUDOCODE_REVIEW.md)
- [Correction design and implementation plan](https://github.com/oyeleketemitope787-sys/temmy-smart-classroom/blob/security-review/student-login-hardening/CENTRAL_GAME_SCORING_CORRECTION_DESIGN.md)
- [Step-based protocol proposal](https://github.com/oyeleketemitope787-sys/temmy-smart-classroom/blob/security-review/student-login-hardening/GAME_RESULT_PROTOCOL_PROPOSAL.md)
- [Gateway proposal](https://github.com/oyeleketemitope787-sys/temmy-smart-classroom/blob/security-review/student-login-hardening/GAME_RESULT_GATEWAY_PROPOSAL.md)
- [Rate-limit and abuse-control design](https://github.com/oyeleketemitope787-sys/temmy-smart-classroom/blob/security-review/student-login-hardening/CENTRAL_SCORING_RATE_LIMITING_ABUSE_CONTROL_DESIGN.md)
- [Game scoring lock-order audit](https://github.com/oyeleketemitope787-sys/temmy-smart-classroom/blob/b58813ef3a8dadd5a6f1f8a4623106c07f074980/security-review/student-login-hardening/GAME_SCORING_LOCK_ORDER_AUDIT_2026-11-12.md)

## 3. Actual legacy Classroom game flow

The reviewed Classroom flow currently has these stages:

1. Teacher selects a class in Learning Activities and opens Start Temmy Smart Game.
2. The current UI lets the teacher select individual students using checkboxes, Select All and Clear All.
3. The browser calls `start_teacher_game_session(p_student_id, p_game_id)` once per selected student.
4. Each successful call returns a session token with a 30-minute expiry.
5. The browser places that token in the game URL query string.
6. The Student Portal calls `get_student_game_sessions(p_access_code)`, receives the student's unexpired/unused sessions, and displays Open Game links.
7. The separate game page reads the token and, in the TEST client, calls the legacy result RPC at game completion.

This proves that assignment/session creation and Student Portal display exist in the reviewed source. It does not prove that the deployed production game client is identical to the TEST client or that its result call is currently active.

## 4. Legacy game result path — not acceptable as the future trusted scoring boundary

The TEST game page:

- embeds fixed questions and correct-answer strings in browser JavaScript;
- calculates `correctCount` and arcade score locally;
- sends `p_score`, `p_max_score`, `p_game_id` and `p_game_name` directly from the browser to `record_student_game_result`;
- has a page-local `submissionStarted` guard, which is not durable server idempotency;
- calls the result RPC whenever a classroom session token exists, without making reward eligibility depend on the selected gameplay mode.

The old client displays an official score based on correct answers out of 15 and keeps streak/final-question bonuses as a separate arcade score. This differs from the later user-approved Number Challenge v1 central scoring contract, whose verified score includes the approved bonuses and has a maximum of 41.

The earlier TEST migration 001 accepts caller-provided score, maximum, game ID and game name, and has weak session/class/student revalidation. Migration 002 improves the server-side constants to one game and a 15-point maximum, rejects out-of-range input, and revalidates active student/class relationships, but it still trusts the browser-supplied score and does not verify individual answers against a protected server-held answer key. It also grants the legacy RPC to browser roles. Neither file is evidence that the function was deployed.

**Conclusion:** the legacy client + legacy RPC path must not be treated as the secure automatic scoring implementation. Do not deploy either TEST migration as a shortcut and do not use the old RPC as the future scoring authority.

## 5. User-approved gameplay and reward policy — authoritative

| Gameplay context | Classroom assignment | Classroom reward |
|---|---|---|
| Public practice | None | Never |
| Student practice | None | Never |
| Challenge | Teacher assigns to the entire class | Verified final score only |
| Class mode | Not an assigned mode | Never |
| Group Challenge | Competition-only; speed contributes to competition results | Not written to Classroom points/history |

Additional rules:

- A student login alone does not make a practice game reward-eligible.
- A mode string supplied by the browser is not proof of assignment.
- Only a valid, trusted Classroom assignment/session can make a Challenge attempt reward-eligible.
- Each student in the assigned class has an individually verified attempt and result.
- A class assignment must not silently become a collection of teacher-selected individual assignments.
- Group Challenge is outside the Classroom points ledger and outside this assigned-game reward flow.

**Required reconciliation:** older examples in the protocol, SQL drafts, tests and Gateway contract use `practice` or `class` as modes for reward-capable sessions. Those examples conflict with the later user-approved policy and must be corrected. For the current release, only an assigned Challenge attempt may enter the reward-scoring Gateway. Public/student practice and Class mode remain outside it.

## 6. User-approved score and ledger policy

- The server verifies every submitted answer using protected attempt state; the browser never supplies an authoritative score, maximum, correctness flag, student/teacher identity or points award.
- Number Challenge v1 has 15 questions and a maximum verified score of **41**, including its approved streak and final-question bonuses.
- The exact verified score is the points award; no silent clamping.
- A score above the registered maximum, unknown game, invalid attempt or mismatched scoring-rule version is rejected with no award.
- The game-specific maximum and immutable scoring-rule version come from a trusted server-controlled catalogue.
- A completed zero-score attempt is recorded with `points_awarded = 0` and no zero-point `point_transactions` row.
- A positive completed score creates exactly one ledger award, linked to the completed attempt.
- Attempt completion, session consumption, idempotency outcome and the single positive ledger insert commit or roll back together.
- No points are shown as awarded until the database transaction commits and the Gateway validates the committed result.

**Required reconciliation:** the legacy TEST game client and TEST migration 002 use an official 15-point score and exclude arcade bonuses. They are historical/legacy evidence, not the current approved scoring contract.

## 7. Required class-wide assignment correction

The current teacher UI permits individual selection and the existing RPC is called once per student. This conflicts with the approved class-wide Challenge assignment policy.

The future Classroom assignment workflow must:

1. Let the teacher select one class and one registered game.
2. Create one auditable class-level assignment event for Challenge.
3. Snapshot the eligible active students in that class at assignment time.
4. Issue one student-bound, short-lived session for each eligible student.
5. Preserve the parent class assignment identity on every child session/attempt/result.
6. Avoid silently leaving the class partially assigned. A trusted operation must either create the assignment and its eligible student sessions atomically, or return explicit per-student failure outcomes with an auditable partial state and safe retry semantics.
7. Prevent a student from changing the assigned mode or game from the browser.
8. Make the Student Portal show only the current student's assigned session and status.

The exact parent assignment schema and whether the first release requires all-or-nothing or explicitly tracked partial issuance remain design items. Do not add tables or change the existing RPC signature without reviewing the actual schema and caller map.

## 8. Gateway and attempt design — current state versus required corrections

### Implemented review-branch scaffolding

- Edge Function request handler with a two-flag fail-closed gate.
- Request-shape validation for `start_attempt` and `submit_answer`.
- Server-side Number Challenge question generator.
- Per-game scoring catalogue and exact score-to-points helper.
- Attempt-response validation and score display helper.
- Deno tests for validation, question generation and scoring/display.

The review-branch Gateway returns HTTP 503 before any Supabase call unless both `GAME_RESULT_GATEWAY_READY=true` and `GAME_RESULT_WRITE_ENABLED=true` are set. Neither flag has been configured; the function is not deployed.

GitHub Actions reported 34 Deno tests passed, and the Gateway entrypoint type-check passed on the documented review commit. These are unit/type-check results only. They are not PostgreSQL integration tests, Edge runtime tests, deployed endpoint tests, or proof of automatic points recording.

### Required code/schema corrections before implementation approval

1. Add the approved UUID `request_id` to every logical start/answer request, validator type, Gateway call, and database function signature. Reuse the same ID only for retries of the same logical operation.
2. Persist a canonical request fingerprint and terminal safe outcome; same key/same payload returns the original result, while same key/different payload rejects without mutation.
3. Use a server-held HMAC key and versioned canonical encoding; verify runtime/extension availability and key rotation in a disposable environment. Never store raw session tokens or answer keys in idempotency rows.
4. Enforce the assigned-Challenge-only policy in trusted state. Do not allow `practice` or `class` to create reward-capable attempts. The browser's mode field is not an authorization decision.
5. Correct the SQL draft lock order to: idempotency request row → class row(s) in stable UUID order → student row → game-session row → attempt row → question row → writes.
6. Re-read and revalidate class/student/session relationships after locks. A transfer/deactivation race must abort safely without score or ledger mutation.
7. Keep answer keys private; validate the full server-generated question set before attempt creation.
8. Add a unique one-attempt-per-session constraint and a unique award reference so no attempt can produce more than one positive ledger award.
9. Keep answer/attempt/idempotency tables inaccessible to browser roles; only the intended backend role may execute scoring functions. Explicitly review function owner, fixed empty `search_path`, schema-qualified names, RLS, effective ACLs and default PUBLIC EXECUTE.
10. Replace the current public response with a fresh explicit allowlist. Do not return `ok`, raw database messages, IDs, session tokens, attempt IDs, answer keys, transaction IDs or arbitrary database properties.
11. Replace the current all-errors-as-HTTP-400 behavior with safe client errors, 409 conflicts, 429 rate limits, retryable 5xx for transient failures, and generic 503 for configuration/schema faults.
12. Implement shared/durable ingress and session-scoped abuse controls; no per-instance memory counters. Do not trust caller-supplied forwarded headers. Thresholds, ingress provider, log retention and alert ownership still require approval.
13. Add a cheap start-admission check before expensive question generation.
14. Prove HMAC, idempotency, response projection, error mapping, retry, replay, concurrency, transfer/deactivation and rollback behavior in an isolated environment.
15. Inventory and migrate every real game client before any legacy RPC permission change. Preserve the existing teacher award/activity scoring flows; do not apply a blanket revoke to direct point-ledger writes.

### Specific contradictions found in the current review artifacts

- `GAME_RESULT_PROTOCOL_PROPOSAL.md` shows `mode: "practice"` for an assigned attempt.
- `CENTRAL_SCORING_INTEGRATION_PROPOSAL.md` contains a completed example with `mode: "class"`.
- `GAME_RESULT_GATEWAY_PROPOSAL.md`, `validation.ts`, `scoring-contract.ts`, schema/function drafts and smoke tests permit or use `practice`, `challenge` and `class` on reward-capable attempts.
- The smoke/concurrency SQL uses `practice` for positive points awards.
- The current Classroom teacher launcher allows individual student selection.
- The legacy TEST game submits a client-computed 0–15 score, whereas the approved server-side scoring contract is 0–41 for Number Challenge v1.
- The Gateway validator and SQL signatures still omit `request_id`, despite the approved idempotency design.
- The SQL function draft is session-first and conflicts with the approved idempotency → class → student → session → attempt → question lock order.
- The current Gateway code returns `ok` and maps RPC failures to HTTP 400, contrary to the later strict response allowlist and error taxonomy.
- The rate-limit and abuse controls remain design-only.

These are design inconsistencies, not evidence that the later approved policy or Gateway has been deployed.

## 9. Security and database readiness — last verified evidence

### Phase A live database snapshot (2026-11-10)

The read-only Phase A report identifies the reviewed Supabase project as `temmy-smart-classroom-test`, but the dashboard environment label observed was `main / PRODUCTION`. The project reference was separately identified in the TEST repository review as `askhdgmjqezvwavfhqzj`. It must not be treated as a safe test database.

The 10 November snapshot reported:

- 16 public tables with RLS enabled, but FORCE RLS disabled; all were owned by `postgres`.
- 20 public function rows, all `SECURITY DEFINER` and owned by `postgres`; the owner has `BYPASSRLS`.
- Explicit PUBLIC/anonymous EXECUTE on sensitive functions including `record_student_game_result`, `start_student_game_session` and `get_student_game_sessions`.
- Direct browser writes to `point_transactions` for teacher awards/deductions, undo rows and activity-score deltas.
- Separate browser writes to activity records and point transactions, which are not atomic.
- Student access codes with 32-bit effective entropy and no visible custom rate limiter in the inspected functions.
- Marketplace and punctuality integrity gaps.
- A Data API dashboard exposure count that did not reconcile with effective database grants.
- No deployed Edge Functions in the selected dashboard view at the time of inspection.
- No live concurrency, failure-injection, penetration or load tests.

These are dated read-only observations, not a current 22 November live-state claim. They must be refreshed by a safe read-only verification before launch sign-off.

### Database integration test readiness

The database integration readiness review states that:

- the repository snapshot does not contain an authoritative production schema/migration history;
- exact columns/types and constraints for sessions, students, classes and point transactions remain to be verified;
- point-ledger constraints, triggers and zero-score behavior were not verified against the live schema;
- no isolated Supabase database was available;
- the Gateway SQL drafts had not been executed or database-integration-tested.

Do not use the project labelled PRODUCTION, shared Classroom backend, or `temmy_classroom_local` for scoring, replay, concurrency, lockout or attack tests. No Gateway feature flag may be enabled on the basis of source inspection or Deno unit tests.

## 10. Classroom launch decision and separation from future Smart Games

The approved product sequence is:

1. Make Temmy Smart Classroom independently launch-ready.
2. Do not make the retired/legacy game platform a dependency of the Classroom launch.
3. After Classroom launch, build Temmy Smart Games as a new, separate product.
4. Integrate the new game product through the future Temmy Gateway using the assigned-Challenge policy, server-verified scoring, request idempotency, safe session exchange and one-time points award.
5. Keep Temmy Teaching Hub as a separately designed product; neither product's business logic is moved into the central integration core by this game review.

**Recommended first-release treatment:** keep the legacy game assignment/reward route disabled or clearly unavailable for the initial Smart Classroom release. Preserve historical records and code for controlled reference; do not delete or migrate the legacy game client. This is the safest way to launch the Classroom independently without claiming that automatic game scoring is secure or operational.

This recommendation does not itself authorize changing the protected `cloud-test` or `main` application. The exact UI treatment (hide the launcher, show a disabled/coming-soon state, or another approved presentation) must be included in the separately reviewed Classroom release change set.

## 11. Remaining launch gates

### A. Fresh read-only production verification
- Confirm the exact deployed Classroom HTML/build and database project identity.
- Re-run a read-only inventory of current table columns, constraints, indexes, triggers, RLS policies, table grants, effective function ACLs, function definitions/owners/search paths, default privileges and deployed Edge Functions.
- Reconcile Data API dashboard counts with actual safe HTTP/PostgREST behavior.
- Map all active browser, game-site and external callers for every relevant RPC and direct table write.
- Do not test with real student data or mutate shared records.

### B. Classroom core transaction/security corrections
- Replace direct browser point-ledger mutations with trusted atomic operations only after full caller mapping and an approved rollout.
- Make activity score updates and corresponding ledger deltas atomic.
- Correct award caps, deduction clamping, idempotency, audit and reversal rules.
- Complete student access-code entropy, rate limiting and safe error controls.
- Resolve marketplace purchase, stock and refund integrity.
- Correct punctuality cap/deduction behavior.
- Harden privileged functions and reconcile PUBLIC/default ACLs, RLS and the Data API surface.
- Preserve teacher workflows and historical records; no blanket privilege revocation.

### C. Isolated verification
- Obtain explicit approval for a genuinely isolated disposable PostgreSQL/Supabase-compatible environment with synthetic data only and no production network/credential path.
- Verify the exact schema assumptions before using SQL drafts.
- Run SQL syntax/runtime, ACL, authorization, idempotency, replay, concurrency, transfer/deactivation, failure-injection and rollback tests.
- Retain reproducible test evidence and resolve all failures.

### D. Release preparation
- Produce an exact change list, risk register, rollback plan and post-release verification checklist.
- Verify teacher sign-in, class/student management, points, activities, student portal, messages, marketplace and all other included core workflows.
- Exclude the legacy game reward path from the initial Classroom release unless a separately verified, approved implementation is completed.
- Obtain explicit approval of the exact release change set and deployment target before any production-impacting operation.

## 12. Final status

**Current decision: NOT YET APPROVED FOR SMART CLASSROOM PRODUCTION LAUNCH.**

The game work is now reconciled at the policy/design level. The legacy assignment and browser-score path is not the approved future scoring architecture. The newer Gateway and transaction designs remain review-only and default-disabled. The wider Classroom security snapshot also contains unresolved launch gates and is dated 10 November, so fresh read-only verification is required.

No application, SQL, database, ACL, secret, feature-flag, branch-protected, or deployment change was made by this reconciliation.
