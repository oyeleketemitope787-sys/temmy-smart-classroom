# Edge Login Endpoint — Design and Test Gate

This document supplements README.md. It is a design checkpoint, not deployable production code.

## What is confirmed

- Supabase Edge Functions can read server-side secrets using environment variables; privileged keys must never be exposed to browser code.
- Supabase has documented an `X-Forwarded-For` client-IP approach for Edge Functions, but the project must verify that its gateway populates and sanitizes this header as expected.
- The current browser calls `student_portal_login` directly. An Edge Function would not enforce a limit while that direct path remains available.

## Before coding the endpoint

### 1. Verify source metadata in the TEST project

Deploying even a diagnostic function is a change and requires explicit approval. When approved, a temporary diagnostic endpoint should return only booleans and safe metadata, never the IP address or full headers. Verify:
- whether `X-Forwarded-For` is present for a normal request;
- whether the gateway overwrites or appends client-provided values;
- how multiple comma-separated addresses are represented;
- whether the function can reject missing or malformed source metadata safely.

Do not treat a client-provided `X-Forwarded-For` header as trusted until these behaviours are verified.

### 2. Decide rate-limit policy

Proposed starting policy for review, not final values:
- source-level short window for broad brute-force protection;
- code/source keyed attempt counter as a secondary signal;
- short progressive cooldown, with generic responses;
- atomic updates to prevent concurrent-request bypass;
- expiration and cleanup for old attempt records;
- no raw codes, raw IPs, or unkeyed code hashes in persisted logs.

Avoid a long victim-code-specific lockout, since an attacker could deliberately trigger it.

### 3. Plan bypass closure

Before routing the frontend to the endpoint, inventory every anonymous RPC that accepts `p_access_code` and calls `verify_student_access_code`. Existing portal functions include messages, history, games, and activities. Choose a coherent enforcement approach for all of them:
- route them through a trusted server-side layer, or
- enforce shared limits inside database verification while avoiding unsafe per-student lockout.

Do not revoke anonymous execute permissions piecemeal; doing so could break the portal. Review function grants, dependencies, and rollback together.

### 4. Secrets and database access

Use an Edge Function secret or Vault-backed key with tightly restricted access. Do not place the service-role key in the browser. If a privileged key is used server-side, scope its use narrowly and do not return it to clients. Keep HMAC generation consistent between the function and the database, and version the key strategy so rotation can be planned.

### 5. Test matrix

- valid code returns the same response fields as current login;
- invalid and inactive code return generic failure;
- malformed request and oversized body are rejected;
- repeated attempts trigger a temporary limit;
- concurrent attempts cannot bypass counters;
- missing/untrusted source metadata fails safely;
- successful login still permits all expected portal features;
- first-time teacher code generation still works;
- regeneration cooldown behaves as specified;
- expiry/cleanup removes stale records;
- direct RPC paths cannot bypass the protection.

## Current decision

No diagnostic function, production function, migration, secret, or frontend change has been deployed or executed. Continue with a reviewable implementation only after the trusted-source test plan and complete RPC coverage have been agreed.
