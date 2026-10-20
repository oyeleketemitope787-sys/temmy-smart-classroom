# Gateway Scaffold Review — Additional Contract Risks

Status: static review only, not a deployment approval. The scaffold remains fail-closed and must not be deployed as a working gateway.

Reviewed file: `supabase/functions/student-access-gateway/index.ts` on `security-review/student-login-hardening`.

## Findings

### 1. Access-code format is an unverified assumption
The scaffold accepts only eight hexadecimal characters:
`/^[A-Fa-f0-9]{8}$/`.

This may match current generated codes, but it must be confirmed against the deployed `generate_student_access_code` implementation and existing student codes before any client migration. If the actual format differs, legitimate students could be rejected. Do not loosen or tighten the pattern by guesswork.

### 2. Extra request properties are not rejected
The current validator checks required properties but does not reject unknown additional properties. It does not currently forward unknown properties to the database, which is good, but a strict schema should reject unexpected keys so client contracts stay explicit and future edits do not accidentally pass them through.

### 3. The response envelope needs an explicit adapter decision
The planned response is `{ data }`. Existing browser callers expect raw arrays/rows for most RPCs and a scalar integer for `mark_student_messages_read`. The eventual client adapter must unwrap and preserve those exact shapes or tests must document a deliberate versioned contract. Do not silently deploy the envelope unchanged.

### 4. CORS is not authorization
The origin allowlist helps browser behavior but does not prevent non-browser callers from sending requests. Rate limiting, validation, fixed RPC allowlisting, narrow privileges, and direct-RPC bypass closure remain necessary. Never describe CORS as authentication.

### 5. The readiness flag does not activate a gateway
The handler intentionally returns 503 even when `STUDENT_ACCESS_GATEWAY_READY=true`. This is a useful second fail-closed stop. Do not set the flag expecting the endpoint to work, and do not remove the hard stop until the limiter and RPC path are implemented and reviewed.

### 6. The game-session action must remain disabled until authorization is resolved
The scaffold accepts a syntactically valid `game_id`, then maps it to `start_student_game_session`. Shape validation does not establish that a student is permitted to start that game. The caller is still not located and the database function's authoritative game allowlist/authorization needs separate review. Keep this action unavailable until both issues are resolved.

### 7. Error mapping needs contract tests
The planned RPC handler returns a generic 400 for every database error. That avoids leaking raw details, but it may classify transient infrastructure errors as client errors and may break retry behavior. Define a small safe error taxonomy and test it; do not expose raw database messages.

### 8. Import and map are currently unused by design
The `createClient` import and `RPC_BY_ACTION` map are currently unused because the RPC block is unreachable. This is expected for the scaffold, not an active defect to fix by enabling the code. When implementation begins, remove dead pieces only as part of a reviewed complete change.

## Required evidence before revising the scaffold

- Confirm the actual access-code generation/validation format from the deployed SQL definitions.
- Confirm every action's exact result contract from current clients.
- Complete the call-site inventory, especially game-session launch.
- Confirm CORS preflight with the actual frontend request headers in an isolated environment.
- Decide safe HTTP status/error mapping.
- Implement and test the atomic limiter and HMAC secret lifecycle.
- Prove the gateway's database role can call only the required RPCs.
- Establish an isolated test environment before risky integration or lockout tests.

## Decision

**NO-GO.** This review makes no changes to the scaffold or live systems. The hard stops must remain in place.
