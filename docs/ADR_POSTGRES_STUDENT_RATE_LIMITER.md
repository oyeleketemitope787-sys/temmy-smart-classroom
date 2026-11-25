# ADR: PostgreSQL-backed rate limiting for student localization

**Date:** 2026-11-25  
**Status:** Proposed design; not implemented  
**Branch:** `cloud-test` only

## Decision

Use a dedicated PostgreSQL table and one atomic SECURITY DEFINER RPC as the shared rate limiter for the `student-language-preference` Edge Function. This avoids an external Redis dependency and ensures all Edge Function instances share the same counters.

Supabase's own Edge Function rate-limit example uses Upstash Redis, not PostgreSQL. PostgreSQL is selected here as the user's explicit preference; its concurrency, cleanup and database-load behaviour must be tested before production use. Edge Functions are distributed/serverless, so process-local memory is not a shared limiter. Supabase docs describe the Edge runtime and its database integration: https://supabase.com/docs/guides/functions.

## Threat model and identity keys

A limiter keyed only by the submitted access-code fingerprint is insufficient: an attacker can vary guesses and create a new key for every guess.

Use two independent dimensions:
1. **Source key:** HMAC-SHA-256 of the actual client IP, derived only from a trusted platform-provided header.
2. **Credential key:** HMAC-SHA-256 of the normalized submitted access code, to slow repeated attempts against one code.

Do not use arbitrary client-provided `X-Forwarded-For` values. Supabase documentation and community discussions do not provide a definitive, official guarantee that one header is sanitized on every hosted ingress path. Treat `cf-connecting-ip` as an unverified deployment assumption until tested on the exact test-project function URL by sending a deliberately forged header and confirming the function does not receive the forged value. Do not fall back to the first/last arbitrary XFF entry. If no trustworthy source address is available, fail closed (temporary unavailable) rather than silently running only the weaker credential-key limiter.

The IP is never stored in clear text. HMAC keys are held only as Edge Function secrets, separate from each other and rotated with a planned key-version strategy. The raw access code, raw IP, HMAC values and Redis/DB keys must never be logged.

## Proposed storage

Create an internal table such as `private.student_language_rate_limits` (or another non-exposed schema), with:
- `scope` text constrained to `source` or `credential`
- `key_fingerprint` bytea (32-byte HMAC)
- `window_seconds` integer constrained to the approved windows
- `window_started_at` timestamptz
- `attempts` integer
- `expires_at` timestamptz
- primary key (`scope`, `key_fingerprint`, `window_seconds`)

Enable RLS and create no browser policies. Revoke table privileges from `PUBLIC`, `anon`, `authenticated`, and `service_role`; only the table owner and tightly scoped SECURITY DEFINER functions should touch it. Keep this schema out of exposed Data API schemas.

## Atomic limiter RPC

Create a single SECURITY DEFINER function with empty search_path and schema-qualified names. It must:
- Require `auth.role() = 'service_role'`.
- Accept only the two HMAC fingerprints, not raw IP or access code.
- Atomically upsert counter rows using `INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING`; no read-then-write counter sequence.
- Apply both short and long windows to both source and credential dimensions in one function call/transaction.
- Return only `allowed boolean` and a bounded `retry_after_seconds integer`; never return counters, keys or fingerprints.
- Revoke EXECUTE from PUBLIC, `anon`, and `authenticated`; grant only to `service_role`.
- Use bounded lock/statement timeouts and avoid session-level advisory locks. Row-level upsert conflict handling provides the atomic counter operation.

Provisional thresholds for test validation only (not approved production settings):
- Per source: 20 attempts / 10 minutes; 100 attempts / hour.
- Per credential fingerprint: 5 attempts / 10 minutes; 20 attempts / hour.

A blocked attempt should still be counted in the applicable windows. Retry time is the maximum remaining time among exceeded windows. The Edge Function should check the limiter before calling either student language RPC and return HTTP 429 with Retry-After. If the limiter RPC errors or times out, return generic HTTP 503 and do not verify the code.

## Cleanup and capacity

Use fixed windows and expire rows. Do not run a full-table DELETE on every request. Add a scheduled cleanup job only after confirming `pg_cron` is available and approved in the test project; otherwise define a bounded maintenance operation (for example, delete a limited batch of expired rows) invoked on a controlled schedule. Add an index supporting expiry cleanup. Monitor row count, function latency, database CPU, lock waits and error rate. Establish a maximum row count / abuse response plan before production.

Do not create an unbounded unique row per arbitrary request; the primary key collapses repeated keys into a small number of window rows. Validate fingerprint length and allowed window values in SQL.

## Edge Function request flow

