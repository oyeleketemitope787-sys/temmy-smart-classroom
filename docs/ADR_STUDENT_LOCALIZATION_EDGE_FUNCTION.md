# ADR: Student localization Edge Function and rate limiting

**Date:** 2026-11-25  
**Status:** Proposed for review; not implemented  
**Branch:** `cloud-test` only

## Context

Student access is currently based on a student access code, not a Supabase Auth user session. The existing `student_portal_login(text)` is the anonymous entry point. The existing `verify_student_access_code(text)` helper is not executable by `anon`. Database inspection found no failed-attempt counter or database rate-limit trigger on `student_access`, and the inspected browser login path contained no visible rate-limit logic. These findings do not rule out controls at the gateway or hosting layer.

The new student language RPCs are therefore restricted to `service_role`. The secret/service-role key must never be sent to the browser or committed to source control.

## Decision proposed

Add one dedicated Supabase Edge Function named `student-language-preference` for student language preference reads and writes. It will call the two service-role-only RPCs from the server.

The function is public in the sense that students do not have an Auth JWT. Configure the function's JWT verification deliberately for this access-code flow (likely `verify_jwt = false`), then perform request validation and abuse controls inside the handler. A publishable API key identifies the project/client application; it is not proof that a caller is a genuine student. Do not treat it as authentication.

## Request contract

Use HTTPS POST with JSON only.

Read:
```json
{ "action": "get", "accessCode": "..." }
```

Set or clear:
```json
{ "action": "set", "accessCode": "...", "languageTag": "ar" }
```

Use `languageTag: null` to clear the individual preference and inherit the class/platform default. Validate exact allowed shape, body size, action, string length and supported BCP 47 tag before calling the database. Do not accept student IDs, class IDs, role names, SQL fragments or caller-supplied identity.

Successful read returns only:
```json
{
  "individualLanguage": null,
  "classDefaultLanguage": "ar",
  "effectiveLanguage": "ar",
  "preferenceSource": "class"
}
```

Successful set returns only the saved language tag (or null after clearing). Never return student IDs, class IDs, access-code hashes, profile fields or raw database errors. Invalid/inactive access codes use one generic response so callers cannot enumerate student records. Rate-limit responses use HTTP 429 and a `Retry-After` header.

## Rate-limiter design

A process-local counter is not acceptable: Edge Function instances are distributed and may restart. Use a shared atomic limiter.

**Preferred first implementation:** Upstash Redis (or an equivalent managed Redis service) with an atomic Lua script or equivalent transaction. Supabase documents this Redis pattern for Edge Function rate limiting. Keep Redis credentials in Edge Function secrets.

- Derive a stable opaque credential fingerprint using HMAC-SHA-256 with a dedicated server secret and the normalized access-code bytes. Do not store or log the raw access code. A plain unsalted hash is not preferred because short access codes can be guessed offline.
- Apply an atomic rolling/fixed-window attempt counter keyed by the HMAC fingerprint before verification. Initial thresholds are configuration proposals only: e.g. 5 attempts per 10 minutes and 20 per hour. Tune only after checking access-code length/entropy and expected student behaviour.
- Consider a second per-source limit only after identifying a trustworthy client-IP value supplied by the platform/proxy. Never trust arbitrary client-provided `X-Forwarded-For` or similar headers. If no trustworthy source IP is available, do not pretend an IP limit exists; document the residual risk and consider a challenge such as Turnstile.
- Fail closed if the shared limiter is unavailable: do not fall back to unbounded verification. Return a generic temporary-unavailable response.
- Do not log request bodies, access codes, HMAC fingerprints, Redis keys, or secrets. Log only request correlation ID, action, outcome category and latency.
- Set retention/TTL on counters; use atomic operations to prevent concurrent requests bypassing the limit.
- Do not lock or disable the student's underlying access record as a side effect of a rate-limit event.

Before selecting Upstash, confirm the user accepts the external service, its account/credentials, data-processing terms and any cost. A Supabase Postgres-backed atomic limiter is a viable alternative if avoiding another vendor is preferred, but it requires a separate narrowly permissioned database design and migration.

## Edge Function security requirements

- Restrict CORS to the actual test application origin(s); do not use wildcard origins with credentials.
- Accept POST only (plus OPTIONS for CORS).
- Enforce JSON content type and a small request body limit.
- Validate action and fields before any database call.
- Keep Supabase secret/service-role key, HMAC key and Redis credentials in test-project Edge Function secrets only.
- Use a server-side Supabase client configured with the secret key to call only the intended student RPCs.
- The RPCs independently require `auth.role() = 'service_role'` and expose no browser EXECUTE grants.
- Return generic invalid-code errors; no account/student enumeration.
- Add request timeout and bounded retries; never retry an invalid code.
- Add tests for malformed JSON, unsupported tags, missing fields, invalid code, inactive student, valid get, valid set, clear/inherit, rate-limit threshold, concurrent requests, limiter outage, CORS rejection and secret absence from built browser assets.

## Rollout sequence

1. Confirm rate-limiter provider (Upstash Redis vs Postgres) and approve initial thresholds.
2. Implement and test the limiter in isolation.
3. Implement the Edge Function and local tests; no deployment yet.
4. Review the complete function source and its secret/config requirements.
5. Deploy only to the separately named `temmy-smart-classroom-test` project.
6. Verify function logs do not contain credentials and test all abuse/security cases.
7. Only then consider applying the revised database migration to the test project.
8. Integrate the browser client after server endpoint tests pass. Do not change the existing login flow as part of this first localization rollout.

## Explicit non-goals

- No changes to `student_portal_login` or `verify_student_access_code`.
- No direct browser grants on `student_access` or the student preference RPCs.
- No production deployment or `main` branch changes.
- No automatic lockout or access-code rotation.
- No time-zone RPCs; time-zone storage is a separate concern.

## References

- Supabase Edge Functions overview: https://supabase.com/docs/guides/functions
- Supabase Edge Function secrets: https://supabase.com/docs/guides/functions/secrets
- Supabase Edge Function security: https://supabase.com/docs/guides/functions/auth
- Supabase rate limiting with Redis: https://supabase.com/docs/guides/functions/examples/rate-limiting
