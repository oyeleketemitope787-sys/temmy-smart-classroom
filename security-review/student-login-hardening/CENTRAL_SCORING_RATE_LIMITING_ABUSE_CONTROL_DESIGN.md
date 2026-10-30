# Central Game Scoring — Rate Limiting and Abuse-Control Design

**Status:** Review proposal only. Not deployed. No secrets, database changes, student records, or production settings changed.
**Branch:** `security-review/student-login-hardening`

## Why this is a release gate

The Edge Function currently validates request shape, limits the body to 16 KiB, checks browser Origin when present, and keeps the service-role key server-side. It does not implement request rate limiting, durable abuse counters, or automated abuse response. Origin/CORS checks are browser controls, not authentication: non-browser clients can omit or forge Origin.

The gateway must remain disabled until the controls below are implemented and tested.

## Threats to address

1. Repeated `start_attempt` requests that consume CPU generating question sets or repeatedly reach the database.
2. High-frequency answer submissions that create avoidable database contention.
3. Token guessing, replay, and attempts to use expired, consumed, or mismatched sessions.
4. Distributed requests from many clients that bypass per-process memory counters.
5. Automated traffic that targets the public endpoint without a browser Origin.
6. Logging or telemetry that accidentally records raw session tokens, access codes, answer keys, or service credentials.

## Required layered controls

### 1. Edge / ingress protection

Before enabling writes, place a durable rate-control layer in front of the function or use a platform-supported shared rate-limit service. Do not rely on an in-memory map in a serverless Edge Function: instances can scale independently, restart, and receive traffic unevenly.

Apply configurable limits by:
- trusted ingress client/network identity where the hosting platform provides it;
- endpoint/action (start versus answer);
- global endpoint capacity, with a protective concurrency ceiling.

Do not trust arbitrary `X-Forwarded-For`, `Forwarded`, or client-supplied identity headers. Only use source metadata documented as overwritten by the trusted ingress. If reliable client identity is unavailable, do not pretend an IP-based policy is enforceable; use the session-scoped database controls below and a managed ingress control.

Return HTTP 429 with a short `Retry-After` value when a limit is reached. Do not expose internal quota keys or implementation details.

### 2. Durable session-scoped controls

Enforce quotas atomically in PostgreSQL, not with a read-then-write sequence in the Edge Function.

Proposed controls:
- One attempt per game session, enforced by a unique constraint on the attempt's session identifier.
- A small configurable cap on attempt-start requests per session and time window, including failed/repeated starts.
- A configurable minimum interval between accepted answer submissions for a session, with allowance for normal classroom interaction and network retries.
- A maximum number of malformed/invalid requests per session before temporary suspension of that session.
- Continue to rely on row locks, sequence checks, expiry checks, and exact-answer idempotency for correctness. Rate limiting is supplementary and must never change a verified score.

Quota updates and decisions must be atomic. A repeated identical answer retry should return the stored result and must not consume a second answer quota or award again. A conflicting duplicate, skipped question, or invalid token must never change score.

The exact numeric thresholds are configuration decisions and should be tuned with classroom usage data before rollout; this proposal intentionally does not hard-code them.

### 3. Protect question generation

The current handler generates the Number Challenge question set before calling `begin_game_attempt`. Add a cheap, durable start-attempt admission check before generation, then enforce the final one-attempt-per-session rule inside the database transaction. The admission check is not a replacement for the database uniqueness constraint.

### 4. Monitoring and safe telemetry

Record structured events for:
- rate-limit decisions and action type;
- invalid, expired, used, or mismatched sessions;
- duplicate retries versus conflicting duplicate answers;
- gateway errors, database latency, and completion/award counts.

Never log raw session tokens, student access codes, answer keys, service-role credentials, or full request bodies. Use a keyed, rotating HMAC pseudonym for session correlation if correlation is needed. Restrict access to logs and define a retention period.

Alert on sudden increases in 429 responses, invalid-session traffic, gateway failures, database contention, and unusual award volume. Alerts must not automatically alter student points.

### 5. Fail-closed behavior

- If the shared rate-limit service is unavailable, reject new attempt starts rather than bypassing the limit.
- Do not fail open to local in-memory counters.
- Preserve idempotent answer retries where the database can safely return the already-stored response.
- Rate-limit failures must not create point transactions or mutate attempt scores.
- Keep both gateway feature flags disabled until the complete design is implemented and tested.

## Required tests before release

1. Concurrent start requests for one session create at most one attempt and cannot bypass the start quota.
2. Parallel answer requests for one session remain serialized and award at most once.
3. Identical retry after a timeout returns the stored answer/result without a second quota charge or reward.
4. Conflicting duplicate, out-of-order, expired, consumed, and invalid-session requests are rejected without score mutation.
5. Limits remain effective across multiple Edge Function instances and restarts.
6. Ingress identity headers supplied by the caller cannot spoof the trusted client identity.
7. Rate-limit service outage fails closed for new starts.
8. Public practice mode remains usable without a student reward session and cannot create student point transactions.
9. Logs and error responses contain no tokens, access codes, answer keys, or credentials.

## Decisions still required

- Approve numeric thresholds for start attempts, answer pacing, invalid requests, and global capacity.
- Select the durable ingress/shared rate-limit mechanism available in the deployment environment.
- Set log retention and alert ownership.
- Confirm whether a completed zero-score attempt should create a zero-point transaction or only a completed attempt record. This is a separate scoring-ledger policy and must be reflected consistently in schema, SQL functions, UI, and tests.

## Release position

**NO-GO.** This is a design checklist, not an implemented control. The gateway remains review-only and default-disabled. Do not configure either feature flag, deploy the function, apply SQL, or change shared Supabase permissions on the basis of this document.
