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

- `CLASSROOM_TRANSACTION_FIXTURE_SCHEMA.sql` — synthetic tables and isolated test-role model.
- `TRUSTED_ACTOR_IDENTITY_DESIGN.md` — restricted test-only gateway identity model and unresolved production identity propagation.
- `TRANSACTION_FUNCTION_DESIGN_REVIEW_ONLY.md` — operation algorithms, idempotency, balance serialization, lock order, audit and test requirements; design document, not executable SQL.
- `CLASSROOM_TRANSACTION_FUNCTIONS_PHASE1_REVIEW_ONLY.sql.txt` — draft SECURITY DEFINER helpers plus teacher award and deduction functions.
- `CLASSROOM_TRANSACTION_FUNCTIONS_PHASE2_REVIEW_ONLY.sql.txt` — draft full award reversal and atomic activity score adjustment functions.
- `CLASSROOM_TRANSACTION_FUNCTIONS_PHASE3_REVIEW_ONLY.sql.txt` — draft one-student marketplace purchase function with stock locking, purchase snapshot, ledger debit and idempotent success replay.
- `CLASSROOM_TRANSACTION_TEST_SEED.sql.txt` — deterministic synthetic teacher, class, student, activity, ledger and marketplace rows.
- `CLASSROOM_TRANSACTION_SMOKE_TESTS.sql.txt` — successful-path smoke checks for award, deduction, reversal, activity scoring, marketplace purchase and successful retry replay; outer transaction rolls back.
- `CLASSROOM_TRANSACTION_EDGE_CASES.sql.txt` — draft rejection/no-op checks for insufficient balance, stock, inactive rewards, cross-teacher access, award cap, zero-balance deduction and invalid activity scores.
- `CLASSROOM_TRANSACTION_ACL_TESTS.sql.txt` — read-only catalog/privilege assertions for client-role isolation, gateway entrypoint grants, helper restrictions, function ownership and fixed search paths.
- `CLASSROOM_TRANSACTION_CONCURRENCY_TEST_PLAN.md` — two-session protocol for finite stock, balance serialization, same-key replay, payload mismatch and concurrent awards/deductions.
- `CLASSROOM_TRANSACTION_ATOMICITY_TEST_PLAN.md` — test-only failure-injection protocol to prove multi-table operations fully roll back when a later write or success-audit write fails.
- `STATIC_REVIEW_FINDINGS_V1.md` — static review findings and pre-execution gates for the Phase 1–3 function drafts.

## Fixture design notes

1. The fixture is separate from the game-scoring fixture and workflow.
2. It includes synthetic activity, marketplace, purchase, idempotency, audit and configuration structures.
3. `marketplace_rewards`, `purchases`, `transaction_requests` and `transaction_audit` are proposed test structures, not claims about production schema.
4. No `UNIQUE(activity_id, student_id)` constraint is present.
5. `NULL` reward stock means unlimited stock; finite stock is non-negative.
6. The fixture seeds a maximum teacher award of 100 points solely as a test value. The production maximum remains undecided.
7. Point transactions use signed values: positive credits and negative debits.
8. Browser test roles have no direct table writes. The gateway test role has no direct table grants; narrow function EXECUTE grants are defined in the separate drafts and still require ACL verification.
9. Role names are namespaced as `temmy_ctest_*` to avoid colliding with standard Supabase roles or other local roles.
10. The fixture refuses to reuse pre-existing namespaced test roles. Run only in a fresh disposable PostgreSQL cluster with a dedicated administrator.
11. The test harness simulates an already-verified teacher identity; it does not test Supabase JWT or production Edge Function authentication.
12. All balance-changing operations must lock the same student row before reading the ledger balance.

## Current review status

Phase 1–3 function drafts cover teacher awards, deductions, full award reversal, activity score adjustment and one-student marketplace purchase. The deterministic synthetic seed, successful-path smoke test, initial edge-case checks, ACL assertions, concurrency protocol and atomicity/failure-injection protocol are also drafted.

**None of the SQL has been executed or syntax/runtime tested.** The ACL, concurrency and atomicity protocols have not been run. The failure-injection triggers described in the atomicity plan have not been created. A static review has identified unresolved actor-identity, class-row locking, rejected-request audit/idempotency and no-op audit decisions; see STATIC_REVIEW_FINDINGS_V1.md. No production or hosted database changes have been made.

## Next gates

Before any SQL is executed in a disposable test database:

- Positively identify a fresh disposable database/cluster; do not use the existing local classroom database without separate explicit approval.
- Review the fixture, seed, smoke-test and edge-case assumptions, including the zero-balance setup and exception-catching harness.
- Pin PostgreSQL version and confirm SHA-256 helper availability.
- Verify SECURITY DEFINER role-context behaviour, function owner, fixed `search_path` and function ACLs.
- Finalize stable result/error codes and durable rejected-request semantics.
- Review lock order and concurrency behaviour.
- Review and validate the test-only failure injector so each failpoint occurs after the intended preceding mutation.
- Only after static review should the suite be run against synthetic data in a fresh disposable local/CI PostgreSQL database.

Production identity propagation, production schema reconciliation, and any hosted changes remain separate gates requiring explicit review and approval.
