# Browser RPC Call-Site Inventory — Student Access Gateway

**Status:** static source review only. Inspected `cloud-test/index.html` from branch `cloud-test` (V8.9.2). This is evidence for planning, not authorization to edit that branch or deploy changes.

## Direct student-code RPC calls found

| Browser operation | RPC | Source location | Expected contract / note |
| --- | --- | --- | --- |
| Student login | `student_portal_login` | `cloud-test/index.html:2307` | Expects array; uses first row fields `student_id`, `class_id`, `class_name`, `first_name`, `last_name`. |
| Load point history | `get_student_point_history` | `cloud-test/index.html:2141-2144` | Expects an array; errors currently displayed in portal. |
| Load assigned games | `get_student_game_sessions` | `cloud-test/index.html:2173-2176` | Expects an array. |
| Load live activities | `get_student_live_activities` | `cloud-test/index.html:2323` | Expects an array. |
| Read messages | `get_student_messages` | `cloud-test/index.html:1811-1816` | Expects an array; after success it calls mark-read. |
| Mark messages read | `mark_student_messages_read` | `cloud-test/index.html:1840-1845` | Caller only checks the error; database function returns an integer. |
| Send message | `send_student_message` | `cloud-test/index.html:1971-1977` | Expects an array-like result and checks `result.length`. |
| Submit live activity | `submit_student_activity` | `cloud-test/index.html:2395-2399` | Expects a row array; then reloads activities. |

## Important source-review findings

1. The eight direct calls above are present in `cloud-test/index.html`. They call the browser Supabase client directly, so an Edge Function would not enforce protection until all relevant calls are migrated.
2. `start_student_game_session` was **not found** in this file. The database inventory contains that function, so the game-launch flow must be located in the full repository or other connected game-launch page before coverage can be declared complete.
3. `verify_student_access_code` is not called directly in this HTML. Its internal database callers still need to be accounted for in the server-side inventory.
4. Some browser error messages display `error.message` directly (for example login at line 2308 and message submission at lines 1979-1982). A gateway migration should return a stable, generic external error contract rather than leaking database-specific messages.
5. The browser retains the entered access code in `studentPortalSession.accessCode` for subsequent actions. The gateway migration must preserve feature behavior without logging or persisting raw codes.
6. The existing UI expects different response shapes for different actions. Preserve the documented compatibility contract: arrays for login/history/games/activities/messages/send/submit, and scalar integer semantics for mark-read unless a deliberate, reviewed frontend adapter normalizes them.

## Coverage status

- [x] Eight student-code RPC call sites identified in `cloud-test/index.html`.
- [ ] Find every additional caller across all branches/pages/repositories, especially `start_student_game_session`.
- [ ] Reconcile the full database function/grant inventory with every browser call site.
- [ ] Specify and review the gateway adapter contract before any frontend changes.
- [ ] Test in a genuinely isolated database before rollout.

## Safety boundary

No frontend code was changed. No SQL was run. No secrets were created. No Edge Function was deployed. Do not revoke anonymous grants until every affected operation is migrated and tested in an isolated environment.
