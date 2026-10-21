# Effective ACL Findings — Game Session and Result RPCs

**Status:** Confirmed from user-supplied read-only Supabase output, 2026-10-21  
**Branch:** `security-review/student-login-hardening`  
**Scope:** Documentation only. No grants/revokes, database writes, deployments, or secrets changed.

## Evidence supplied by the database owner

| Function | Owner | SECURITY DEFINER | anon EXECUTE | authenticated EXECUTE | service_role EXECUTE | Raw ACL |
|---|---|---:|---:|---:|---:|---|
| `get_student_game_sessions(text)` | postgres | yes | true | true | true | `{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres}` |
| `record_student_game_result(uuid,text,text,integer,integer)` | postgres | yes | true | true | true | NULL |
| `start_student_game_session(text,text)` | postgres | yes | true | true | true | NULL |
| `start_teacher_game_session(uuid,text)` | postgres | yes | false | true | false | `{postgres=X/postgres,authenticated=X/postgres}` |

## Interpretation

1. The effective privilege checks confirm anonymous execution is allowed for `record_student_game_result`, `start_student_game_session`, and `get_student_game_sessions`.
2. Anonymous execution is denied for `start_teacher_game_session`; authenticated execution is allowed.
3. A NULL `proacl` is not itself evidence of no permissions. PostgreSQL applies default privileges when no explicit ACL is stored. The effective `has_function_privilege` outputs above are the decisive evidence for the tested roles.
4. All four functions are owned by `postgres` and marked `SECURITY DEFINER`, so their internal authorization logic and search-path settings matter.
5. The evidence confirms callable exposure, not successful exploitation. It does not prove that a caller has a valid session token or has caused unauthorized point transactions.
6. `service_role` privilege output is included for completeness, but service-role access should not be granted to browser code or used as a public client credential.

## Immediate risk and boundaries

- `record_student_game_result` inserts student point transactions when a session is valid, unused, unexpired, and the supplied game ID matches the stored game ID.
- `start_student_game_session` verifies an access code and stores a caller-supplied game ID.
- `get_student_game_sessions` returns session tokens for unexpired, unused sessions belonging to the student resolved from the supplied access code.
- The actual deployed caller of `record_student_game_result` remains unidentified. The inspected classroom source creates and distributes session tokens, while inspected game source reads a token but does not visibly submit a result.
- The deployed game source remains unverified.
- Public gameplay must remain available without student-linked reward submission.

## Decision

**Confirmed exposure; no immediate blind revoke.** Do not revoke anonymous EXECUTE until all legitimate callers are identified or a safe coordinated replacement path is ready. In parallel, do not treat the current public permissions as safe. The next steps are:

1. Locate the actual deployed result-submission caller.
2. Finalize a server-side authorization contract that validates the session and game ID, bounds score inputs, and prevents client-selected student identity.
3. Migrate every legitimate client call to a server-controlled gateway/endpoint.
4. Verify the effective ACL and response contracts again.
5. Test safely in an isolated environment before a coordinated revoke/rollout.
6. Prepare rollback and monitoring.

No SQL migration, grant/revoke, Edge Function deployment, secret creation, frontend modification, or production deployment was performed as part of this review.
