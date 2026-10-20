# Anonymous Game-Result RPC — Confirmed Finding

**Status:** Confirmed from user-supplied read-only Supabase query  
**Scope:** Review only. No database permissions or application code changed by this finding.

## Evidence

The effective privilege query returned:

| Function | Anonymous EXECUTE | Authenticated EXECUTE |
|---|---:|---:|
| `public.get_student_game_sessions(text)` | true | true |
| `public.start_student_game_session(text, text)` | true | true |
| `public.record_student_game_result(uuid, text, text, integer, integer)` | true | true |
| `public.start_teacher_game_session(uuid, text)` | false | true |

The `record_student_game_result` function is SECURITY DEFINER and inserts a row into `public.point_transactions` for the student referenced by the session. It checks that the session token exists, is unused, has not expired, and its stored game ID matches the submitted game ID. It then marks the session as used.

## Security interpretation

- Anonymous callers have database permission to invoke the result-recording function.
- The function's session checks are useful controls, but the permission result means the RPC is reachable without an authenticated database role.
- The query does **not** prove successful exploitation or establish whether a token can be obtained or guessed.
- The game session start function accepts a caller-supplied `p_game_id`; no approved-game allowlist check was present in the supplied definition.
- Public gameplay must remain available but must not write rewards to student accounts. Only a validated student-linked session should be able to award points.
- Search of the default branches of the Classroom and Smart Games repositories did not find the result submission caller. Search results are inconclusive and do not prove the caller is absent.

## Required before any permission change

1. Trace every legitimate caller of `start_student_game_session`, `get_student_game_sessions`, and `record_student_game_result`, including deployed pages and other repositories/branches.
2. Implement the student access gateway and migrate all student-code-consuming calls together.
3. Ensure student-linked result recording is authorized by a server-validated session, uses the session's stored student and game identity, and validates game eligibility.
4. Keep public gameplay separate from student reward recording.
5. Verify expected response shapes and run controlled end-to-end checks in an isolated environment before revoking direct anonymous EXECUTE.
6. Prepare rollback and monitoring before rollout.

## Current safety status

No SQL migration, permission revocation, Edge Function deployment, secret creation, or frontend deployment was performed as part of this review. Do not revoke anonymous EXECUTE until legitimate callers have been migrated and verified; equally, do not treat the current permissions as proof that the points-awarding path is safely isolated.