1. Enforce POST, JSON content type, small body limit and exact request shape.
2. Validate action and language tag; never accept student/class IDs.
3. Extract source IP only from the verified trusted ingress header. No spoofable XFF fallback.
4. Normalize access code exactly as the existing login path expects; do not trim/change semantics without verifying existing code generation rules.
5. HMAC source and credential values with separate secrets.
6. Call the service-role-only limiter RPC. Fail closed on missing source identity or limiter errors.
7. If allowed, call the student get/set RPC (which itself verifies the code using the existing verifier).
8. Return only the minimal preference payload; generic invalid-code errors; never log secrets.
9. Rate limiting occurs before access-code verification. The rate limiter itself must not reveal whether a student/access code exists.

## Threshold approval and test plan

Thresholds above are placeholders for a controlled test. Before adopting them:
- inspect access-code format/entropy and expected student login frequency;
- test normal classroom use, including shared school networks/NAT where many students may share one public IP;
- test repeated same-code attempts and many different guesses from one source;
- test multiple simultaneous requests to confirm no race-condition bypass;
- test limiter database outage and timeout (must fail closed);
- test expiry cleanup and row growth;
- test missing/forged client-IP header behaviour on the exact test function URL;
- ensure raw IP/access code and fingerprints are absent from logs.

Because many students may share a school NAT, per-source thresholds must be generous enough not to block a whole school. The provisional source limits above must be validated before any real student trial.

## Rollout order

1. Review and approve this design and thresholds.
2. Run a test-only probe to establish the exact trusted client-IP header behaviour. Do not use arbitrary forwarding headers.
3. Add the rate-limit table/function in a separate reviewed migration on `cloud-test`; do not combine this with the localization preference migration until both have independent tests.
4. Test SQL atomicity and grants in the isolated test database.
5. Implement the Edge Function and local tests.
6. Deploy the function only to `temmy-smart-classroom-test`, set secrets through the dashboard/CLI secret mechanism, and run forged-header and load tests.
7. Only after successful tests, apply the revised localization preference migration and integrate the browser UI.
8. Production rollout requires a separate explicit approval.

## References

- Supabase Edge Functions: https://supabase.com/docs/guides/functions
- Supabase Edge Function rate-limiting example (Redis): https://supabase.com/docs/guides/functions/examples/rate-limiting
- Supabase securing Edge Functions: https://supabase.com/docs/guides/functions/auth
- Supabase API security and pre-request checks: https://supabase.com/docs/guides/api/securing-your-api
- Supabase log fields: https://supabase.com/docs/guides/observability/log-field-reference
- MDN X-Forwarded-For security guidance: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Forwarded-For


# PostgreSQL rate limiter: extension and cleanup implementation notes

**Date:** 2026-11-25  
**Status:** Design update; not implemented

## Test-project extension inventory

The test database reports:
- `pg_stat_statements` 1.11 in schema `extensions`
- `pgcrypto` 1.3 in schema `extensions`
- `plpgsql` 1.0 in `pg_catalog`
- `supabase_vault` 0.3.1 in `vault`
- `uuid-ossp` 1.1 in `extensions`

`pg_cron` is not installed. Do not install it solely for this feature without a separate decision and test-project approval.

## Consequences for the proposed limiter

- PostgreSQL-backed counters remain viable.
- The Edge Function should compute HMAC-SHA-256 fingerprints using Web Crypto APIs and server-only secrets. This avoids requiring the database to receive raw access codes or source IP addresses.
- If any SQL cryptographic helper is needed, explicitly schema-qualify `extensions.*`; do not rely on search_path.
- Cleanup must not depend on pg_cron. Use a bounded, controlled maintenance function or an approved existing scheduler after separate inspection. Do not run an unbounded delete per request.
- A maintenance function, if added, must be service-role-only or owner-only, delete a limited batch of expired rows, and return only a count. It must not be callable by browser roles.

## Next preflight checks

1. Confirm whether the `private` schema exists and whether it is exposed through Supabase API schemas.
2. Inspect available database scheduler facilities already configured in the project (do not install or enable anything).
3. Inspect role/schema privileges relevant to creating a non-exposed private schema and table.

No extensions were installed, no schema/table/function was created, and no SQL was executed beyond read-only inspection.


## Schema privilege preflight results — 2026-11-25

