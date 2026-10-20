# Student-Linked Play vs Public Play — Security Boundary

Status: based on the product owner's clarification on 2026-10-20. Planning only; no frontend, database, permissions, secrets, or deployments changed.

## Intended product behavior

### Teacher-assigned student play
1. A teacher assigns a game to a student or class.
2. The student receives the assignment and plays the game.
3. The student's result/mark is recorded.
4. Points are automatically added to that student's Temmy Smart Classroom points balance according to the platform's scoring rules.

This flow is student-linked and must preserve identity, assignment ownership, result integrity, and correct point attribution.

### General public play
1. Any visitor may open a game in a browser and play without a student login.
2. Public play is independent of classroom assignment.
3. Public-play results must not add to any student's point balance.

## Security architecture implications

- Public game pages must not need a student access code merely to play a standalone game.
- Student access codes should only be used for student-linked operations that need identity, such as retrieving assignments, creating a student game session, submitting an assigned result, or awarding points.
- A public visitor must not be able to attach a public-play score to a student by supplying or guessing an access code after the game is played.
- Student-linked results and point awards must be tied to a server-validated assignment/session and the authenticated/verified student identity, not merely a browser-provided game ID or score.
- The gateway should cover code-consuming student operations only; it should not become a gate in front of public gameplay.
- A game session token is sensitive and must not be logged. The existing RPC returns a token with a 30-minute expiry; the full downstream validation and use of that token must be traced before changing this contract.

## Unresolved technical evidence

- The actual caller of `start_student_game_session(p_access_code, p_game_id)` has not been found through indexed GitHub searches. Search misses are inconclusive.
- The provided function definition checks the access code and active class, then stores caller-supplied `p_game_id`; no approved-game allowlist is visible in that definition.
- The downstream path that validates `session_token`, accepts game results, and increments points still needs to be mapped.
- No rate-limiting migration has been executed; no HMAC secret or Vault secret has been created; no gateway or diagnostic Edge Function has been deployed.
- The TEST frontend and production Classroom share a Supabase project. Do not run lockout, brute-force, spoofed-header, or concurrency tests against it.

## Required next review

1. Trace the assignment-to-game launch flow and identify where the student receives the assignment.
2. Trace how the game consumes the session token and how results are submitted.
3. Identify the exact database operation that adds points and verify it derives student identity from a trusted session/assignment rather than browser-supplied identifiers.
4. Map public play separately and verify that it cannot trigger student point awards.
5. Complete the gateway and permission plan only after all code-consuming call sites and result paths are accounted for.
6. Test changes in an isolated environment before any coordinated rollout.

## Decision

Keep both modes supported. Student-linked play is protected and point-bearing; public play remains open and must not affect student balances. Do not deploy or change permissions until the end-to-end student result path is traced and safely testable.
