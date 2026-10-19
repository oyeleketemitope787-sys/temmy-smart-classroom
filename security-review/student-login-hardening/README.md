# Student Login Hardening — Review Draft

Status: design review only. This branch is based on `cloud-test`. Nothing in this branch is deployed, and no database migration has been executed.

## Scope

Protect the existing student access-code login for Temmy Smart Classroom. Preserve the current response shape:

```json
{
  "student_id": "uuid",
  "class_id": "uuid",
  "class_name": "string",
  "first_name": "string",
  "last_name": "string"
}
```

Do not change `main`, the production site, or the separate Temmy Smart Games project.

## Current observed behaviour

- The browser calls `supabaseClient.rpc('student_portal_login', { p_access_code: code })`.
- `student_portal_login(text)` calls `verify_student_access_code(text)`.
- The verifier uses bcrypt via `extensions.crypt` and checks active access/student records.
- `generate_student_access_code(uuid)` verifies that the signed-in teacher owns the student's active class, then replaces the existing code on every successful call.
- Student messages and other portal RPCs still accept the student code. Moving login alone does not protect those other endpoints from automated guessing if they independently verify codes.

## Proposed staged architecture

1. Add a trusted Edge Function for login. The function should validate method, content type, body size and code format; return generic invalid-code responses; and never log submitted codes.
2. Establish a trusted request-source signal from the actual Supabase Edge ingress/runtime. Do not trust a client-supplied `X-Forwarded-For`, `X-Real-IP`, or similar header unless the deployment explicitly guarantees that it is overwritten by trusted infrastructure. If trustworthy source metadata cannot be established, do not claim IP-based throttling is implemented.
3. Apply request-level rate limiting at a trusted edge/gateway and use atomic database operations for durable counters. Keep windows/cooldowns short and progressive to reduce denial-of-service lockout risks.
4. Use a random HMAC key held in Supabase Vault or Edge Function secrets; never store raw codes, raw IP addresses, or plain unsalted hashes of access codes. Because the code space is limited, an unkeyed digest can be brute-forced offline.
5. Keep direct database RPC access from anonymous clients from bypassing the new endpoint. This requires a separate, carefully reviewed privilege plan because student portal RPCs share the verifier and currently allow anonymous execution. Do not revoke grants until the replacement flow and dependent RPCs have been accounted for.
6. Add a regeneration cooldown to `generate_student_access_code` only after reviewing the teacher UI's initial-code workflow. Initial generation must remain allowed; ownership checks must remain intact.
7. Test on TEST: successful/invalid login, malformed input, rapid repeated requests, parallel requests, cooldown expiry, first-time code generation, existing-code regeneration, and the other student portal RPCs. Do not deploy until tests pass.

## Critical design cautions

- A database RPC called directly from the browser has no trustworthy client IP argument. Never add an IP parameter and trust the browser to supply it.
- Fingerprinting the code alone can allow attackers to trigger a victim-specific lockout. Source and code dimensions should be separate and limits should be chosen to minimize lockout abuse.
- A successful login response should not create a durable Supabase Auth session unless the architecture is intentionally changed; current portal behavior is code-based.
- Do not put the service-role key in the browser. Do not return secrets or internal throttling details to the client.
- The table draft is only a data structure, not functioning throttling. Counters need atomic RPCs/functions, cleanup, monitoring, and tests.
- This document is not an authorization to execute SQL, create Vault secrets, deploy functions, or switch the frontend.

## Review gates

- [ ] Confirm which trusted request headers/IP metadata are actually available in Supabase Edge Functions for this project.
- [ ] Confirm how the Edge Function will access the database without exposing privileged credentials.
- [ ] Finalize and review the migration and rollback.
- [ ] Deploy only to a test environment after explicit approval.
- [ ] Verify the login flow and dependent portal RPCs before any production plan.
