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
- `CLASSROOM_TRANSACTION_FUNCTIONS_V2_FOUNDATION_REVIEW_ONLY.sql.txt` — replacement shared request, audit, hashing and class/student lock helpers; review-only.
- `CLASSROOM_TRANSACTION_FUNCTIONS_V2_PHASE1_REVIEW_ONLY.sql.txt` — V2 teacher award and deduction operations with durable rejection and no-op audit semantics; review-only.
- `CLASSROOM_TRANSACTION_FUNCTIONS_V2_PHASE2_REVIEW_ONLY.sql.txt` — V2 full award reversal and activity score adjustment operations; review-only.
- `CLASSROOM_TRANSACTION_FUNCTIONS_V2_PHASE3_REVIEW_ONLY.sql.txt` — V2 one-student marketplace purchase operation; review-only.
- `TRUSTED_ACTOR_IDENTITY_DESIGN.md` — restricted test-only gateway identity model.
- `TEMMY_GATEWAY_PRODUCTION_AUTHENTICATION_DESIGN.md` — user-approved production design target: Supabase Auth token verification at the server-side Gateway, actor ID derived from verified identity, and protected database transaction entrypoints.\n- `TEMMY_CLASSROOM_GLOBAL_LOCK_ORDERING_RULE.md` — user-approved class-before-student locking rule, global lock order, transfer/admin ordering and required concurrency tests.
- `TRANSACTION_FUNCTION_DESIGN_REVIEW_ONLY.md` — operation algorithms, idempotency, balance serialization, lock order, audit and test requirements; design document, not executable SQL.
- `CLASSROOM_TRANSACTION_FUNCTIONS_PHASE1_REVIEW_ONLY.sql.txt` — superseded historical draft; do not install or execute.
- `CLASSROOM_TRANSACTION_FUNCTIONS_PHASE2_REVIEW_ONLY.sql.txt` — superseded historical draft; do not install or execute.
- `CLASSROOM_TRANSACTION_FUNCTIONS_PHASE3_REVIEW_ONLY.sql.txt` — superseded historical draft; do not install or execute.
- `CLASSROOM_TRANSACTION_TEST_SEED.sql.txt` — deterministic synthetic teacher, class, student, activity, ledger and marketplace rows.
- `CLASSROOM_TRANSACTION_SMOKE_TESTS.sql.txt` — successful-path smoke checks for award, deduction, reversal, activity scoring, marketplace purchase and successful retry replay; outer transaction rolls back.
- `CLASSROOM_TRANSACTION_EDGE_CASES.sql.txt` — draft rejection/no-op checks for insufficient balance, stock, inactive rewards, cross-teacher access, award cap, zero-balance deduction and invalid activity scores.
- `CLASSROOM_TRANSACTION_ACL_TESTS.sql.txt` — read-only catalog/privilege assertions for client-role isolation, gateway entrypoint grants, helper restrictions, function ownership and fixed search paths.
- `CLASSROOM_TRANSACTION_RUNTIME_DENIAL_TESTS.sql.txt` — runtime direct-DML denial probes for anon, authenticated and gateway fixture roles; review-only and unexecuted.
- `CLASSROOM_TRANSACTION_IDEMPOTENCY_REVERSAL_TESTS.sql.txt` — durable rejection replay after configuration change, new-key re-evaluation, changed actor/operation conflicts and insufficient-balance reversal; review-only and unexecuted.
- `CLASSROOM_TRANSACTION_CONCURRENCY_TEST_PLAN.md` — two-session protocol for finite stock, balance serialization, same-key replay, payload mismatch and concurrent awards/deductions.
- `CLASSROOM_TRANSACTION_ATOMICITY_TEST_PLAN.md` — test-only failure-injection protocol to prove multi-table operations fully roll back when a later write or success-audit write fails.
- `STATIC_REVIEW_FINDINGS_V1.md` — static review findings and pre-execution gates for the Phase 1–3 function drafts.

