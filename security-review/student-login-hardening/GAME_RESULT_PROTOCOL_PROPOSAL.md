# Step-Based Game Result Protocol Proposal

**Status:** Design/review only. No deployment, database DDL, grants, point writes, or production changes.
**Game:** `grade3-temmy-number-challenge`
**Review branch:** `security-review/student-login-hardening`

## Why the current approach is insufficient

The inspected game source embeds all 15 prompts, answer options, correct-answer strings, and a local score counter in browser JavaScript. It reads a session token from the URL but does not contain a visible call that submits a score. A final request containing `score`, `max_score`, or the entire answer list would still let the browser dictate the claimed result.

The request validator therefore uses a step-based contract. The Edge Function has a staged RPC path that remains disabled unless both server-side feature flags are explicitly set; neither flag is configured and the function is not deployed.

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

The generator uses Web Crypto through `crypto.getRandomValues` by default. Tests can inject deterministic randomness. A local TypeScript/Node harness passed semantic checks across 10,000 deterministic seeds (150,000 generated questions); the checked-in Deno tests have not yet been run with Deno. The current public HTML remains unchanged; it still uses its original fixed question set. It must not be switched to this protocol until a separate, reviewed client patch is prepared in the game repository.

Randomized prompts are not a guarantee that a human personally played the game. They make each attempt distinct and ensure that the **server** verifies answers instead of accepting a browser-calculated score. The protocol's purpose is to protect point-record integrity, not to claim perfect anti-cheating.

## Proposed data model

See `GAME_RESULT_ATTEMPT_SCHEMA_PROPOSAL.sql.txt` for the non-executable catalogue/attempt schema draft and `GAME_RESULT_ATOMIC_FUNCTIONS_PROPOSAL.sql.txt` for the non-executable atomic RPC draft.

- `student_game_attempts`: one attempt per existing game session; stores sequence state, completion status, and verified correct-answer count.
- `student_game_attempt_questions`: per-attempt prompt, options, correct choice index, submitted choice, and server-computed correctness.
- Both tables have RLS enabled and no direct browser-role table privileges. Browser calls go through reviewed server functions only.
- An atomic answer function must lock the session and attempt, validate current index and session state, derive correctness from the stored answer key, persist the answer once, advance counters, and consume the session on completion.
- The answer key must be stored in protected state and never included in API responses before answer submission.

The SQL file is deliberately placed under `security-review`, outside any migration directory. It is not intended to be executed as-is.

## Central scoring contract — owner-approved rule

The owner has clarified the product rule: **record the actual verified score and reward that score as points. The maximum is game-specific, not globally fixed at 15.** Central scoring is responsible for presenting the score and correct maximum consistently across the platform.

### Contract

- The browser sends only a session token, registered game ID, and one answer per request. It never supplies the official score, maximum, reward points, student/teacher identity, or whether an answer is correct.
- The trusted server verifies the submitted answer against the protected attempt answer key and applies the scoring rule registered for that game.
- The server returns and records the exact verified score and that game's configured maximum.
- **Awarded points equal the exact verified score. Do not silently clamp a valid score.**
- The maximum is loaded from the server-controlled scoring catalogue and cannot be selected by the caller.
- If a score is above the game's configured maximum, reject the result and do not award points. Do not rewrite it to the maximum.
- Each registered game must have an immutable/versioned scoring rule. A game out of 20 with no bonuses has maximum 20; a verified 16/20 is recorded as 16/20 and awards 16 points.
- Bonus points are part of the actual score when the game's registered rule awards them. In that case, the configured maximum and displayed denominator must include the maximum achievable bonus. No screen should display 24/15 when the scoring rule permits a score of 24.

### Current Number Challenge scoring rule

The source currently awards one base point for each correct answer, an additional point when the correct-answer streak is at least three, another additional point when the streak is at least five, and two additional points for a correct final question. Its maximum all-correct score is:

- 15 base points
- 13 streak bonuses for questions 3–15
- 11 further streak bonuses for questions 5–15
- 2 final-question bonus points
- **Maximum: 41 points**

The review branch's central scoring catalogue therefore registers this version as max_score 41, rule_version number-challenge-streak-v1. A verified 24-point result under this exact rule is recorded as 24 points and displayed as 24/41, not capped to 15 or mislabeled 24/15. If the game design later changes its bonus rules, the catalogue version and maximum must be updated and tested together.

A different game that is genuinely scored out of 20 without score bonuses registers max_score 20. Its maximum must not be inherited from Number Challenge.

### What this means for the historical transaction

The historical 24-point transaction is not automatically an invalid reward merely because the source displayed 24/15; the current browser scoring algorithm can generate bonus totals greater than 15. However, its historical submission/write path remains unverified, and the recorded denominator 15 is inconsistent with the current bonus rule. Preserve the transaction history while tracing the caller and legacy function version. Do not delete, reduce, or otherwise adjust that record without a separate evidence-based, owner-approved correction.

The central scoring module now contains:
- scoring-contract.ts: server-owned game catalogue, game-specific maximum, exact-score reward result, Number Challenge v1 bonus calculation, and central score-display values.
- scoring-contract_test.ts: tests for exact score reward, 16/20 behavior, unknown games, invalid values, out-of-range scores, streaks, the 41-point perfect-run maximum, and display labels.

The score helper and central response contract are in the review branch. The Edge Function includes a staged RPC path but defaults to HTTP 503 without a database call unless both server-side feature flags are explicitly enabled. They have not been configured and the function is not deployed.

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
- Gateway: default-disabled behind two server-side feature flags; with either flag unset, returns HTTP 503 without a database call. The staged RPC path has not been deployed or invoked.
- Database schema/functions, client migration, RPC permission changes, point awarding, and deployment: not implemented.
- Release decision: **NO-GO**.
