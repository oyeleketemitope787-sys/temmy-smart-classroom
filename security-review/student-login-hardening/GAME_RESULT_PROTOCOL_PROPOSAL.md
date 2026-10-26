# Step-Based Game Result Protocol Proposal

**Status:** Design/review only. No deployment, database DDL, grants, point writes, or production changes.
**Game:** `grade3-temmy-number-challenge`
**Review branch:** `security-review/student-login-hardening`

## Why the current approach is insufficient

The inspected game source embeds all 15 prompts, answer options, correct-answer strings, and a local score counter in browser JavaScript. It reads a session token from the URL but does not contain a visible call that submits a score. A final request containing `score`, `max_score`, or the entire answer list would still let the browser dictate the claimed result.

The new request validator therefore uses a step-based contract. The gateway remains fail-closed and never calls Supabase in this proposal.

## Proposed request contract

### Start an assigned attempt

```json
{
  "action": "start_attempt",
  "session_token": "<UUID bearer token>",
  "game_id": "grade3-temmy-number-challenge"
}
```

The server must validate that the token maps to a session which is unexpired, unused, associated with the approved game, and still linked to an active student in an active class. It then creates or resumes exactly one attempt for that session and generates a fresh question set.

The browser receives only the current question's index, prompt, four options, hint, and total question count. It must not receive `correct_choice_index`, score totals, student IDs, or the stored answer key.

### Submit one answer

```json
{
  "action": "submit_answer",
  "session_token": "<UUID bearer token>",
  "game_id": "grade3-temmy-number-challenge",
  "question_index": 0,
  "choice_index": 2
}
```

The browser submits one option for the server's current question. It does not submit `is_correct`, `score`, `max_score`, `student_id`, `teacher_id`, or `game_name`.

The trusted server retrieves the stored correct choice, calculates correctness, records the answer, and advances the attempt atomically. The server rejects skipped questions, altered game IDs, expired or used sessions, duplicate conflicting answers, invalid choices, and attempts outside the configured question range.

### Retry and duplicate behavior

- Repeating the same answer for a question already recorded may return the stored result idempotently; it must not increment the score twice.
- Sending a different answer for an already answered question is rejected.
- Only the expected current question may be answered.
- The last accepted answer completes the attempt and consumes the session in the same transaction as final result handling.
- Concurrent requests must lock the session/attempt state, so two requests cannot both earn credit for the same question.

## Server-side question generation

The review branch now contains `question-generator.ts`. It creates 15 fresh comparison, ordering, nearest-number, inequality, between-number, greatest-number, and place-value reasoning questions. It returns a `correct_choice_index` for storage by the trusted caller. That key must never be sent to the browser.

The generator uses Web Crypto through `crypto.getRandomValues` by default. Tests can inject deterministic randomness. The current public HTML remains unchanged; it still uses its original fixed question set. It must not be switched to this protocol until a separate, reviewed client patch is prepared in the game repository.

Randomized prompts are not a guarantee that a human personally played the game. They make each attempt distinct and ensure that the **server** verifies answers instead of accepting a browser-calculated score. The protocol's purpose is to protect point-record integrity, not to claim perfect anti-cheating.

## Proposed data model

See `GAME_RESULT_ATTEMPT_SCHEMA_PROPOSAL.sql.txt` for a non-executable DDL draft.

- `student_game_attempts`: one attempt per existing game session; stores sequence state, completion status, and verified correct-answer count.
- `student_game_attempt_questions`: per-attempt prompt, options, correct choice index, submitted choice, and server-computed correctness.
- Both tables have RLS enabled and no direct browser-role table privileges. Browser calls go through reviewed server functions only.
- An atomic answer function must lock the session and attempt, validate current index and session state, derive correctness from the stored answer key, persist the answer once, advance counters, and consume the session on completion.
- The answer key must be stored in protected state and never included in API responses before answer submission.

The SQL file is deliberately placed under `security-review`, outside any migration directory. It is not intended to be executed as-is.

## Scoring rule — product decision still required

The visible game presents 15 questions but local JavaScript adds streak bonuses and a final-question bonus, then displays the result as `/15 points`. This is inconsistent.

**Recommended rule for approval:** official score and classroom points equal the number of correct answers out of 15. Streaks and celebration bonuses may remain visual-only. This recommendation has not been approved in this review.

Until the owner explicitly approves the rule, the proposal must not insert a point transaction or mark an attempt as successfully awarded. Once approved, the final answer, session consumption, result row, and one `point_transactions` insert must happen atomically, with the score constrained by server-controlled catalogue rules. A replay must never create a second point transaction.

## Caller and permission migration gates

1. Keep `record_student_game_result`'s anonymous EXECUTE permission under review; do not revoke it until all real deployed callers have been identified and migrated.
2. Update the game client in a dedicated review branch in `temmy-smart-games`; remove client-side correct-answer data from the reward-enabled client and consume the new step-based endpoint.
3. Keep public/practice play functional with no student session and no points award.
4. Review direct `authenticated` INSERT on `point_transactions`. Existing Classroom code uses it for teacher point adjustments and activity scoring. Any narrowing must preserve those flows and must not treat a browser-provided `source` value as trustworthy.
5. Ensure the database answer/attempt functions are executable only by the intended server role. Explicitly review effective privileges rather than relying on default ACL assumptions.
6. Test in an isolated environment before any shared-database migration. The TEST frontend and production Classroom currently share the same Supabase project, so the shared project is not a safe substitute for an isolated integration test.
7. Explain the historical `24/15` transaction separately; this protocol does not retroactively prove how it was created.

## Current status

- Request validation: implemented on the review branch for `start_attempt` and `submit_answer`.
- Fresh question generator: implemented on the review branch.
- Generator structural tests: added, not yet executed in a Deno runtime.
- Gateway: intentionally returns HTTP 503 for valid requests and performs no database calls.
- Database schema/functions, client migration, RPC permission changes, point awarding, and deployment: not implemented.
- Release decision: **NO-GO**.