The test project has no existing `private` schema. Schema USAGE checks show `anon`, `authenticated`, and `service_role` have USAGE on `auth`, `extensions`, `graphql`, `graphql_public`, `public`, `realtime`, and `storage`; only `service_role` has USAGE on `vault`. This means a future `private` schema must be created deliberately and must not inherit browser-role access through broad grants. The migration should create it with a trusted owner, revoke schema privileges from `PUBLIC`, `anon`, and `authenticated`, and grant only the minimum required to `service_role` if the Edge Function's database RPC resolution requires schema USAGE. Keep the schema out of PostgREST exposed schemas as a separate dashboard/API configuration check; the `pgrst.db_schemas` setting was not visible in `pg_settings`, so that query did not establish the exposed-schema list.

Next preflight: inspect database-level CREATE privileges and current role membership before drafting schema creation/grants. No schema has been created.


## Database creation privilege result — 2026-11-25

The test SQL editor reports `current_user = postgres`, database `postgres`, database owner `postgres`, and `has_database_privilege(..., 'CREATE') = true`. The intended migration role can create a schema in this test database. This is a capability check only; it does not authorize or perform schema creation. Before drafting the migration, inspect role membership and default privileges so the schema/table/function ownership and grants are explicit.


## Role membership preflight — 2026-11-25

The membership query for `anon`, `authenticated`, `service_role`, and `postgres` returned only rows where `postgres` is the member and the granted role is `anon`, `authenticated`, `authenticator`, `service_role`, or several PostgreSQL administrative roles. It returned no rows showing `anon`, `authenticated`, or `service_role` as members of another role. This does not show browser roles inheriting `postgres` privileges. Regardless, the private schema and its objects must explicitly revoke `PUBLIC`, `anon`, and `authenticated` privileges and grant only narrowly required access.


## Private-schema object check — 2026-11-25

The read-only query against `pg_class` joined to `pg_namespace` for `nspname = 'private'` returned `Success. No rows returned`. This confirms there are currently no relations in a `private` schema; the earlier namespace check also confirmed that the schema itself does not exist. This removes a name collision concern for the proposed private limiter objects. It does not itself verify PostgREST exposed-schema configuration.


## Scope decision: protect the complete student access-code pathway — 2026-11-25

The user approved the recommendation to protect the entire student access-code pathway, not only student language-preference requests. The PostgreSQL rate limiter must therefore be invoked at the student access-code authentication boundary used by the existing student login flow (including `student_portal_login`/its Edge Function caller), before any access-code verification that could be used for guessing. It must also cover future student access-code authenticated operations only where those operations independently accept/verify an access code; an already-established student session should not be forced to resubmit the code for every normal request. Language preference RPCs must reuse the authenticated student session or the protected access-code entry flow, rather than create a weaker parallel login path.

The currently drafted SQL names (`student_language_rate_limits`, `consume_student_language_rate_limit`, `cleanup_student_language_rate_limits`) are now too narrow and should be renamed to generic student access-code rate-limit names in a revised migration before application. No SQL migration has been executed. Next implementation step is inspect the existing student login Edge Function/client call path on `cloud-test`, identify the exact point before `student_portal_login` / `verify_student_access_code`, and then revise the database migration and Edge Function integration together. Do not modify the existing verifier's authentication semantics or production branch/project.


## Existing student login implementation inspection — 2026-11-25

Inspected `index.html` on `cloud-test` (read-only). The current `studentPortalLogin()` function calls `supabaseClient.rpc('student_portal_login', {p_access_code: code})` directly from the browser. On success it stores `accessCode` plus returned student/class display fields in `studentPortalSession`. Subsequent browser RPCs pass `studentPortalSession.accessCode` directly to `get_student_live_activities`, `submit_student_activity`, `get_student_point_account_summary`, `get_student_point_history`, `get_student_game_sessions`, `get_student_messages`, `mark_student_messages_read`, and `send_student_message`. Thus the current access-code is repeatedly sent to PostgreSQL for multiple operations; the rate limiter must not be narrowly attached only to localization or login while leaving code-guessable direct RPCs exposed.

No matching Edge Function entrypoint was found at the conventional candidate paths checked (`supabase/functions/student-portal-login/index.ts`, `student_portal_login/index.ts`, `student-login/index.ts`); `supabase/config.toml` was also not found at the checked path. This is not proof that no differently named Edge Function exists. The repository's current browser login call is confirmed direct RPC. Next design decision: introduce a dedicated Edge Function login boundary and a server-issued, short-lived student session credential (or equivalent secure session mechanism), then migrate all student operations away from repeatedly transmitting the raw access code. Avoid storing long-lived raw access codes in browser state. Keep existing SQL RPCs intact during a staged compatibility migration; do not disable them until all callers are migrated and direct public execution is revoked safely. No source code or database changes were made in this inspection.


## Approved student session-token architecture — 2026-11-25

