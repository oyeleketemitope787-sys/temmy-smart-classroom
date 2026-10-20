# Verified Game-Session RPC Finding

Status: read-only database evidence supplied by the project owner on 2026-10-20. No database or deployment changes were made.

## Function inspected

`public.start_student_game_session(p_access_code text, p_game_id text)`

Observed properties:
- Returns a session token, student/class identifiers and names, and expiry.
- Declared `SECURITY DEFINER` with `search_path = public`.
- Calls `public.verify_student_access_code(p_access_code)`.
- Returns no row when code verification fails or the class is inactive.
- Creates a `student_game_sessions` row with the caller-supplied `p_game_id`.
- Sets expiry to `now() + interval '30 minutes'`.
- The supplied definition does not validate `p_game_id` against an approved game catalogue.

## Effective EXECUTE evidence

The owner supplied this result from `has_function_privilege`:
- `anon_can_execute = true`
- `authenticated_can_execute = true`
- `service_role_can_execute = true`
- `proacl = null`

Interpretation: null explicit ACL does not mean inaccessible. Effective checks confirm anonymous execution is currently allowed.

## Client-call-site search

Searches in the GitHub index for `start_student_game_session`, `session_token`, `student_game_sessions`, and `p_game_id` returned no indexed matches in the inspected `temmy-smart-classroom` and `temmy-smart-games` repositories. This is inconclusive: code search indexing may be incomplete and deployed pages may live elsewhere.

## Decision

NO-GO for permission changes or gateway deployment.

Before any change:
1. Identify every deployed caller, including game launchers and static pages.
2. Confirm all code-consuming RPC call sites and response contracts.
3. Implement gateway and limiter on the review branch only.
4. Arrange a safe test path isolated from the shared live Classroom database.
5. After full migration and testing, review exact EXECUTE restrictions as a separate approved rollout step.

Do not revoke anonymous execution now: that could break student game launch. Do not enable the scaffold: it intentionally returns 503 and is not a working gateway.

## Separate authorization issue

The function accepts caller-provided `p_game_id` without visible allowlist validation. Review this independently from rate limiting; do not silently add an allowlist until valid game IDs and legitimate launcher behavior are inventoried.
