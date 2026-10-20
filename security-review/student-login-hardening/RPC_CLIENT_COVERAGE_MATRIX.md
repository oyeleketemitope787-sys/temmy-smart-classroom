# Student Access Gateway — RPC and Client Coverage Matrix

Status: review artifact only. This is not an executable migration and contains no GRANT/REVOKE statements.

## Purpose

Use this matrix to prevent an incomplete gateway rollout. The gateway must cover all student access-code operations before direct anonymous execution is revoked. Function names below come from the SQL definitions and browser inspection already reviewed in this branch. Reconfirm against the current deployed schema and all deployed clients before release.

## Known student-facing RPC inventory

| RPC | Expected result contract in current client | Client call-site status | Special review notes |
|---|---|---|---|
| `student_portal_login(p_access_code)` | Array/row; empty result means invalid or inactive code | Found in `cloud-test/index.html` | Updates last-login timestamps; preserve returned student/class/name fields |
| `get_student_point_history(p_access_code)` | Array of transactions | Found in `cloud-test/index.html` | Function is STABLE; do not add writes to verifier call path without separate review |
| `get_student_live_activities(p_access_code)` | Array | Found in `cloud-test/index.html` | Scope to student's class |
| `get_student_game_sessions(p_access_code)` | Array | Found in `cloud-test/index.html` | Returns unused, unexpired sessions scoped to student |
| `get_student_messages(p_access_code)` | Array | Found in `cloud-test/index.html` | Safe generic errors needed; current function can raise an invalid/inactive-code error |
| `mark_student_messages_read(p_access_code)` | Scalar integer | Found in `cloud-test/index.html` | Keep scalar contract or explicitly adapt it |
| `send_student_message(p_access_code, p_message)` | Array/row | Found in `cloud-test/index.html` | Existing message-length validation; keep response fields expected by client |
| `submit_student_activity(p_access_code, p_activity_id, p_answer)` | Array/row | Found in `cloud-test/index.html` | Class ownership, live status, and duplicate submission checks |
| `start_student_game_session(p_access_code, p_game_id)` | Row/array with session token and session metadata | Caller NOT located in inspected `cloud-test/index.html`; full caller coverage unresolved | Must locate the game-launch client before rollout. `p_game_id` currently lacks a verified authoritative allowlist |
| `verify_student_access_code(p_access_code)` | Student identity row(s) or no rows | Internal shared verifier; not a browser RPC in inspected client | Keep verifier semantics stable; no write-based throttling added here |
| `generate_student_access_code(p_student_id)` | Teacher-side generated code contract | Teacher-side function; not part of student gateway action list | Preserve authorization; do not accidentally revoke teacher access |

## Permission matrix — deliberately incomplete until audit output is reviewed

Do not infer final ACLs from function source alone. Effective permissions depend on explicit ACL entries, default privileges, ownership, and inherited roles.

| Function group | Current evidence | Future target | Release condition |
|---|---|---|---|
| Student-facing code-consuming RPCs listed above | Prior audit reported anonymous execution for the nine student-facing RPCs; corrected broad audit output is still required | Browser uses gateway; direct anon execution revoked only after all callers migrate | Confirm exact signature, owner, effective ACL, and every call site |
| `verify_student_access_code` | Prior audit reported anon execution revoked and authenticated execution retained | Internal verifier remains unavailable to anonymous direct callers; gateway uses only an explicitly reviewed server-side path | Confirm effective ACL and gateway DB-role requirements |
| `generate_student_access_code` | Prior audit reported authenticated execution and no anon execution | Teacher-side authorization remains unchanged | Verify teacher workflow and exact ACL before any change |
| Other candidate matches from broad audit | Not yet classified | No change until classified | Inspect full definition and callers |

## Required evidence to complete this matrix

1. Output from `READ_ONLY_ACCESS_CODE_CALLGRAPH_AUDIT.sql` on the current database.
2. Confirmation that the output includes all signatures and effective grant entries, including default ACL interpretation.
3. Full caller inventory for `start_student_game_session` across the Classroom, game launch page, and any separate game repository.
4. A reviewed allowlist mapping each gateway action to one exact function signature and validated input schema.
5. A tested compatibility adapter for array/row and scalar return contracts.
6. A list of teacher-only or shared functions that must not be swept into broad revokes.

## Explicit no-go conditions

- Any student code-consuming RPC can still be called directly by anonymous clients after cutover.
- Any legitimate deployed client still calls a function directly.
- The `start_student_game_session` caller is unknown.
- Effective ACLs are assumed rather than inspected.
- Gateway returns a generic envelope that the existing client does not unwrap.
- Limiting depends on untrusted request headers.
- A migration requires risky tests against the shared production/test database.
- Rollback would restore a frontend that bypasses the gateway.

## Safety note

This file is a planning artifact only. It must not be pasted into SQL Editor. No database permissions, data, secrets, functions, or deployments are changed by this document.
