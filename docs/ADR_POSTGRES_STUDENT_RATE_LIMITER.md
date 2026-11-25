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
