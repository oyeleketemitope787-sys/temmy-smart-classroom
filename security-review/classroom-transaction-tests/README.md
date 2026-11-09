# Classroom Transaction Test Fixture

**Status:** Review-only synthetic fixture draft  
**Specification:** `security-review/student-login-hardening/CLASSROOM_TRANSACTION_TEST_SPECIFICATION_V1.0.md`  
**SQL design:** `security-review/student-login-hardening/CLASSROOM_TRANSACTION_SQL_DESIGN_REVIEW_ONLY.sql.txt`  
**Actor boundary:** `TRUSTED_ACTOR_IDENTITY_DESIGN.md`  
**Function design:** `TRANSACTION_FUNCTION_DESIGN_REVIEW_ONLY.md`

## Safety boundary

This directory is for a separate disposable PostgreSQL test suite. Its schema is synthetic and is not a verified copy of the hosted Supabase database.

- Never run these SQL files in Supabase SQL Editor or against a hosted/shared database.
- Do not place these files in `supabase/migrations`.
- Do not add hosted Supabase credentials to the test workflow.
- Do not change `main`, `cloud-test`, the existing game-scoring fixture, or its workflow.
- No production grants, revokes, policies, functions, or deployments are authorized by this test fixture.

## Current contents

- `CLASSROOM_TRANSACTION_FIXTURE_SCHEMA.sql` — synthetic table and isolated test-role model only; no transaction functions or scenario seed data yet.
- `TRUSTED_ACTOR_IDENTITY_DESIGN.md` — restricted test-only gateway identity model and unresolved production identity propagation.
- `TRANSACTION_FUNCTION_DESIGN_REVIEW_ONLY.md` — operation algorithms, idempotency, balance serialization, lock order, audit and test requirements. Not executable SQL.
- `CLASSROOM_TRANSACTION_FUNCTIONS_PHASE1_REVIEW_ONLY.sql.txt` — draft SECURITY DEFINER helpers plus teacher award and deduction functions.
- `CLASSROOM_TRANSACTION_FUNCTIONS_PHASE2_REVIEW_ONLY.sql.txt` — draft full award reversal and atomic activity score adjustment functions.
- `CLASSROOM_TRANSACTION_FUNCTIONS_PHASE3_REVIEW_ONLY.sql.txt` — draft one-student marketplace purchase function with stock locking, purchase snapshot, ledger debit and idempotent success replay.
- `CLASSROOM_TRANSACTION_TEST_SEED.sql.txt` — fixed synthetic teacher, class, student, activity, ledger and marketplace rows for repeatable isolated tests.
- `CLASSROOM_TRANSACTION_SMOKE_TESTS.sql.txt` — successful-path smoke checks for award, deduction, reversal, activity scoring, marketplace purchase and successful retry replay; outer transaction rolls back.

## Fixture design notes

1. The fixture is separate from the game-scoring fixture and workflow.
2. It includes synthetic activity, marketplace, purchase, idempotency, audit, and configuration structures.
3. `marketplace_rewards`, `purchases`, `transaction_requests`, and `transaction_audit` are proposed test structures, not claims about production schema.
4. No `UNIQUE(activity_id, student_id)` constraint is present.
5. `NULL` reward stock means unlimited stock; finite stock is non-negative.
6. The fixture seeds a maximum teacher award of 100 points solely as a test value. The production maximum remains undecided.
7. Point transactions use signed values: positive credits and negative debits.
8. Browser test roles have no direct table writes. The gateway test role has no direct table grants; narrow function EXECUTE grants remain to be designed and tested.
9. Role names are namespaced as `temmy_ctest_*` to avoid colliding with standard Supabase roles or other local roles.
10. The fixture refuses to reuse pre-existing namespaced test roles. Run only in a fresh disposable PostgreSQL cluster with a dedicated administrator.
11. The test harness simulates an already-verified teacher identity; it does not test Supabase JWT or production Edge Function authentication.
12. All balance-changing operations must lock the same student row before reading the ledger balance.

## Planned separate test assets

- `CLASSROOM_TRANSACTION_FUNCTIONS.sql` — transaction functions for disposable tests only.
- `CLASSROOM_TRANSACTION_SMOKE_TESTS.sql`
- `CLASSROOM_TRANSACTION_EDGE_CASES.sql`
- `CLASSROOM_TRANSACTION_ACL_TESTS.sql`
- `CLASSROOM_TRANSACTION_CONCURRENCY_TESTS.sql`
- `CLASSROOM_TRANSACTION_ATOMICITY_TESTS.sql`
- `CLASSROOM_TRANSACTION_TEST_PLAN.md`
- A dedicated review-branch CI workflow, separate from game-scoring tests.

Phase 1 and Phase 2 function files are draft SQL text only and have not been executed or syntax-tested. Phase 1–3 transaction function drafts cover teacher awards, deductions, full award reversal, activity score adjustment, and one-student marketplace purchase. The deterministic synthetic seed and successful-path smoke test draft have also been added. None of the SQL has been executed or syntax/runtime tested. Edge/ACL/concurrency/atomicity tests and the dedicated CI workflow are not yet implemented.

## Next gates

Before executable test functions are drafted:
- Review the function contract and lock order against the synthetic fixture.
- Pin PostgreSQL version and confirm the built-in SHA-256 function availability.
- Finalize stable result/error codes and which business rejections are durably stored.
- Verify SECURITY DEFINER role-context behaviour, owner, fixed search_path and function ACLs.
- Review lock order and SQL syntax in a fresh disposable PostgreSQL database before implementing marketplace functions.
- Review the seed and smoke-test assumptions. Then build rejected-operation edge cases, ACL, concurrency and atomicity tests. Only after static review should the suite be run in a fresh disposable local/CI PostgreSQL database.

Production identity propagation, production schema reconciliation, and any hosted changes remain separate gates requiring explicit review and approval.
