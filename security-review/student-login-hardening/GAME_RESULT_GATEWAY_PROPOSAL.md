# Game Result Gateway Proposal

**Status:** Review-only patch; intentionally fail-closed  
**Branch:** `security-review/student-login-hardening`  
**Not deployed. No database objects, permissions, secrets, production code, or student records changed.**

## Patch added

- `supabase/functions/game-result-gateway/index.ts`

The new handler validates method, content type, body size, origin allowlist, exact JSON keys, UUID-shaped session token, the currently intended game ID, and a bounded list of unique question/choice indexes. It refuses client-supplied `score`, `max_score`, `student_id`, `teacher_id`, or `game_name`.

For a structurally valid request it still returns HTTP 503. It intentionally has no Supabase client, secret, database write, or path to award points. Do not remove this fail-closed behavior as a routine follow-up or deploy this handler as a functioning scoring path.

## Why it is not enabled

The current game calculates its score inside browser JavaScript. Its inspected source reads a `session` query parameter but does not submit a result to the database. The Classroom code creates a session and constructs the URL, but no matching result-submission caller has been located.

A final array of answers submitted by the browser is still untrusted input. Even if an Edge Function calculates a score from those answers, a caller could fabricate the array without playing. The current session table and RPC do not provide an authoritative per-question attempt/progress record for this proposal to validate. Consequently, this patch provides input-contract validation only; it is not yet a trustworthy scoring implementation.

## Required design before enabling score awards

1. **Choose the official scoring rule.** The visible game has 15 questions but grants streak and final-question bonuses; its displayed `/15` denominator conflicts with the local score. Decide whether the official score is correct answers out of 15 and whether bonuses are display-only. This product decision has not been approved in this review.
2. **Move trust server-side.** The browser must not choose the official score, maximum score, student identity, teacher identity, or transaction name. The server must use an approved game catalogue and derive student/game identity from a validated session.
3. **Add an authoritative attempt protocol.** If game results are based on answers, create a server-validated, replay-resistant per-question protocol that records/validates question state and submissions. Merely receiving a complete answer array at the end is insufficient proof that the game was played. Any required schema changes must be proposed separately and approved before execution.
4. **Make consumption and award atomic.** Session validation, score verification, one-time consumption, and point insertion must be a single atomic operation or an equally strong transactional workflow. Reject expired, consumed, wrong-game, invalid, duplicate, or out-of-range submissions without awarding points.
5. **Migrate all callers first.** The existing `record_student_game_result` function has `SECURITY DEFINER` and current effective `anon EXECUTE = true`. Do not revoke direct execution until legitimate caller paths have been located, replaced, and validated together. The current deployed caller remains unidentified.
6. **Close the direct insert gap carefully.** Authenticated users currently have direct INSERT permission on `point_transactions`, with an RLS check for teacher ownership and student/class membership, but the policy does not restrict `source` or `action_type`. The inspected Classroom code uses direct inserts for teacher point adjustments and activity scoring with `source = 'teacher'`. Review and preserve these workflows before proposing a narrower policy or server-only points writer.
7. **Keep public game play independent.** A public/non-assigned game can remain playable but must not award points to a student account without a valid student-linked session.

## Static review test plan

These tests can be run against the handler's request validator in an isolated code test harness; they do not call Supabase:

| Case | Expected validation outcome |
|---|---|
| Wrong method | HTTP 405 |
| Unsupported origin | HTTP 403 (when an Origin header is present) |
| Wrong content type | HTTP 415 |
| Oversized body | HTTP 413 |
| Malformed JSON or extra key such as `score` / `max_score` | HTTP 400 |
| Invalid token, game ID, question index, choice index, or duplicate question index | HTTP 400 |
| Structurally valid request | HTTP 503, no database call and no point award |

A valid request returning 503 is intentional and is the current safety invariant. Unit-level request tests do not substitute for an isolated end-to-end test once the full trusted protocol and database changes are separately approved.

## Release blockers

- Deployed result caller/source version not identified.
- Historical `24/15` transaction is not explained; the current function would cap those exact arguments at 15.
- Official game score/bonus rule is undecided.
- Trusted server-side scoring and atomic attempt/session state do not yet exist in this patch.
- Direct anonymous RPC execution and unrestricted source/action fields on authenticated point inserts need a coordinated migration plan.

**Decision remains NO-GO for release.** This proposal is documentation and a fail-closed code scaffold only; no deployment or database change has been performed.