## Fixture design notes

1. The fixture is separate from the game-scoring fixture and workflow.
2. It includes synthetic activity, marketplace, purchase, idempotency, audit and configuration structures.
3. `marketplace_rewards`, `purchases`, `transaction_requests` and `transaction_audit` are proposed test structures, not claims about production schema.
4. No `UNIQUE(activity_id, student_id)` constraint is present.
5. `NULL` reward stock means unlimited stock; finite stock is non-negative.
6. The fixture configuration is seeded with a 50-point maximum_teacher_award. The inspected seed file contains 50-point opening balances and no 100-point award-cap seed. The earlier stale-100-point warning was inaccurate for the current fixture and seed; retain a repository-wide scan for stale award-cap assumptions and distinguish unrelated activity maximum-score values. Do not run the fixture until the function drafts and tests are reconciled.
7. Point transactions use signed values: positive credits and negative debits.
8. Browser test roles have no direct table writes. The gateway test role has no direct table grants; narrow function EXECUTE grants are defined in the separate drafts and still require ACL verification.
9. Role names are namespaced as `temmy_ctest_*` to avoid colliding with standard Supabase roles or other local roles.
10. The fixture refuses to reuse pre-existing namespaced test roles. Run only in a fresh disposable PostgreSQL cluster with a dedicated administrator.
11. The test harness simulates an already-verified teacher identity; it does not test Supabase JWT or production Edge Function authentication.
12. All balance-changing operations must lock the same student row before reading the ledger balance.

## Current review status

The V2 foundation and Phase 1–3 drafts now cover teacher awards, deductions, full award reversal, activity score adjustment and one-student marketplace purchase. The original Phase 1–3 files are superseded historical drafts. The deterministic synthetic seed, successful-path smoke test, edge-case checks, catalog ACL assertions, runtime direct-DML denial probes, idempotency/reversal regression cases, concurrency protocol and atomicity/failure-injection protocol are drafted.

**None of the SQL has been executed or syntax/runtime tested.** The ACL, concurrency and atomicity protocols have not been run. The failure-injection triggers described in the atomicity plan have not been created. A static review has produced V2 drafts implementing durable expected rejections, zero-balance no-op auditing and class-before-student locking. These changes remain unverified until PostgreSQL 16 syntax/runtime, role-context, ACL, concurrency and atomicity tests pass; see TRANSACTION_RECONCILIATION_GATE_2026-11-23.md. No production or hosted database changes have been made.

## Next gates

Before any SQL is executed in a disposable test database:

- Positively identify a fresh disposable database/cluster; do not use the existing local classroom database without separate explicit approval.
- Review the fixture, seed, V2 smoke-test, edge-case, idempotency/reversal and runtime-denial test assumptions, including zero-balance setup and durable rejection assertions.
- Pin PostgreSQL version and confirm SHA-256 helper availability.
- Verify SECURITY DEFINER role-context behaviour, function owner, fixed `search_path` and function ACLs.
- Verify the V2 stable result/error codes and durable rejected-request semantics against the caller contract.
- Statically review all V2 transaction drafts against TEMMY_CLASSROOM_GLOBAL_LOCK_ORDERING_RULE.md and review lock order/concurrency behaviour.
- Scan the repository for stale manual-award cap assumptions; preserve unrelated activity maximum-score values and reconcile any true conflicts with the approved 50-point default.
- Complete administrator-only award-cap configuration coverage, including same-key replay after a cap change and new-key re-evaluation.
- Review and validate the test-only failure injector so each failpoint occurs after the intended preceding mutation.
- Only after static review should the suite be run against synthetic data in a fresh disposable local/CI PostgreSQL database.

The production Gateway authentication trust chain is now documented as an approved design target. Its implementation, production schema reconciliation, and any hosted changes remain separate gates requiring explicit review and approval.
