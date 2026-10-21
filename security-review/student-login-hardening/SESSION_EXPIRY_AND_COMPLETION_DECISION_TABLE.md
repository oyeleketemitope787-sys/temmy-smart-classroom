# Session Expiry, Assignment Visibility, and One-Time Scoring — Decision Table

**Status:** Design-only decision record based on source inspection and user-observed behaviour. Database behaviour remains unverified pending read-only SQL output.  
**Branch:** `security-review/student-login-hardening`  
**No implementation, migration, ACL change, or deployment is included.**

## Confirmed evidence

- The reviewed Classroom source creates teacher game sessions with `start_teacher_game_session(p_student_id, p_game_id)`.
- The UI tells teachers that each selected student receives a 30-minute game session.
- Student Portal rendering displays `expires_at` and currently labels listed sessions `READY`.
- The reviewed student portal loads rows from `get_student_game_sessions(p_access_code)`.
- The inspected student session RPC definition sets expiry to `now() + interval '30 minutes'`.
- The user observed that assigned games disappeared for both students who completed the task and students who had not completed it; refreshing did not restore them.
- In the user's replay test, the game opened as a practice preview without a classroom session, and no second points award was recorded.
- The exact query filtering logic, presence of a durable assignment entity, and downstream result-submission route have not yet been confirmed from the full database definitions.

## Required state separation

| Concept | Intended lifecycle | Must not mean |
|---|---|---|
| Class-game availability | Game can be discovered by teacher for a matching class | Game is already assigned |
| Student assignment | Durable record of a teacher's instruction to a student | Temporary play session |
| Play session | Short-lived credential to launch one assigned attempt | The assignment itself |
| Result/award | Server-validated one-time completion and points event | Browser-displayed score alone |
| Game History | Read-only view of prior assignments/results | A way to start a new scored attempt |

## Required behaviours

| Situation | Student dashboard | Can launch? | Can award points? |
|---|---|---|---|
| Assigned, never started, valid session | Show as Ready | Yes | Once, after valid completion |
| Assigned, session expired, unfinished | Keep assignment visible | Fresh session only if server authorizes it | Once |
| Assigned, result accepted | Show Completed or move to History | No scored replay | No additional award |
| Duplicate submission for same session/assignment | Preserve completed state | No new scored attempt | No |
| Student opens Game History | Keep current work separate | No launch by default; result view only | No |
| Public practice without assigned session | Not shown as an assignment | Yes, public play remains open | Never affects a student |
| Session lookup/load fails | Show safe retry/error state; do not claim no assignments exist | Only after successful validation | No until server validates |

## Important design constraints

1. Expiry must apply to the play session, not silently delete or hide the durable assignment.
2. The server must enforce one-time completion/award atomically. Client-side hiding is only a UX aid.
3. A completed assignment must not obtain a new scored session through the student portal or an alternate RPC.
4. A new session for an unfinished assignment must reuse the same durable assignment identity, not create a duplicate assignment.
5. Public play must not submit results to a student or award points.
6. Assignment visibility must not depend solely on whether an unexpired session row exists.
7. Do not assume the database already has an assignment table. First inspect the inventory results; if there is no durable assignment model, propose a model separately and obtain explicit approval before schema changes.

## Evidence still required

- Full definition of `get_student_game_sessions` and its exact expiry/used filters.
- Full definitions of session creation and result submission functions.
- Relevant table columns and foreign keys for classes, students, game sessions, results, point transactions, and any assignment table.
- The real deployed game result-submission call site.
- Confirmation that the result function's used-session guard is atomic and that no second route bypasses it.

## Next action

Run the read-only lifecycle audit SQL and schema inventory in Supabase SQL Editor, then share the output. Review those results before recommending a specific data model or changing any functions.

**Decision:** No-go for implementation or database changes until evidence is complete and a safe isolated test path exists.
