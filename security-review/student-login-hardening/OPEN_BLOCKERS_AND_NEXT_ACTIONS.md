# Student Access-Code Hardening — Open Blockers and Next Actions

Status checked for the review branch on 2026-10-21. This is a planning note only; it does not change Supabase, frontend code, secrets, or deployments.

## Current confirmed state

- Review branch: `security-review/student-login-hardening`.
- The gateway scaffold is intentionally fail-closed and is not a functioning deployed gateway.
- No rate-limiter migration has been executed.
- No HMAC/Vault secret has been created for this work.
- No Edge Function has been deployed for this work.
- No frontend migration has been deployed.
- The test frontend and production Classroom share a Supabase project, so risky tests against that database remain prohibited.
- The corrected read-only audit SQL is available in this branch, but its current output has not yet been reviewed in this conversation.
- Searches did not locate `start_student_game_session` in the inspected repositories; search results do not prove the caller is absent.

## Blocking evidence

### Blocker 1 — Actual effective ACLs
Required: run the corrected read-only audit in Supabase SQL Editor and share its result. The result must be reviewed before producing exact permission statements. Source code alone is not sufficient to determine effective grants, default privileges, role inheritance, and owner behavior.

### Blocker 2 — Complete deployed call-site inventory
Required: locate every call to the student code-consuming RPCs, especially `start_student_game_session(p_access_code, p_game_id)`. Include the Classroom site, game launcher, static game pages, and any separate deployed client. A search miss is not proof of absence.

### Blocker 3 — Trusted request source
Required: establish whether the deployed edge/proxy supplies trustworthy source metadata. Do not trust client-controlled forwarding headers or claim IP limiting until verified. The diagnostic function remains a review draft and must not be deployed to the shared backend for probing.

### Blocker 4 — Limiter and secret design
Required: finalize atomic counters, HMAC key provisioning/rotation, expiry/cleanup, failure behavior, and safe aggregate monitoring. No raw access codes or unkeyed hashes of short codes may be stored or logged.

### Blocker 5 — Safe verification environment
Required: perform tests that could lock out users or create concurrent state only in an isolated environment. An isolated Supabase project is not currently available; do not substitute the shared Classroom backend.

## Next actions in order

1. Obtain and review the current read-only SQL audit output.
2. Complete caller discovery and explicitly resolve the game-session launcher.
3. Reconcile every action against the gateway action contract and exact function signatures.
4. Design the narrowest server-side role privileges and limiter access based on verified schema/ACL facts.
5. Implement and statically review the gateway and client adapter on the review branch only.
6. Establish a safe isolated test path before any test that could mutate data, lock out students, or test trust boundaries.
7. Only after all gates pass and the owner explicitly approves the exact changes, plan a coordinated rollout and permission closure.

## Current decision

**NO-GO for deployment or database changes.** Continue static review and evidence gathering only. Do not claim that student-code rate limiting or gateway protection is active.
