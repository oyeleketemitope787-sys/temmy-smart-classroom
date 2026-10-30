# Central Scoring Database Integration — Readiness Review

**Status:** Review-only; database integration tests are blocked pending verified schema metadata.
**Branch:** `security-review/student-login-hardening`
**Scope:** Static review of the proposed attempt schema, atomic functions, gateway adapter, and previously supplied audit evidence. No database connection, SQL execution, migration, grants, deployment, or production change was made.

## Verified existing evidence

- The review-branch GitHub Actions workflow currently runs Deno type-checking and unit tests for request validation, question generation, and scoring/display. The latest inspected run (40518746857) completed successfully.
- The gateway is default-disabled and returns HTTP 503 before creating a Supabase client/RPC call unless both server-side flags are explicitly true.
- The proposed SQL remains in `security-review` as `.sql.txt` design material, not a migration.
- Earlier user-supplied read-only audit output identified `record_student_game_result(uuid, text, text, integer, integer)` as a legacy SECURITY DEFINER reward writer. Its implementation uses `LEAST(p_score, p_max_score)`, and the complete deployed caller inventory remains unresolved.
- The existing session trace is partial. It does not establish every deployed caller or the exact current schema.

## Static review findings that block a trustworthy PostgreSQL CI test

1. **The real schema is not present in this repository snapshot.** The proposed SQL assumes exact columns and types for `student_game_sessions`, `students`, `classes`, and `point_transactions`. The review branch has no authoritative schema migration history to build a faithful disposable fixture from.
2. **Point transaction constraints are unknown.** The proposed SQL creates a transaction for every completed attempt, including a possible zero-score completion. We must verify whether `point_transactions.points` permits zero and whether its other required columns, constraints, triggers, and balance logic match the proposed insert.
3. **Session lifecycle assumptions need confirmation.** The proposal assumes a UUID token, `expires_at`, nullable `used_at`, and a specific session-to-student/class/game relationship. These must match the actual database exactly.
4. **The attempt schema and function draft must be tested together.** A hand-written mock schema that merely makes the SQL compile could hide incompatibilities with the actual app and would create misleading confidence.
5. **Legacy reward paths remain a release blocker.** Do not revoke existing RPC permissions or change point transaction policies until all callers and teacher/classroom point-writing flows are accounted for.

## Required next input — read-only metadata only

Before adding PostgreSQL integration tests, obtain current output from the existing read-only inventory script:

`security-review/student-login-hardening/READ_ONLY_GAME_ASSIGNMENT_SCHEMA_INVENTORY.sql`

The output should include column names/types/nullability/defaults, foreign keys, and candidate function signatures. It must not include student records, access codes, session tokens, or point-history rows.

Also obtain read-only constraint/index/trigger metadata for `public.point_transactions` and `public.student_game_sessions`, plus the effective ACL output for the existing game-result/session functions. Do not execute any proposed DDL or function definitions on the shared TEST/production project.

## Safe next implementation after metadata arrives

- Create a disposable PostgreSQL service in GitHub Actions.
- Build a fixture schema that matches verified production table definitions and required constraints, using synthetic records only.
- Convert the reviewed SQL proposal into a test-only SQL fixture or migration artifact in the review branch; do not place it in the deployable migrations directory yet.
- Exercise begin/resume, answer correctness, duplicate same-answer retry, conflicting retry, out-of-order answer, invalid/expired/used session, challenge third-life completion, final-answer completion, and concurrent duplicate submissions.
- Assert exactly one reward transaction per completed attempt, exact score equals awarded points, correct game-specific maximum, and no transaction before completion.
- Keep secrets absent and network access to all hosted Supabase projects absent from the CI job.

## Release status

**NO-GO.** Current unit/contract tests are successful, but no database integration test has been run. The gateway remains disabled; no database or live application has been changed.
