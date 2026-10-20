# Rate-Limiter Design Decision Matrix

**Status:** review-only decision aid. No final thresholds or implementation selected; no database, frontend, secret, or deployment changes made.

## Current constraints

- The TEST frontend and live Classroom share one Supabase database.
- No isolated project is currently available for deliberate invalid-code, concurrency, spoofed-header, or lockout testing.
- Nine student-facing public functions in the supplied SQL definitions call `verify_student_access_code`.
- `get_student_point_history` is SQL `STABLE` while invoking that verifier, so a write-based counter must not be added blindly to the verifier.
- Student codes have been observed as eight hexadecimal characters (32 bits of randomness).
- The current gateway scaffold intentionally fails closed and does not execute RPCs.

## Options

| Option | Advantages | Main risks / work | Current assessment |
| --- | --- | --- | --- |
| Add attempt writes inside `verify_student_access_code` | One common verification point; potentially covers all callers | `STABLE` caller conflict; code-only counters can lock out a victim; must inspect every caller and transactional behavior | **Do not implement directly yet.** First resolve volatility and lockout design. |
| Add a separate limiter call to each student RPC | Clear per-endpoint accounting and can cover actions uniformly | More function edits; risk missing a function; repeated checks may double-count; must preserve signatures and grants | Possible, but broad migration and rollback review required. |
| Edge Function gateway with privileged server client | Centralized request validation; browser no longer calls student RPCs directly | Every browser call must migrate; direct anonymous grants must be removed in coordinated order; service-role credential is powerful; trusted source metadata unresolved | Preferred architectural direction only if narrow execution and complete coverage are proven. Not deployable now. |
| Edge Function using anon role while anonymous RPC grants remain | Avoids privileged server key | Direct browser calls can bypass gateway and its limits | **Not an effective security boundary.** |
| Client-side throttling only | Easy to add | Easily bypassed by direct RPC calls | **Reject as a security control.** |

## Recommended decision at this stage

Do not write or run the production migration yet. Continue static review and prepare a candidate design, but leave thresholds unset until expected normal traffic and denial-of-service tradeoffs are considered.

A viable future design must avoid long code-only lockouts. If trusted source identity cannot be verified, the first release must not claim IP-based limiting. A keyed code fingerprint must use a server-held HMAC key with versioning/rotation; never persist raw codes or an unkeyed hash of the short code.

## Minimum pre-migration gates

1. Confirm every direct RPC call in the classroom frontend and any separate game-launch code.
2. Confirm the complete RPC inventory, function definitions, ownership and grants.
3. Choose where the atomic attempt counter is enforced and prove all paths pass through it.
4. Resolve the `STABLE` history function constraint without breaking existing behavior.
5. Specify generic failure responses and a recovery path that does not let attackers lock out individual students.
6. Design secret handling, key rotation, bounded expiry/cleanup, exact grants, and rollback.
7. Test in a genuinely isolated database before any production rollout.
8. Obtain separate explicit approval for the SQL migration, Edge Function deployment, secrets, and frontend migration.

## Status

Static design only. No SQL executed; no secrets created; no function deployed; no production or TEST frontend modified.
