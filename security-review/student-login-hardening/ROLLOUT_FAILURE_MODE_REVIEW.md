# Student Gateway — Rollout Sequence and Failure-Mode Review

Status: review-only companion to the implementation package. No live change is authorized or performed.

## Proposed sequence

```text
Inventory deployed callers and effective grants
                 |
                 v
Complete fixed-action gateway + atomic limiter + safe logging
                 |
                 v
Static/unit/contract tests in isolated environment
                 |
                 v
Migrate every client to gateway (including game-launch caller)
                 |
                 v
Verify all student workflows and gateway metrics
                 |
                 v
Apply exact, reviewed anonymous EXECUTE revokes
                 |
                 v
Re-run effective-grant audit and verify no bypass
```

This sequence is a proposal, not a deployment instruction. Do not begin the database-permission stage until every earlier gate is evidenced and the owner explicitly approves the exact change set.

## Failure-mode checklist

| Failure | Required behavior | Evidence required before release |
|---|---|---|
| Limiter database unavailable | Fail closed for code-consuming actions, with safe generic response; do not silently bypass the limiter | Unit/integration tests and observable safe metrics |
| Malformed/oversized request | Reject before database RPC; bounded request parsing | Tests for wrong method, content type, invalid JSON, body limit, missing/extra fields |
| Unknown action | Reject; never pass through arbitrary RPC names | Static review and negative tests |
| HMAC secret missing/invalid | Fail closed; do not fall back to raw code or an unkeyed hash | Startup/handler tests and secret-rotation runbook |
| Untrusted forwarded header | Ignore for identity/rate limiting until trusted source policy is documented | Hosting/proxy evidence and isolated validation |
| Rate limit reached | Return generic throttled response without revealing code/student existence | Contract tests for consistent messages/status |
| Client expects array but gateway returns envelope | Adapter explicitly unwraps or maps result; no implicit assumption | Contract tests for every action, including scalar mark-read result |
| Gateway deployed but old client remains | Do not revoke direct grants yet; block release until all clients migrated | Repository/call-site inventory and version/traffic evidence |
| Grants revoked too early | Roll back through reviewed ACL snapshot; do not ship a direct-RPC client as the fix | Dry-run rollback review and exact prior ACL snapshot |
| Game ID is syntactically valid but unauthorized | Reject against a trusted game/session authorization rule | Defined allowlist/authorization test; shape validation alone is not enough |
| Logs include code/token/secret | Treat as incident, remove exposure and rotate secrets where applicable | Log-field review and redaction tests |

## Counter design requirements

The implementation must define these before any SQL is written:

- Which dimensions are counted: action/request volume, failed verification, and any trusted source-level bucket.
- Whether an attempt is charged before verification and how successful attempts are counted.
- Atomicity under concurrent requests; read-then-write counters are insufficient.
- Bucket key format using a server-held HMAC and a key version identifier.
- Counter window/expiry behavior and bounded cleanup.
- What happens if the limiter table is full, unavailable, or under maintenance.
- How HMAC keys are provisioned, accessed by the database/Edge Function, rotated, and revoked without exposing them in logs or browser code.
- Aggregate observability that records action/outcome and latency without raw access codes, session tokens, secrets, or raw IP addresses.

Do not finalize numeric thresholds until expected classroom usage and the risk of denying legitimate pupils have been considered. Avoid long code-only lockouts that let an attacker lock out a known student's code.

## Database privilege design questions

Before writing a migration, decide and prove:

1. Which database role the Edge Function will use.
2. Whether the gateway role can execute the required functions after anonymous execution is revoked.
3. Whether those functions' SECURITY DEFINER owners, search paths, and internal table privileges are safe.
4. Whether the limiter schema is inaccessible to `anon` and `authenticated`, including via default privileges.
5. Whether a private HMAC helper can retrieve its secret without granting broad table or schema access.
6. Whether each exact function signature has only the grants needed by its intended caller.
7. Whether function ownership or role inheritance changes the effective grants.
8. Whether the existing `STABLE` point-history function remains compatible with the chosen design.

These questions cannot be answered solely from source text. Review the corrected audit output and actual role configuration before proposing executable SQL.

## Current release decision

**NO-GO.** The audit result, full game-launch caller, trusted-source policy, atomic limiter, HMAC lifecycle, isolated tests, and exact privilege plan remain open. This document changes no live system.
