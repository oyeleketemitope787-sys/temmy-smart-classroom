# Student Access Gateway — Migration and Rollback Runbook (Review Only)

Status: planning document only. Nothing in this runbook has been executed against Supabase.

## Safety boundary

- Target branch for review artifacts: `security-review/student-login-hardening`.
- Do not modify `main` or `cloud-test` as part of this review.
- The TEST frontend and production Classroom share the same Supabase project (`askhdgmjqezvwavfhqzj`). Therefore, a database migration, function deployment, secret change, or permission change would affect the shared backend and must not be treated as isolated testing.
- No SQL migrations, rate-limit writes, Vault secrets, Edge Function deployments, or frontend deployments are authorized by this runbook.
- Do not run brute-force, concurrency, spoofed-header, or lockout tests against the shared backend.

## Why the change must be staged

Nine student-facing RPCs use `verify_student_access_code`. The current browser calls those RPCs directly, and direct anonymous execution remains available for the student-facing calls. Deploying a gateway alone would not close that bypass. Revoking direct execution before every legitimate caller has migrated would break student functionality.

The `get_student_point_history(p_access_code text)` function is declared `STABLE`. Do not add write-based attempt-counter logic inside `verify_student_access_code` without a separate PostgreSQL volatility/call-context review; this can fail when called from a STABLE function. Keep rate limiting outside the verifier, at a gateway boundary, unless a separately reviewed database design proves safe.

## Required migration order (future change only)

### Gate 0 — Inventory and freeze
- Confirm the exact deployed definitions and effective ACLs for every code-consuming RPC using the corrected read-only audit.
- Find every caller, including game-launch code outside `cloud-test/index.html`. The caller for `start_student_game_session` is not yet accounted for; do not claim coverage is complete.
- Confirm which roles call each RPC and which calls are teacher-only. Preserve the existing authorization of `generate_student_access_code(p_student_id)`.
- Record baseline login, messages, live activities, game sessions, point history, activity submission, and student messaging behavior without mutating shared data.

**Stop condition:** any unknown caller, unresolved effective grant, or unverified source-IP trust policy means no rollout.

### Gate 1 — Implement the gateway in review
- Use a fixed action allowlist; never accept a browser-supplied RPC/function name.
- Validate HTTP method, content type, bounded request body, access-code format, action-specific fields, and request size.
- Keep service-role credentials and the HMAC key server-side only. Never log access codes, session tokens, HMAC inputs, or service credentials.
- Use atomic, bounded, expiring counters keyed by a server-held HMAC; never store raw codes or unkeyed hashes of short codes.
- Only use source/IP rate limiting if the platform's source metadata is proven trustworthy. Header presence alone is not proof. Until resolved, do not claim source-based protection.
- Preserve the existing response shapes or add a deliberate browser adapter: login and list/read/submit/send operations currently expect arrays; `mark_student_messages_read` expects a scalar integer. A generic `{data: ...}` envelope must not silently break callers.
- Keep the scaffold fail-closed until the limiter, RPC allowlist, privileges, CORS behavior, and response contracts are implemented and reviewed.

### Gate 2 — Review all clients and contracts
- Update every browser/game caller together in a dedicated change, not in this planning-only branch.
- Confirm that the access code is held only as long as needed in client memory and is never persisted or logged.
- Confirm generic safe errors do not expose internal database messages.
- Validate CORS preflight for the exact production and test origins.
- Resolve and review the `p_game_id` authorization/allowlist question separately; shape validation is not authorization.

### Gate 3 — Pre-rollout verification
- Run unit/static tests and response-contract tests without calling the shared database.
- Verify limiter atomicity, expiry/cleanup, HMAC key handling/rotation, fail-closed behavior, safe logs, and rollback steps in an isolated environment. No isolated Supabase project is currently available, so do not substitute the shared project for risky tests.
- Prepare a precise ACL change listing every function and role. Do not generate or apply broad blanket revokes until the call-site inventory and corrected audit agree.

### Gate 4 — Controlled release (not approved or scheduled)
Only after all prior gates pass and the owner explicitly approves a deployment:
1. Publish reviewed gateway code and server-side secrets.
2. Confirm gateway health and non-mutating contract checks.
3. Deploy the matching frontend/client adapter.
4. Verify all student flows using approved, low-risk checks.
5. Only then revoke direct anonymous execution from the complete set of migrated code-consuming RPCs, with an exact grant matrix and immediate verification.
6. Monitor safe aggregate metrics and error rates.

Do not revoke `verify_student_access_code` permissions or alter teacher-side functions by assumption; derive every ACL change from the reviewed effective-grant audit.

## Rollback principles

Rollback must restore service without reopening an unreviewed bypass or exposing secrets.

- Before any release, save the exact prior frontend commit, gateway version, function definitions, and ACL snapshot.
- If the gateway fails before direct grants are changed, disable routing to it and restore the previous client only if the previous path is known safe for the incident; record that direct RPC access remains a security gap.
- If direct anonymous grants have been revoked, do not simply roll back the frontend to a version that calls RPCs directly. First restore a compatible, reviewed gateway/client pair or use a specifically reviewed ACL rollback approved by the owner.
- Never delete rate-limit tables or counters as a first response to an incident. Disable/adjust limiter behavior only through a reviewed change that preserves data integrity.
- Rotate any exposed secret immediately; never put a replacement secret in Git or browser code.
- After rollback, verify login, messages, activity, game-session, and point-history contracts, plus effective ACLs. Document residual risk.

## Open blockers

1. Corrected effective-ACL audit output has not yet been reviewed in this thread.
2. `start_student_game_session` caller coverage is unresolved.
3. Trusted client-source metadata policy is unresolved.
4. Atomic limiter implementation, HMAC secret lifecycle, storage cleanup, and operational monitoring are not implemented.
5. The gateway scaffold is intentionally fail-closed and is not deployable as a working gateway.
6. No isolated Supabase test environment is available; shared-backend attack/lockout tests are prohibited.

## Release decision

**NO-GO.** This is documentation only. No protection should be described as active until the gateway, client migration, limiter, ACL closure, and verification have all been completed and confirmed.
