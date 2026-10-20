# Student Access Gateway — Action Contract Draft

Status: proposed API contract for review only. This is not deployable code and does not change the frontend, database, secrets, or Edge Functions.

## Contract rules

- Endpoint accepts only POST JSON requests (OPTIONS only for CORS preflight).
- Request has exactly one `action` string and the fields listed for that action; reject unknown actions and unexpected fields.
- Never accept an RPC name, table name, SQL fragment, role, student ID, or authorization decision from the browser as a substitute for server-side validation.
- Do not log request bodies, access codes, answers, messages, session tokens, or secrets.
- Responses should preserve the current client-facing data shape for each action. If a standard envelope is selected, the client adapter must deliberately unwrap it and contract tests must prove compatibility.
- The examples below describe intended input shapes only. Code format/length rules and message/answer bounds must be confirmed against the deployed schema and actual student codes before implementation.

## Proposed action map

| Action | Required request fields | Expected compatibility shape | Required server-side checks |
|---|---|---|---|
| `login` | `accessCode` | Array/row with student_id, class_id, class_name, first_name, last_name; empty result indicates invalid/inactive | Validate code; call only `student_portal_login`; return safe generic failure |
| `point_history` | `accessCode` | Array of point-history rows | Validate code; call only `get_student_point_history` |
| `live_activities` | `accessCode` | Array of live activity rows | Validate code; call only `get_student_live_activities` |
| `game_sessions` | `accessCode` | Array of game-session rows | Validate code; call only `get_student_game_sessions` |
| `messages` | `accessCode` | Array of messages | Validate code; call only `get_student_messages`; normalize internal errors |
| `mark_messages_read` | `accessCode` | Scalar integer count | Validate code; call only `mark_student_messages_read`; preserve scalar or explicitly adapt |
| `send_message` | `accessCode`, `message` | Array/row with message_id and sent_at | Validate code; apply server-side length limits; call only `send_student_message` |
| `submit_activity` | `accessCode`, `activityId`, `answer` | Array/row with record_id, activity_id, status | Validate UUID and bounded answer; call only `submit_student_activity`; rely on and preserve class/live/duplicate checks |
| `start_game_session` | `accessCode`, `gameId` | Array/row containing session_token, student/class/name, expiry | Caller not yet located. Do not enable this action until its legitimate client is identified and game authorization/allowlist is defined |

## Do not expose these as browser actions

- `verify_student_access_code`: internal verifier, not a standalone public action.
- `generate_student_access_code`: teacher-side operation; preserve its existing authorization and keep it outside the student action allowlist.

## Error response policy

The public API should use a small documented set of generic error categories, for example:
- malformed request
- unsupported action
- invalid or inactive access code
- temporarily rate limited
- temporarily unavailable

Do not reveal whether a student exists, whether a code is nearly correct, database table names, SQL errors, stack traces, or limiter internals. Choose final HTTP status codes only after testing the current Supabase browser client and frontend adapter.

## Important unresolved design choices

1. Does the gateway preserve raw result shapes or return a versioned envelope? Do not mix approaches.
2. What exact access-code format and maximum length are valid in the deployed database?
3. What body-size and field-size limits fit actual answer/message usage?
4. How is a trusted source identity obtained, if available at all?
5. Which server-side role executes each RPC, and what exact grants does it need?
6. Which game IDs are permitted, and where is the authoritative authorization check?
7. How are attempts counted once per externally initiated action without double-counting the internal verifier?
8. What are the HMAC key versioning, rotation, expiry, and failure behaviors?

## Acceptance criteria

- Every action has positive and negative contract tests.
- Tests assert exact result shapes, including the scalar integer response.
- No action can route to an arbitrary RPC.
- No request data or secrets are logged.
- Rate-limit failure never silently bypasses enforcement.
- Unknown or unresolved actions are disabled, not guessed.
- All current callers are identified before rollout.
- No shared-database brute-force or lockout testing is performed.

## Current decision

**NO-GO.** The action map is a design proposal only. Effective ACL output, full caller coverage, trusted-source policy, limiter implementation, HMAC lifecycle, and isolated testing remain unresolved.
