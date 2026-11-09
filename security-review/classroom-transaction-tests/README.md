# Classroom Transaction Test Fixture

**Status:** Review-only synthetic fixture draft  
**Specification:** `security-review/student-login-hardening/CLASSROOM_TRANSACTION_TEST_SPECIFICATION_V1.0.md`  
**SQL design:** `security-review/student-login-hardening/CLASSROOM_TRANSACTION_SQL_DESIGN_REVIEW_ONLY.sql.txt`

## Safety boundary

This directory is for a separate disposable PostgreSQL test suite. Its schema is synthetic and is not a verified copy of the hosted Supabase database.

- Never run these SQL files in Supabase SQL Editor or against a hosted/shared database.
- Do not place these files in `supabase/migrations`.
- Do not add hosted Supabase credentials to the test workflow.
- Do not change `main`, `cloud-test`, the existing game-scoring fixture, or its workflow.
- No production grants, revokes, policies, functions, or deployments are authorized by this test fixture.

## Current contents

- `CLASSROOM_TRANSACTION_FIXTURE_SCHEMA.sql` — synthetic table and role model only. It does not yet contain transaction functions or test data for business scenarios.

## Fixture design notes

1. The fixture is separate from the game-scoring fixture and workflow.
2. It includes synthetic activity, marketplace, purchase, idempotency, audit, and configuration structures.
3. `marketplace_rewards`, `purchases`, `transaction_requests`, and `transaction_audit` are proposed test structures, not claims about production schema.
4. No `UNIQUE(activity_id, student_id)` constraint is present.
5. `NULL` reward stock means unlimited stock; finite stock is non-negative.
6. The fixture seeds a maximum teacher award of 100 points solely as a test value. The production maximum remains undecided.
7. Point transactions use signed values: positive credits and negative debits.
8. Direct table write grants are withheld from browser roles. Exact function execution grants will be added only after the trusted actor boundary is designed and reviewed.
9. The test harness must simulate a verified Gateway identity. A caller-controlled teacher ID or user-writable session variable must never be treated as authenticated identity.

## Planned separate test assets

- `CLASSROOM_TRANSACTION_FUNCTIONS.sql` — transaction functions for disposable tests only.
- `CLASSROOM_TRANSACTION_SMOKE_TESTS.sql`
- `CLASSROOM_TRANSACTION_EDGE_CASES.sql`
- `CLASSROOM_TRANSACTION_ACL_TESTS.sql`
- `CLASSROOM_TRANSACTION_CONCURRENCY_TESTS.sql`
- `CLASSROOM_TRANSACTION_ATOMICITY_TESTS.sql`
- `CLASSROOM_TRANSACTION_TEST_PLAN.md`
- A dedicated review-branch CI workflow, separate from game-scoring tests.

These are planned, not yet implemented. No CI workflow has been added.

## Next gates

Before executable transaction functions are drafted:
- Review this fixture's logical schema and role assumptions.
- Decide a safe test-only trusted-actor harness that cannot be invoked by browser roles.
- Decide how to serialize all point-balance mutations consistently.
- Define exact idempotency retry/recovery behaviour.
- Keep rejected-operation audit separate from success audit if the business transaction rolls back.
- Then write functions and tests against this fixture and run them only in a fresh disposable local/CI PostgreSQL database.
