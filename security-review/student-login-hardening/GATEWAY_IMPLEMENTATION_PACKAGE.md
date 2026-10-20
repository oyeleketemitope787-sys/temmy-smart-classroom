# Student Access-Code Gateway — Implementation Package (Review Draft)

**Status:** review-only. Not deployable. No Edge Function, migration, secret, or frontend change is authorized by this document.

## Safety constraints

- Work only on `security-review/student-login-hardening`.
- Do not change `cloud-test` or `main`.
- The TEST frontend and live Classroom share a Supabase database. The shared project is not an isolated test environment.
- Do not deploy the diagnostic Edge Function or run brute-force, concurrency, spoofed-header, or lockout tests against the shared project.
- Do not expose a service-role key, Vault secret, raw access code, or raw IP address to the browser or logs.

## Existing browser-to-RPC map

The current `cloud-test/index.html` uses the Supabase browser client and calls these RPCs:

| Student action | RPC |
| --- | --- |
| Login | `student_portal_login(p_access_code)` |
| Load point history | `get_student_point_history(p_access_code)` |
| Load live activities | `get_student_live_activities(p_access_code)` |
| Load assigned games | `get_student_game_sessions(p_access_code)` |
| Read messages | `get_student_messages(p_access_code)` |
| Mark messages read | `mark_student_messages_read(p_access_code)` |
| Send a message | `send_student_message(p_access_code, p_message)` |
| Submit activity | `submit_student_activity(p_access_code, p_activity_id, p_answer)` |

The database inventory also includes `start_student_game_session(p_access_code, p_game_id)`. The game-launch flow and all other call sites must be searched before implementation.

## Required architecture

1. Browser calls one fixed Edge Function endpoint with an explicit action enum. It must not accept an arbitrary RPC name.
2. The Edge Function validates HTTP method, content type, body size, action, code format, and per-action arguments.
3. Apply a source-level rate limit only after the project’s trusted source metadata is verified. Do not trust client-supplied `X-Forwarded-For`, `X-Real-IP`, or custom IP headers. If the source cannot be trusted, do not claim IP limiting is active.
4. Apply code-related controls using a server-held HMAC key and atomic database counters. Never persist raw codes or unkeyed hashes of the short code.
5. Use a narrowly allowlisted server-side database client. If service-role credentials are required, they remain in Edge Function secrets, and the endpoint exposes only fixed RPC calls with validated arguments. Never forward arbitrary client-supplied table names, SQL, RPC names, or arguments.
6. Close direct anonymous RPC bypasses only in the same reviewed rollout that routes every student-code operation through the gateway. Preserve teacher ownership checks and student-to-record authorization checks.
7. Keep response shapes compatible with the current frontend and return generic invalid/inactive/rate-limited errors. Do not reveal whether a student or code exists.
8. Add bounded storage, expiration/cleanup, safe key rotation, monitoring that excludes secrets, and a rollback plan.

## RPC coverage and frontend migration

The gateway action allowlist must cover every public operation that accepts a student access code, including:

- `login` → `student_portal_login`
- `point_history` → `get_student_point_history`
- `live_activities` → `get_student_live_activities`
- `game_sessions` → `get_student_game_sessions`
- `messages` → `get_student_messages`
- `mark_messages_read` → `mark_student_messages_read`
- `send_message` → `send_student_message`
- `submit_activity` → `submit_student_activity`
- `start_game_session` → `start_student_game_session`

This list is based on the current inventory and must be confirmed against the full repository and database before the implementation is finalized. Internal calls to `verify_student_access_code` should not independently count as new user attempts; count each externally initiated action once, then record verification success/failure at the correct boundary.

## Database package requirements

The SQL package must be a single reviewed migration with clearly separated sections:

1. Create a non-exposed schema and limiter table with constraints and indexes.
2. Configure restrictive schema/table/function privileges explicitly.
3. Add a private HMAC helper with a narrowly scoped secret retrieval path.
4. Add an atomic limiter operation using an upsert/row lock or equivalent concurrency-safe method.
5. Define short, progressive controls and expiry behavior; do not impose long code-only lockouts that allow victim denial-of-service.
6. Integrate enforcement consistently with the code-consuming functions, preserving existing signatures, return types, authorization predicates, and behavior.
7. Revoke direct anonymous execution only after the gateway path is ready, and grant the server-side role only the exact functions it needs.
8. Include preflight assertions, post-change verification queries, and a rollback script.

The previously discussed numbers (five failures per 15 minutes and ten requests per minute) are placeholders only. They require validation against expected portal traffic and must not be silently hard-coded as final policy.

## Source metadata and diagnostic gate

The existing `supabase/functions/diagnose-request-source/index.ts` is a draft only. It has not been deployed. Header presence alone cannot establish trust. Before implementing source-based throttling, document the platform's current header semantics and validate them in an isolated project or a controlled environment that does not share the live database. If this cannot be safely verified, use an alternative trusted gateway or omit IP-based claims from the first release.

## Rollout gates

- [ ] Confirm all student-code RPCs and frontend call sites.
- [ ] Decide how the gateway authenticates to the database and prove direct RPC bypasses will be closed.
- [ ] Finalize trusted-source handling or explicitly defer source-based throttling.
- [ ] Finalize HMAC secret access and rotation.
- [ ] Complete migration and rollback review.
- [ ] Review Edge Function implementation for allowlisting, input validation, safe errors, no secret logging, and size limits.
- [ ] Test success, invalid/inactive codes, malformed/oversized requests, normal portal loading, all portal features, and expired limits in an isolated environment.
- [ ] Only after separate explicit approval, deploy and migrate in a coordinated order.

## Current status

This file is a plan only. No database changes, Vault secret creation, Edge Function deployment, frontend changes, or production rollout have occurred.
