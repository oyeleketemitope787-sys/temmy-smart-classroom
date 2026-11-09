# Temmy Gateway Production Authentication and Actor Trust Design

**Status:** Approved design target; review-only documentation  
**Approval:** User approved this trust chain on 2026-11-09.  
**Scope:** Temmy Smart Classroom transaction security and the future Temmy Gateway boundary.  
**Not implemented:** This document does not authorize code changes, SQL execution, hosted database changes, or deployment.

## 1. Decision

Adopt the following trust chain as the production design target:

1. A teacher signs in through Supabase Auth.
2. The browser sends the teacher's Supabase access token to a Temmy Gateway server-side endpoint (initially a Supabase Edge Function).
3. The Gateway validates the token with Supabase Auth and derives the teacher's immutable user ID from the verified identity claim (sub).
4. The Gateway authorizes the requested operation and checks the teacher/class/student relationship using trusted server-side data.
5. The Gateway invokes only the narrowly scoped database transaction function needed for that operation.
6. The database function enforces the transaction invariants, ownership constraints, idempotency, locking, and atomic ledger/audit updates.

The browser is an untrusted caller. A teacher ID, student ID, class ID, score, point amount, reward price, or stock value supplied by the browser is input to validate, not proof of authority.

## 2. Authentication and identity derivation

- Require a valid Supabase access token on every teacher-authorized Gateway request.
- Validate the token server-side using the Supabase Auth user-validation endpoint/client (for example, auth.getUser(accessToken)), or an equivalently secure JWT verification mechanism configured for the correct project, issuer, audience, signing keys, and expiry.
- Do not merely decode a JWT and trust its claims. A decoded but unverified token is not authentication.
- Derive the actor teacher UUID from the verified user identity (sub / authenticated user ID).
- Never accept teacher_id, actor_id, or equivalent caller identity from the request body, URL, or browser state as the authenticated actor.
- Validate that the authenticated account is an active/authorized teacher and that the requested student, class, activity, or reward belongs to that teacher according to trusted database relationships.
- Reject missing, invalid, expired, revoked, or inappropriate identities before invoking a transaction function.

## 3. Gateway-to-database boundary

The browser must never receive a Supabase service-role key, database password, privileged JWT signing secret, or other server credential.

The initial implementation may use a server-only Supabase service-role client inside the Edge Function, provided all of the following are true:

- The credential is stored only in the server-side Edge Function secret environment and is never returned to the browser or written to logs.
- The Edge Function validates the caller's access token independently before using the privileged client.
- Only the Gateway code path invokes the transaction entrypoints.
- Database EXECUTE grants are limited to the trusted server role needed by the Gateway; anon and authenticated browser roles receive no EXECUTE on protected transaction entrypoints.
- The transaction entrypoints are narrowly scoped and independently validate all business inputs and ownership. A privileged caller does not make arbitrary inputs trustworthy.
- No browser-facing route exposes a generic SQL/RPC proxy or allows callers to choose arbitrary database functions.

A dedicated restricted database role/credential may be preferable if the deployment architecture supports it without exposing credentials or weakening Supabase's managed security model. Select and verify the actual mechanism during implementation; do not assume that a custom Postgres role can be safely assumed by an Edge Function without a tested connection/authentication design.

## 4. Database function contract

The production database function must not rely on the test harness's current_setting('role') = 'temmy_ctest_gateway' check as proof of a real teacher identity. That role is test-only.

For the first implementation, a verified actor ID may be passed from the Gateway to a server-only function argument only when:

1. The Gateway has validated the Supabase access token.
2. The database entrypoint is executable only by the trusted server role.
3. Browser roles cannot call the entrypoint directly.
4. The function independently checks the actor's ownership/authorization against stored relationships.
5. The actor ID argument is never populated from untrusted browser input.

The implementation review must explicitly assess the risk of using a shared service-role credential and actor-ID parameter. If a stronger database-verifiable identity propagation method is available and compatible with the deployment, prefer it. In either case, the database must not trust a caller-supplied teacher ID from an authenticated browser session.

## 5. Request validation and authorization

For every operation, the Gateway and database function must validate the complete operation-specific contract. Examples:

- Award/deduction: teacher authorization, student/class ownership, whole-number amount, configured cap, reason and operation constraints.
- Activity score: teacher ownership of activity and student submission, score bounds, and the approved score-delta/balance rules.
- Reversal: ownership of the original transaction, eligible transaction type, no prior reversal, and sufficient remaining balance for full reversal.
- Marketplace purchase: student and reward ownership, active reward, price, stock, available balance, one-student request, and idempotency key/payload binding.

The database transaction function remains the final enforcement point for invariants and atomic writes. Gateway checks improve request handling but do not replace database enforcement.

## 6. Secrets, logging, and failure behaviour

- Never log access tokens, service-role keys, passwords, or full authorization headers.
- Log safe request identifiers, actor IDs where appropriate, operation names, outcomes, and correlation IDs according to a reviewed retention/privacy policy.
- Fail closed when token validation, teacher authorization, database access, or required configuration is unavailable.
- Do not retry a non-idempotent mutation with a new request ID after an uncertain response. Retry using the same request ID and canonical payload.
- Do not return internal SQL errors, secrets, stack traces, or privileged database details to the browser.
- Define rate limits and abuse controls for Gateway endpoints before public launch.

## 7. Required verification before deployment

In a fresh disposable environment only:

1. Valid teacher token maps to the correct verified teacher UUID.
2. Invalid, expired, revoked, wrong-project, and missing tokens are rejected.
3. A browser-supplied forged teacher ID is ignored or rejected.
4. Teacher A cannot operate on Teacher B's class, student, activity, reward, or transaction.
5. anon and authenticated cannot execute protected transaction functions directly.
6. The trusted Gateway role can execute only the intended entrypoints.
7. No generic RPC/SQL proxy or alternate browser path bypasses Gateway checks.
8. Service-role credentials are absent from browser bundles, network responses, client storage, and logs.
9. Function owner, SECURITY DEFINER behaviour, fixed search path, helper permissions, and effective EXECUTE ACLs are verified.
10. End-to-end mutation, idempotency, concurrency, audit, and atomicity tests pass.

## 8. Explicit non-goals and safety boundary

This is a design decision, not an implementation report. It does not authorize:

- Hosted Supabase SQL, grants, revokes, policies, functions, migrations, or test writes.
- Deployment of an Edge Function or any other service.
- Changes to GitHub main or shared cloud-test.
- Changes to the existing classroom application or its production data.
- Connection of the future game platform.

All future implementation and deployment steps require separate review and explicit approval. The current SQL function drafts and temmy_ctest_* role harness remain synthetic, unexecuted review artifacts until the identity design is implemented and verified in a fresh disposable environment.
