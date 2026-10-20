# Game Session Caller Trace — Partial Evidence and Remaining Gap

**Status:** Partial source trace; not release-ready  
**Branch:** `security-review/student-login-hardening`  
**Scope:** Read-only repository inspection. No application files or database objects changed.

## Confirmed from `temmy-smart-classroom` `cloud-test/index.html`

The file SHA inspected was `9fc70a0ae617472904e0b96910940adab4553df9`.

1. Teacher assignment flow calls `supabaseClient.rpc('start_teacher_game_session', { p_student_id, p_game_id })`.
2. It expects a returned `session_token` and constructs a game URL to `https://games.stgloriousschool.org/games/temmy-number-challenge.html?session=<token>`.
3. Student portal game retrieval calls `get_student_game_sessions` with the student's access code, then builds the same game URL using each returned session token.
4. The inspected Classroom `cloud-test/index.html` contains no direct call to `record_student_game_result` or `start_student_game_session`.
5. It does call `get_student_game_sessions`, so this client currently depends on that anonymous-capable access-code RPC.

## Confirmed from `temmy-smart-games` `main`

Inspected file: `games/temmy-number-challenge.html`, blob SHA `9d343952f1374d40b80debb86514dfaf99c8b39f`.

- The page reads the `session` query parameter into a local `classroomGameSession.token` field.
- The inspected file does not contain `record_student_game_result`, `session_token`, a Supabase client, or a visible submission to the database.
- The game file has a local game ID `grade3-temmy-number-challenge`, while the classroom page displays a fixed game URL and may pass a database `game_id`. Compatibility of these values must be verified rather than assumed.

## Interpretation and limits

The inspected legacy game page receives a token but, in the inspected source, does not submit a result to the points-awarding RPC. This does not prove that the current deployed game, other pages, other branches, or other repositories lack a result submission path. GitHub code search returned no indexed matches for the RPC name or token fields in the two repositories; search coverage is not proof of absence.

This leaves a material end-to-end gap: the actual deployed caller of `record_student_game_result` and the flow that awards student points are not yet located. Do not revoke direct anonymous EXECUTE or deploy the gateway based only on this partial trace.

## Next safe investigation

1. Identify the exact URL/page students reach for a teacher-assigned game and compare it with the current deployed game source.
2. Inspect other relevant game pages and deployment branches for the result-submission logic and token handoff.
3. Verify the exact `game_id` stored in sessions matches the ID sent by the result caller.
4. Map student-assigned and public gameplay separately; public gameplay must not create student point transactions.
5. Only after all legitimate callers are located should the gateway migration and permission revocation be planned.