**Decision:** The user approved a cryptographically random, opaque, short-lived student session token. PostgreSQL stores only a one-way hash of the token; the raw token is returned once to the browser and is never stored in the database.

### Proposed lifecycle

1. Student submits the access code to a dedicated login Edge Function.
2. The Edge Function validates request shape and obtains a trusted source identity; it computes separate HMAC-SHA-256 fingerprints for source and credential using server-only secret material and distinct domain-separation labels.
3. The Edge Function invokes the PostgreSQL rate limiter before any access-code verification. Limiter failure is fail-closed.
4. If allowed, the Edge Function calls the existing student_portal_login(p_access_code) through a privileged server-side client. The existing verifier semantics remain unchanged during the staged migration.
5. On successful login, a tightly scoped PostgreSQL session-creation RPC creates a cryptographically random token (minimum 256 bits of entropy, generated by the Edge Function using Web Crypto), hashes it with SHA-256, and stores only the hash with the student ID, creation time, expiry, and revocation state. The raw token is returned once to the Edge Function and then to the browser over HTTPS.
6. The browser keeps the raw token in JavaScript memory only in the initial implementation. A page refresh requires login again; do not persist the raw token in localStorage. Evaluate sessionStorage only after an explicit XSS/threat-model review.
7. All subsequent student operations go through a student-session Edge Function gateway. The gateway hashes the presented token, validates it against PostgreSQL, checks expiry/revocation and student active status, derives student identity server-side, and executes an allow-listed operation. The browser never supplies student ID/class ID as authority and never supplies the original access code again.
8. Logout calls a revocation operation and clears the in-memory token. Expiry and revocation are enforced server-side, not only in the UI.

### Proposed session table fields

private.student_sessions:
- id uuid primary key (internal only)
- token_hash bytea unique, exactly 32 bytes
- student_id uuid foreign key to public.students(id) with appropriate deletion behaviour
- created_at timestamptz
- expires_at timestamptz
- revoked_at timestamptz nullable
- optional last_seen_at timestamptz only if an explicit idle-timeout policy is approved

Do not return session IDs or student IDs as authorization credentials. Do not store raw tokens. Avoid updating last_seen_at on every read unless needed; high-frequency writes create contention. Session validation should return only the minimum identity/context required to execute the allow-listed operation.

### Initial session policy — proposed, requires explicit confirmation before implementation

- Token entropy: at least 256 bits, generated with crypto.getRandomValues.
- Token encoding: base64url without padding.
- Token hash: SHA-256 of the decoded random token bytes; high entropy makes password-style slow hashing unnecessary. Never hash a low-entropy access code this way.
- Absolute lifetime: propose 8 hours initially for the test environment.
- Idle timeout: omit initially to avoid write amplification; consider later based on threat model.
- Browser storage: in-memory only; page reload logs out.
- One active session per login is not assumed. Multiple sessions may coexist until an explicit concurrency policy is chosen.
- Logout revokes the current session.
- No token refresh/renewal in the first version; user logs in again after expiry.

### Required API boundary and migration

- Create dedicated login and student-session Edge Functions, or a single carefully routed gateway with an allow-list. The preferred initial design is two functions: login and student API gateway.
- The gateway must not accept arbitrary RPC names from the browser. It maps fixed operation names to fixed server-side SQL operations.
- Student access-code RPCs must not remain directly callable by anon/authenticated after all callers are migrated. Revoke direct browser execution only after verifying every legitimate caller and server-side dependency.
- Keep teacher/admin operations unchanged.
- Do not change the existing student_portal_login or verify_student_access_code authentication semantics during the initial staged rollout.
- Add a secure logout/revocation path.
- Avoid logging access codes, raw session tokens, token hashes, or full sensitive request bodies.

### Security tests required before release

- Correct access code creates a session; incorrect/inactive code does not.
- Rate limit runs before verifier invocation.
- Limiter database/network failure prevents verification (fail closed).
- Raw token is returned once; database contains only a 32-byte hash.
- Wrong token, expired token, revoked token, inactive student, and malformed token are rejected.
- Browser roles cannot read session or rate-limit tables or execute privileged internal RPCs.
- The service-role Edge Function can call only intended operations.
- Browser cannot choose student ID, class ID, or arbitrary SQL/RPC function.
- Logout revokes the token; replay after logout fails.
- Existing student features continue working through the gateway: activities, activity submissions, points summary/history, game sessions, messages, mark-as-read, and sending messages.
- Rate-limit tests include parallel requests and fixed-window boundary behaviour.

**Status:** Architecture approved in principle. The token lifetime and storage policy above are proposed defaults, not separately approved product settings. No session table, RPC, Edge Function, or browser code has been created or changed.
