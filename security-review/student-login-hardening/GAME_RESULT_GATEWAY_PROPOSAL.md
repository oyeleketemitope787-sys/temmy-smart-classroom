# Game Result Gateway Proposal

**Status:** Review-only implementation scaffold; deliberately fail-closed  
**Branch:** `security-review/student-login-hardening`  
**Not deployed. No database DDL, permissions, secrets, production code, or student records changed.**

## Files added or updated

- `supabase/functions/game-result-gateway/index.ts` — HTTP handler; valid requests deliberately receive HTTP 503 and no database call is made.
- `supabase/functions/game-result-gateway/validation.ts` — strict request-shape validation for `start_attempt` and `submit_answer`.
- `supabase/functions/game-result-gateway/validation_test.ts` — request-contract tests.
- `supabase/functions/game-result-gateway/question-generator.ts` — fresh 15-question number-challenge generator; correct choice index is for protected server state and must not be returned to the browser.
- `supabase/functions/game-result-gateway/question-generator_test.ts` — generator shape and semantic-answer tests across deterministic test seeds.
- `security-review/student-login-hardening/GAME_RESULT_PROTOCOL_PROPOSAL.md` — proposed step-based API and migration gates.
- `security-review/student-login-hardening/GAME_RESULT_ATTEMPT_SCHEMA_PROPOSAL.sql.txt` — non-executable DDL draft outside the Supabase migrations directory.
- `security-review/student-login-hardening/GAME_RESULT_GATEWAY_PROPOSAL.md` — this review record.

## Request contract

The request validator allows only:
- `start_attempt`: `session_token` and the approved `game_id`.
- `submit_answer`: those fields plus the current `question_index` and selected `choice_index`.

It rejects client-supplied score, maximum score, student/teacher identity, transaction label, answer-correctness claims, unsupported actions and extra fields. This is only request-shape validation; a valid request is not trusted until the server validates session and attempt state.

## Why awarding remains disabled

The current public game source embeds fixed question prompts, choices, correct-answer strings and a local score counter. It reads a session token but does not visibly submit results. The Classroom source creates sessions and constructs game URLs, but the deployed result-submission caller is still unidentified.

The newly added generator makes fresh values and shuffles option order. The trusted caller would store the correct choice index in protected per-attempt state and return only prompt/options/hint to the browser. The current live game HTML has not been changed; a separate, reviewed client patch is still required.

The handler deliberately uses no Supabase client, service-role key or database call. It returns HTTP 503 for structurally valid requests. Do not remove this fail-closed behavior until the attempt-state schema, atomic answer function, scoring policy, caller migration, ACL plan and isolated tests are complete.

## Scoring policy still requires approval

The visible game has 15 questions but adds streak and final-question bonuses, then displays the score as `/15 points`. This is inconsistent.

Recommended decision for owner approval: official score/points equal the number of correct answers out of 15; streak and celebration bonuses are visual-only. **This recommendation has not been approved.** The proposed schema leaves award fields null until the official rule is confirmed. Do not make an award based on an assumed rule.

## Database and authorization gates

1. Apply no SQL. The schema draft is deliberately outside the migrations directory and uses a `.sql.txt` suffix.
2. Future server functions must derive student, class and game identity from the stored session; validate session expiration, use state, active class/student, sequence order and answer bounds; store correctness based on the protected per-attempt answer key; and make answer submission, session consumption and final award atomic.
3. A repeated identical answer may be idempotent; a conflicting duplicate, skipped question or replay must not earn additional credit.
4. Current effective privileges show `anon EXECUTE = true` for `record_student_game_result`. Do not revoke that permission until legitimate deployed callers have been located and migrated together.
5. Authenticated users currently have direct INSERT permission on `point_transactions` under an RLS check for teacher ownership and student/class membership. The inspected Classroom client uses direct inserts for teacher adjustments and activity scoring with `source = 'teacher'`. Narrowing this policy requires a separately reviewed migration that preserves those flows.
6. Public/practice gameplay must remain available without a student-linked reward session and must never award student points by itself.
7. The historical `24/15` point transaction remains unexplained. The current result function would cap `p_score=24, p_max_score=15` at 15, but this alone does not identify the historical write path.

## Tests and validation status

Test files include:
- Nine validation contract cases for valid start/answer requests and malformed, out-of-range, identity/score injection, unsupported-action and extra-field requests.
- Three generator tests, including 200 deterministic runs checking 15 sequential questions, four distinct options, in-range correct-choice indexes, semantic answer validity, and variation across seeds.

**Tests have been authored but not executed** because the Deno runtime is not available in this environment. No build or runtime success is claimed.

## Current decision

**NO-GO for release.** The gateway is not deployed and awards no points. The database schema and functions, game-client migration, point-award integration, ACL changes and production deployment are not implemented.
