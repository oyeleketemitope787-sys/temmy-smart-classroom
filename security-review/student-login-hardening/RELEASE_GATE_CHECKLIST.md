# Student Access Gateway — Release Gate Checklist

Status: NOT APPROVED FOR RELEASE. This checklist is a planning/review artifact; it does not execute SQL or deploy anything.

## Gate A — Database evidence
- [ ] Run the corrected read-only audit against the current Supabase project.
- [ ] Review every returned function signature, owner, security-definer setting, volatility, search path, source, and effective EXECUTE grant.
- [ ] Compare explicit grants with default privileges and role inheritance.
- [ ] Identify and classify every candidate function; do not apply blanket revokes.
- [ ] Preserve teacher-side `generate_student_access_code(p_student_id)` authorization.
- [ ] Confirm the verifier remains safe for all call contexts, including the STABLE point-history function.

**Stop if:** the audit output is missing, ambiguous, or differs from the function/caller inventory.

## Gate B — Caller coverage
- [ ] Find all calls to the nine student-facing RPCs across the Classroom and game launch pages/repositories.
- [ ] Locate the caller of `start_student_game_session(p_access_code, p_game_id)`.
- [ ] Verify no deployed client has an alternate direct-RPC path.
- [ ] Specify one fixed gateway action for each allowed operation and map it to an exact RPC signature.
- [ ] Document teacher-only paths separately.

**Stop if:** any legitimate caller remains unknown or calls direct RPCs after cutover.

## Gate C — Gateway implementation
- [ ] Keep the function fail-closed until all controls are implemented.
- [ ] Enforce method, content type, body size, access-code format, and per-action input validation.
- [ ] Use an explicit action allowlist; never accept a browser-provided RPC name.
- [ ] Keep service credentials and HMAC secrets server-side only.
- [ ] Implement atomic rate-limit counters with bounded retention and cleanup.
- [ ] Do not store raw access codes or unkeyed hashes of short codes.
- [ ] Use client-source/IP limits only after the proxy's source metadata is proven trustworthy.
- [ ] Ensure generic safe errors; do not expose raw database errors or credentials.
- [ ] Confirm CORS preflight behavior for the actual permitted origins.
- [ ] Decide and implement HMAC key rotation and incident response.

**Stop if:** limiter atomicity, key handling, expiry/cleanup, source trust, or fail-closed behavior is unproven.

## Gate D — Client compatibility
- [ ] Preserve login and list/read/submit/send result shapes.
- [ ] Preserve scalar integer result for `mark_student_messages_read`, or adapt it explicitly.
- [ ] Ensure the frontend unwraps any gateway envelope intentionally.
- [ ] Confirm the student access code is not persisted or logged.
- [ ] Review `p_game_id` authorization against an authoritative allowlist; shape checks alone are insufficient.

**Stop if:** any expected field or response shape changes without a tested adapter.

## Gate E — Test strategy
- [ ] Complete static and unit tests without using the shared database for attack simulations.
- [ ] Verify rate-limit behavior, atomicity, expiry, safe logging, and failure modes in an isolated test environment.
- [ ] Verify all student workflows with approved low-risk checks.
- [ ] Confirm no brute-force, concurrency, spoofed-header, or lockout testing is run against the shared Classroom database.

**Stop if:** isolated testing is unavailable for a test that could lock out students or mutate shared state.

## Gate F — Deployment approval
- [ ] Owner explicitly approves the exact gateway/client/SQL change set.
- [ ] Record pre-change function definitions, grants, frontend commit, gateway version, and rollback procedure.
- [ ] Deploy gateway and secrets.
- [ ] Deploy matching client changes.
- [ ] Verify gateway and legitimate student workflows.
- [ ] Only then apply narrowly scoped, reviewed anonymous EXECUTE revokes.
- [ ] Re-run the effective-ACL audit and confirm the intended result.
- [ ] Monitor aggregate error and throttle metrics without logging secrets.

## Rollback gate
- [ ] Restore a compatible gateway/client pair.
- [ ] Never revert to a direct-RPC frontend while anonymous execution is revoked unless an explicitly approved ACL rollback is required.
- [ ] Restore only the exact reviewed ACL snapshot if necessary; never use broad blanket grants.
- [ ] Rotate exposed secrets and document residual risk.
- [ ] Re-verify login, messages, activities, game sessions, point history, and effective grants.

## Current blockers
1. Corrected SQL audit output has not yet been reviewed in this conversation.
2. Caller coverage for `start_student_game_session` is unresolved.
3. Trusted source metadata is unresolved.
4. Atomic limiter, HMAC secret lifecycle, and operational cleanup/monitoring are not implemented.
5. No isolated Supabase project is available; risky tests against the shared backend are prohibited.
6. The gateway scaffold is fail-closed and not a functioning deployed gateway.

## Current decision
**NO-GO. Documentation only. No active rate-limiting protection is claimed.**
