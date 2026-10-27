# Game Result Gateway Proposal

**Status:** Review-branch implementation proposal; default-disabled with two server-side feature flags  
**Branch:** `security-review/student-login-hardening`  
**Not deployed. No database DDL, permissions, secrets, production code, or student records changed.**

## Files added or updated

- `supabase/functions/game-result-gateway/index.ts` — Edge Function handler. Unless BOTH `GAME_RESULT_GATEWAY_READY=true` and `GAME_RESULT_WRITE_ENABLED=true` are set in the server environment, requests fail with HTTP 503 and no database call is made. Neither flag has been configured and the function is not deployed.
- `supabase/functions/game-result-gateway/validation.ts` — strict request-shape validation for `start_attempt` (including the selected mode) and `submit_answer`.
- `supabase/functions/game-result-gateway/validation_test.ts` — request-contract tests.
- `supabase/functions/game-result-gateway/question-generator.ts` — fresh 15-question number-challenge generator; correct choice index is for protected server state and must not be returned to the browser.
- `supabase/functions/game-result-gateway/question-generator_test.ts` — generator shape and semantic-answer tests across deterministic test seeds.
- `supabase/functions/game-result-gateway/scoring-contract.ts` — central per-game scoring catalogue, variable maximum, exact score-to-points rule, and Number Challenge bonus calculation.
- `supabase/functions/game-result-gateway/scoring-contract_test.ts` — tests exact score-to-points, variable maximums, invalid/out-of-range scores, bonus scoring, and central score display labels.
- `security-review/student-login-hardening/GAME_RESULT_PROTOCOL_PROPOSAL.md` — proposed step-based API and migration gates.
- `security-review/student-login-hardening/GAME_RESULT_ATTEMPT_SCHEMA_PROPOSAL.sql.txt` — non-executable schema/catalogue draft outside the Supabase migrations directory.
- `security-review/student-login-hardening/GAME_RESULT_ATOMIC_FUNCTIONS_PROPOSAL.sql.txt` — non-executable draft for atomic begin/answer/award functions.
- `security-review/student-login-hardening/CENTRAL_SCORING_INTEGRATION_PROPOSAL.md` — response contract and central display examples.
- `security-review/student-login-hardening/GAME_RESULT_GATEWAY_PROPOSAL.md` — this review record.

## Request contract

The request validator allows only:
- `start_attempt`: `session_token`, a registered game ID, and `mode` set to `practice`, `challenge`, or `class`.
- `submit_answer`: session token, registered game ID, current `question_index`, and selected `choice_index`, bounded by that game's registered question count.

It rejects client-supplied score, maximum score, student/teacher identity, transaction label, answer-correctness claims, unsupported actions and extra fields. This is only request-shape validation; a valid request is not trusted until the server validates session and attempt state.

## Why awarding remains disabled

The current public game source embeds fixed question prompts, choices, correct-answer strings and a local score counter. It reads a session token but does not visibly submit results. The Classroom source creates sessions and constructs game URLs, but the deployed result-submission caller is still unidentified.

The newly added generator makes fresh values and shuffles option order. The trusted caller would store the correct choice index in protected per-attempt state and return only prompt/options/hint to the browser. The current live game HTML has not been changed; a separate, reviewed client patch is still required.

The handler contains a staged Supabase RPC path, but it is disabled by default. It returns HTTP 503 without calling Supabase unless BOTH `GAME_RESULT_GATEWAY_READY=true` and `GAME_RESULT_WRITE_ENABLED=true` are set in the Edge Function's server environment. Neither flag has been configured, the handler is not deployed, and no RPC calls have been made. Rate limiting and other endpoint abuse controls are not implemented. Do not set these flags until the proposed schema/functions are implemented in an isolated environment, tests pass, rate limiting is designed and verified, the game client is migrated, and the ACL rollout is separately reviewed.

## Central scoring policy — owner-approved

The owner has approved the governing rule: **award the exact score verified by trusted server logic, with a game-specific maximum.** There is no universal 15-point cap and no silent clamping.

- Game configuration on the trusted side defines the question count, scoring rule version, and actual maximum achievable score.
- The central platform stores and displays both verified score and configured maximum. For a no-bonus game out of 20, 16 correct points are recorded as 16/20 and 16 points are awarded.
- If a game's scoring formula includes bonus points, its configured maximum includes those points. The current Number Challenge bonus algorithm has a theoretical all-correct maximum of 41 (15 base + 13 streak bonuses + 11 further streak bonuses + 2 final bonus). Under this rule, a verified score of 24 is 24/41, awarded as 24 points, not clamped to 15 or displayed as 24/15.
- A verified score outside the configured range is rejected with no award; never silently replace it with the maximum.
- Unknown or unregistered games are rejected; there is no fallback maximum.
- These rules do not authorize trusting a client-reported score. Correctness and score must be calculated from trusted server-side attempt state.

The central scoring module is present in scoring-contract.ts with rule version number-challenge-streak-v1 for the current game, exact score-to-points output, and a score display contract that returns labels such as 24/41 and 16/20. The staged handler calls the central score-result/display helper to check the committed result, but per-answer bonus logic is mirrored in the SQL draft and TypeScript reference helper. Those rules need explicit parity tests before release. The HTTP gateway remains disabled by default and returns 503 without database calls while either feature flag is unset.

## Database and authorization gates

1. Apply no SQL. The schema draft is deliberately outside the migrations directory and uses a `.sql.txt` suffix.
2. Future server functions must derive student, class and game identity from the stored session; validate session expiration, use state, active class/student, sequence order and answer bounds; store correctness based on the protected per-attempt answer key; and make answer submission, session consumption and final award atomic.
3. A repeated identical answer may be idempotent; a conflicting duplicate, skipped question or replay must not earn additional credit.
4. Current effective privileges show `anon EXECUTE = true` for `record_student_game_result`. Do not revoke that permission until legitimate deployed callers have been located and migrated together.
5. Authenticated users currently have direct INSERT permission on `point_transactions` under an RLS check for teacher ownership and student/class membership. The inspected Classroom client uses direct inserts for teacher adjustments and activity scoring with `source = 'teacher'`. Narrowing this policy requires a separately reviewed migration that preserves those flows.
6. Public/practice gameplay must remain available without a student-linked reward session and must never award student points by itself. The proposed protocol preserves the current Number Challenge modes: practice/class modes run through the configured question count, while challenge mode completes early after three incorrect answers. The exact verified score earned so far is still awarded on an early completion.
7. The historical `24/15` transaction's write path remains unexplained. The 24-point value itself is consistent with the current local bonus algorithm; the denominator `15` is inconsistent with its theoretical maximum of 41. The current database result function would cap arguments `24, 15` at 15, so it does not explain that stored value with those exact arguments.

## Tests and validation status

The earlier generator branch was checked with a local harness across 10,000 deterministic seeds (150,000 generated questions). The current branch includes 14 request-validation cases and 11 central scoring/display cases, including mode validation, prototype-property game IDs, a 16/20 reward, and the Number Challenge 41-point maximum. These newly added scoring and validation tests have not been executed in this environment.

The checked-in Deno test files currently contain 15 request-validation cases, three generator tests, and 11 scoring/display tests. **The Deno test runner has not been executed** because Deno is not installed in this environment. No compile or runtime success is claimed for the latest scoring-contract changes, and there are no isolated database end-to-end test results yet.

## Current decision

**NO-GO for release.** The gateway is not deployed and awards no points. The database schema and functions, game-client migration, point-award integration, ACL changes and production deployment are not implemented.
