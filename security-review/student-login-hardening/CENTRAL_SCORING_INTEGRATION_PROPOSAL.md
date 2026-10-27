# Central Scoring Integration — Review Proposal

**Status:** Review branch only; not deployed. No shared database or production code changed.

## Owner-approved score/reward contract

The central scoring integration must use the exact score verified by trusted server-side logic and award the same number of points. Every game has its own registered maximum and scoring-rule version.

- Do not hardcode a global maximum of 15.
- The client must not supply the official score, max score, student ID, teacher ID, points awarded, transaction label, or correctness flag.
- The maximum comes from a trusted game catalogue and includes all legitimate bonus points under that rule.
- A verified score above the registered maximum is rejected; it is never silently clamped.
- Unknown or unregistered games fail closed.
- The central UI reads score and maximum from the same result object that was committed to the database.

## Score examples

### Current Temmy Number Challenge rule

The current JavaScript adds one base point per correct answer, one extra point when the streak reaches at least three, another extra point at a streak of at least five, and two extra points for a correct final question. If those rules remain, the theoretical all-correct maximum is 41 points.

~~~json
{
  "status": "completed",
  "game_id": "grade3-temmy-number-challenge",
  "score": 24,
  "max_score": 41,
  "points_awarded": 24,
  "score_rule_version": "number-challenge-streak-v1",
  "score_display": {
    "score_label": "24/41",
    "points_awarded": 24,
    "points_awarded_label": "24 points awarded",
    "max_score": 41,
    "score_rule_version": "number-challenge-streak-v1"
  }
}
~~~

The central platform should display **24/41** and **24 points awarded**, not 24/15. A future Number Challenge redesign may choose a different scoring rule, but the game UI, trusted rule catalogue, database record, and displayed maximum must be updated together.

### Example of a no-bonus game out of 20

This is an example contract, not yet a registered production game.

~~~json
{
  "status": "completed",
  "game_id": "example-game-out-of-20",
  "score": 16,
  "max_score": 20,
  "points_awarded": 16,
  "score_rule_version": "one-point-per-correct-v1",
  "score_display": {
    "score_label": "16/20",
    "points_awarded": 16,
    "points_awarded_label": "16 points awarded",
    "max_score": 20,
    "score_rule_version": "one-point-per-correct-v1"
  }
}
~~~

The example game ID above is only illustrative; it has not been added to the real game catalogue.

## Proposed end-to-end flow

1. The Classroom issues a short-lived session token bound to a student, class, and registered game.
2. The new Game Platform starts an attempt through the Edge Function, passing the session token, registered game ID, and selected mode (`practice`, `challenge`, or `class`). The server stores the mode so it cannot be changed during a retry.
3. The Edge Function validates the request and generates questions on the trusted server. The correct-choice index is never sent to the browser.
4. A server-only database function verifies the session, stores the attempt and answer key, and returns only the question prompt, choices, and hint.
5. The client submits one selected choice at a time. The database function locks the session/attempt, calculates correctness from the stored answer key, and updates the score/streak atomically.
6. The final answer consumes the session and inserts exactly one points transaction in the same database transaction as the completed attempt record. In challenge mode, reaching zero lives after an incorrect answer finalizes early with the actual verified score earned to that point.
7. The central UI receives the committed score, game-specific maximum, points awarded, scoring-rule version, and progress counts (`questions_answered`, `question_count`, `correct_count`) and displays them without hardcoded denominators or falsely showing a full set of answered questions for an early-ended challenge.

Identical retries can return the stored result but must not increment points or create another transaction. A conflicting duplicate answer, skipped question, expired session, reused session, or mismatched game is rejected.

## Review artifacts

- Edge Function handler and two-flag fail-closed gate: supabase/functions/game-result-gateway/index.ts
- Trusted per-game scoring catalogue, exact-score reward contract and display format: supabase/functions/game-result-gateway/scoring-contract.ts
- Request validation: supabase/functions/game-result-gateway/validation.ts
- Server-side Number Challenge question generator: supabase/functions/game-result-gateway/question-generator.ts
- Non-executable schema/registry proposal: security-review/student-login-hardening/GAME_RESULT_ATTEMPT_SCHEMA_PROPOSAL.sql.txt
- Non-executable atomic SQL function proposal: security-review/student-login-hardening/GAME_RESULT_ATOMIC_FUNCTIONS_PROPOSAL.sql.txt
- Detailed protocol: security-review/student-login-hardening/GAME_RESULT_PROTOCOL_PROPOSAL.md

## Critical rollout gates

- The Edge Function is not deployed. It returns HTTP 503 without contacting Supabase unless both server-side variables GAME_RESULT_GATEWAY_READY=true and GAME_RESULT_WRITE_ENABLED=true are set. Neither has been configured.
- The database schema and atomic functions are drafts only; they have not been run or integration-tested.
- The current live game client has not been migrated to start attempts and submit one answer at a time.
- The existing record_student_game_result RPC still has anonymous EXECUTE permission. Do not revoke it until every real caller has been identified and migrated. Do not mistake this proposal for a closed bypass.
- Authenticated direct inserts into point_transactions remain in place for teacher awards and activity scoring. Any narrowing requires a separate coordinated review that preserves those workflows.
- Endpoint rate limiting/abuse controls are not implemented in this review scaffold. Design them without trusting unverified client-supplied source headers, and verify them in isolation before enabling the public endpoint.
- No isolated Supabase database is currently available. Do not test attack, replay, concurrency, or lockout cases against the shared TEST/PRODUCTION project.
- The checked-in Deno tests have not been run with Deno. No Deno runtime success is claimed.
- The historical 24-point transaction's write path is still unknown. The 24-point value may fit the current bonus rule, but its recorded 24/15 denominator is inconsistent. Preserve the history; do not adjust it without separate evidence and approval.

**Release decision remains NO-GO** until the schema/functions, all game/client callers, test results, effective permissions, and central display behavior are verified together.
