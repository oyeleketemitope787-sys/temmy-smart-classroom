# Central Scoring Client Migration Plan

**Status:** Review-only implementation plan. No game client changes, database changes, secrets, or deployments are made by this document.
**Target game:** `games/temmy-number-challenge.html` in `oyeleketemitope787-sys/temmy-smart-games`.
**Backend review branch:** `security-review/student-login-hardening`.
**Game repository:** Keep `main` unchanged. The GitHub integration did not permit creating a separate branch in the game repository, so this plan is stored only on the isolated Classroom review branch.

## Current client findings

The current public HTML game:
- keeps its fixed 15-question set and correct answers in browser JavaScript;
- calculates `score`, streak bonuses, and challenge lives in the browser;
- displays the final result as `score/15 points`;
- reads the optional `session` URL token but does not submit a verified attempt or answer to the central gateway.

Consequently, the client must not be treated as a trusted source of marks. The local result display and answer key must be replaced for assigned, reward-eligible sessions before central scoring can be enabled.

## Required client protocol

1. Detect whether the URL has a session token. Without a token, run a clearly separate practice-only path; it must not call reward APIs or create point transactions.
2. For an assigned session, call the gateway with `start_attempt`, the token, the registered game ID, and selected mode. Do not send the student name as identity; derive identity from the session on the server.
3. Render only the current server-returned question, options, hint, and progress. Never receive or store the answer key in browser code.
4. Submit only `question_index` and `choice_index` with the token and game ID. Disable answer controls while a request is pending to avoid accidental concurrent clicks.
5. Render the server response as the source of truth for correctness, score, streak/progress, and lives. Do not locally calculate official points or awards.
6. On a completed response, display `score_display.score_label` (for example, `24/41`), the exact `points_awarded`, and the returned question/correct-answer counts. Do not hardcode `/15`.
7. If a request times out, retry only the same answer payload. The backend must make identical retries idempotent; the client must not advance until it receives a valid response.
8. If the gateway is disabled, returns an invalid response, or the session is rejected, show a safe error and do not fall back to a local score that could be mistaken for an official reward.

## Central scoring rules

- Store the actual verified score and game-specific maximum.
- Award exactly the verified score as points.
- For the current Number Challenge scoring algorithm, the registered rule is `number-challenge-streak-v1`, with a maximum of 41 (15 base points, 13 streak bonuses at streak 3+, 11 additional streak bonuses at streak 5+, and 2 final-question bonus points). A verified score of 24 is therefore displayed as `24/41` and awards 24 points, not `24/15`.
- A no-bonus game out of 20 must register its own maximum of 20; a verified `16/20` awards 16 points.
- Unknown games, unsupported rule versions, inconsistent server responses, or scores above the registered maximum fail closed. Never clamp or rewrite a score.

## Implementation and release gates

Do not implement the live client switch until all of these are available:
- An isolated Supabase project for integration testing, separate from shared TEST and production.
- A reviewed schema migration and atomic SQL functions, tested in that isolated project.
- A deployed test-only Edge Function with server-side secrets configured and both feature flags disabled by default.
- Verified session/RPC grants, RLS, and the legacy anonymous `record_student_game_result` caller inventory. Do not revoke existing grants until legitimate callers are migrated.
- Rate limiting / abuse controls for the public gateway.
- A client patch on a review branch in the game repository, followed by end-to-end tests.
- Explicit approval before any deployment or permission change.

## Required acceptance tests

1. Practice without a session token cannot write reward points.
2. A valid assigned session starts with a server-generated question and no answer key in the response.
3. Correct and incorrect answers are verified server-side and advance exactly one question.
4. An identical retry does not increment score or create another transaction; a conflicting duplicate is rejected.
5. Concurrent submissions cannot score the same question twice.
6. Challenge mode completes after the third incorrect answer and awards only the verified score earned so far.
7. The final result, stored attempt, and single point transaction agree on score, maximum, rule version, and points awarded.
8. A 24-point Number Challenge result displays `24/41`; a registered no-bonus game result of `16/20` displays `16/20`.
9. Expired, reused, mismatched, and unknown-game sessions fail without an award.
10. A gateway/database failure does not show a success screen or claim points were awarded.

## Current decision

**NO-GO for release.** The backend handler is review-only and default-disabled; the SQL files remain non-executable drafts; the public game client is unchanged. Do not configure the feature flags or deploy until the complete isolated integration test passes.


## Latest source/branch verification — 2026-10-30

Read-only inspection of `oyeleketemitope787-sys/temmy-smart-games` confirmed that the current `main` version of `games/temmy-number-challenge.html` still:
- reads the optional `session` URL parameter into a local object but does not use it to call the gateway or a result RPC;
- keeps the 15 questions and correct answers in browser JavaScript;
- calculates base points, streak bonuses, final-question bonus, lives, and the final score locally;
- displays the final score with a hardcoded `/15 points` denominator, even though the local bonus algorithm can exceed 15.

The game repository's default branch is `main`. Existing branches include `classroom-integration`, but that branch was not assumed to be safe or related to this scoring migration. A dedicated branch named `integration/central-scoring-number-challenge-review` was requested from `main`; GitHub returned HTTP 403 (`Resource not accessible by integration`). No branch was created and no file was changed in the game repository. Do not fall back to editing `main` or an unrelated branch.

**Next safe action:** prepare and test the client migration as a review patch/diff in the Classroom review repository until a dedicated game-repository branch can be created by an authorized GitHub workflow/user. Keep the public no-session practice path independent from reward submission. The central gateway contract must be reconciled with the game UI before any client patch is proposed for application.
