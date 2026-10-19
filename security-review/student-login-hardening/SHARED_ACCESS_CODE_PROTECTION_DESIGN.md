# Shared Student Access-Code Protection — Review Design

Status: design only. This is not a migration and must not be executed. No database, frontend, secret, or deployment changes are authorized by this document.

## Safety constraints

- The known Supabase database is shared by the TEST frontend and the live Classroom.
- Work only on `security-review/student-login-hardening`. Do not modify `cloud-test` or `main`.
- Do not run brute-force, concurrency, spoofed-header, or lockout tests against the shared database.
- Do not deploy the draft diagnostic Edge Function to the shared project.
- Any future database migration, Edge Function, secret, or frontend change needs separate review and explicit approval.

## Confirmed starting point

The browser calls `student_portal_login(p_access_code)` directly. The database inventory found SECURITY DEFINER functions accepting a student access code, including:

- `verify_student_access_code`
- `student_portal_login`
- `get_student_game_sessions`
- `get_student_live_activities`
- `get_student_messages`
- `get_student_point_history`
- `mark_student_messages_read`
- `send_student_message`
- `start_student_game_session`
- `submit_student_activity`

The current grant review showed several anonymous execution paths. A grant on `PUBLIC` is inherited by roles unless revoked; revoking PUBLIC alone while leaving an explicit `anon` grant does not block anonymous access. Conversely, removing anon execute from one RPC at a time may break portal features while leaving alternate paths open.

The verifier uses a bcrypt hash comparison and active-state checks. Student codes were observed to contain eight hexadecimal characters (32 bits of randomness). That is a limited search space, so rate limiting is important, but policy must avoid creating an easy denial-of-service mechanism against an individual student.

## Design decision to evaluate

Prefer one shared enforcement boundary that every student-code-consuming operation must pass through. The existing verification function is a candidate, but it is not yet proven to be a complete enforcement point: the actual definitions and call graph for every listed function must be inspected to confirm that each reaches it exactly as expected and that no alternate verification path exists.

Do not implement a counter in the browser. A user can bypass client-side timers and call the RPC directly.

### Required properties

1. **Complete coverage:** every public/anonymous code-consuming RPC is covered, including `start_student_game_session`.
2. **Atomic updates:** simultaneous requests cannot race past a limit. Counter updates and decision-making must be transactional and use appropriate row/advisory locking or another proven atomic primitive.
3. **No raw secrets in logs:** never persist raw access codes or expose them in error messages. Do not store an unkeyed hash of the short code as if it were anonymous; it can be brute-forced offline. If a code fingerprint is required, use a server-held keyed HMAC with key versioning and rotation planning.
4. **No victim lockout:** avoid long lockouts keyed only to a student code. An attacker who knows or guesses a code could deliberately lock that student out. Prefer short progressive delays, broad abuse signals, generic failures, and a safe recovery path.
5. **Bounded storage:** counters expire and stale records can be cleaned without unbounded table growth.
6. **Generic external responses:** invalid, inactive, and rate-limited cases should not reveal whether a student exists or whether a code was correct.
7. **Teacher workflow preserved:** teacher ownership checks, class/student authorization, first-time code generation, and legitimate regeneration remain functional. Do not impose student-login cooldowns on teacher code generation.
8. **Independent authorization review:** rate limiting does not replace checks that the student can access only their own messages, scores, games, activities, and class data.
9. **Safe rollout and rollback:** plan a reversible migration, preserve existing function signatures/return shapes, and identify rollback steps before any approval to apply changes.

## Proposed review sequence

### Gate A — Read-only call-graph audit

For each function above, read the complete function definition and record:
- whether it calls `verify_student_access_code`;
- whether it makes writes before verification;
- what data it returns or changes;
- whether authorization is tied to the verified student ID;
- its grants to `PUBLIC`, `anon`, `authenticated`, and `service_role`;
- its `SECURITY DEFINER` status and safe `search_path`.

Do not assume that every RPC calls the verifier just because it accepts `p_access_code`. Confirm from the function bodies. Also search for all other functions that invoke the verifier or read `student_access` directly.

### Gate B — Choose the counter design

Compare at least two approaches before writing SQL:

- **Database-centered:** enforce a shared, atomic attempt policy at the common verification boundary. This may cover all RPCs if the call graph confirms it, but a short-code-only per-student counter risks victim lockout. Decide what can be counted safely without a trustworthy request-source signal.
- **Trusted server boundary:** route all code-consuming operations through a server-side layer and remove direct anonymous paths only after every affected frontend call has been migrated and tested in an isolated project. Routing login alone is insufficient. Source-IP throttling must not trust arbitrary client-supplied forwarding headers.

Do not choose a final schema, threshold, cooldown, or source-IP policy until the call graph and threat model have been reviewed.

### Gate C — Isolated test environment

The existing TEST frontend shares the live database, so it is not an isolated test environment. Before any test that intentionally causes failures, concurrency, lockouts, or source-header manipulation, obtain a genuinely separate Supabase project/database that can be used without affecting the live Classroom. Do not bypass plan restrictions or create another account to evade a provider's limits. If a separate project is not available, keep the work to read-only inspection and static review.

### Gate D — Controlled acceptance tests

In an isolated environment only:
- valid active code returns the existing expected response;
- invalid, inactive, malformed, and oversized input fails safely;
- concurrent requests cannot bypass the limit;
- all student-facing features continue to work;
- direct RPC calls cannot bypass protection;
- first-time teacher code generation and legitimate regeneration work;
- counters expire and cleanup is bounded;
- no raw code or sensitive request header is stored or logged;
- rollback restores the previous behavior cleanly.

## Not authorized yet

This document does not authorize:
- creating or altering tables/functions/policies/grants;
- creating Vault secrets;
- deploying Edge Functions;
- changing frontend RPC calls;
- changing either production or shared TEST configuration;
- running deliberate invalid-code or concurrency tests.

## Next action

Complete Gate A using read-only function definitions. Only after the call graph is confirmed should we write a separate proposed migration for review. Do not execute it until the user explicitly approves the specific change and confirms the target environment is isolated.
