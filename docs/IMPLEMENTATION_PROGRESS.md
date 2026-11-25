# Temmy Smart Classroom — Progressive Implementation Record

**Status:** Approved requirements recorded; implementation in progress  
**Working repository:** `oyeleketemitope787-sys/temmy-smart-classroom`  
**Working branch:** `cloud-test`  
**Production branch:** `main` — protected from changes during this work  
**Scope:** Temmy Smart Classroom only

## 1. Working agreement

The design-question phase is paused. Implement the decisions already approved, record progress here, and avoid reopening settled requirements. Ask the user only when an actual implementation blocker or consequential product choice cannot be resolved from the approved decisions and existing system.

Preserve working features and existing data. Inspect the current schema and code before changing them. Do not deploy to production without explicit approval.

## 2. Approved functional requirements

### 2.1 Activities and assessment

Implement the approved activity workflow within Temmy Smart Classroom:
- Activity creation and management, assignment and class/student eligibility.
- Six question formats: multiple choice, fill in the gaps, true/false, matching, short answer, and extended response/show your working.
- Question bank, reusable templates, question-level marks, topics/objectives, mathematical notation and media.
- One attempt per activity; teacher-authorised exceptional reopening only, with an audit record.
- Per-student server-controlled countdown timer; timer expiry preserves answers and locks editing.
- Autosave with server confirmation, safe offline recovery and stale-write protection.
- Student interface with Previous/Next and question navigator; review before submission.
- Submission confirmation, immutable submitted attempt, and status tracking.
- Teacher live monitoring shows progress/timer/status but not active answers.
- Hybrid marking, partial credit, optional negative marking (off by default), teacher feedback, controlled result publication and correction history.
- Reports and analytics based on valid graded records.
- Accessibility and differentiated versions as previously approved.

### 2.2 Aggregate and Spendable Points

These are two distinct balances and must never be conflated.

- **Aggregate Points** are the student's lifetime/period achievement measure used for reward levels, ranking and leadership. Marketplace purchases and ordinary spendable deductions never reduce Aggregate Points.
- **Spendable Points** are the available balance for marketplace purchases. Purchases and ordinary spendable deductions reduce Spendable Points only.
- A valid points award increases both Aggregate Points and Spendable Points.
- All balance-changing operations must be recorded in a trusted, auditable transaction ledger and executed server-side/atomically. Prevent duplicate awards, cross-student balance changes, negative spendable balances, and client-side balance manipulation.
- Achievement thresholds: Bronze 50+, Silver 100+, Gold 150+, Champion 500+.
- Class Champion ranking is based on Aggregate Points and is separate from the Champion achievement threshold; the highest Aggregate total in a class may be Class Champion even below 500.
- Aggregate and Spendable balances must be shown distinctly wherever students or teachers see points. Marketplace prices and purchase eligibility use Spendable Points only.

### 2.3 Student leadership

- Leadership roles: Captain, Disciplinary Prefect, Sanitary Prefect 1, Sanitary Prefect 2.
- Appointment milestones are ordered by server timestamps; deterministic ordering resolves simultaneous awards.
- A student may hold only one leadership position in an academic period.
- Rotation and appointment history must be preserved.
- Role titles and appointments are teacher-editable within authorised permissions.
- Formal corrections to points do not silently remove a previously earned leadership appointment.
- Fresh appointments are made for each academic period.
- A student transferring into a receiving class starts with zero Aggregate Points for that receiving class/period; historical records remain preserved.
- Class Champion ranking is separate from leadership appointments. Ties are resolved through the teacher's live task/decision process.
- Leadership settings, appointments, changes and reasons must be auditable.

## 3. Existing-system inspection baseline (2026-11-25)

The `cloud-test` branch currently contains a single-page `index.html` build labelled V8.9.2.

Initial code inspection found:
- The browser-side model still represents student points as a single `points` value.
- The student leaderboard and class summary use that single value.
- The visible reward-level UI currently shows Champion at 200+, which conflicts with the approved 500+ threshold.
- Marketplace UI describes purchases as spending points; it must be moved to Spendable Points.
- Teacher award actions insert rows into `point_transactions` and then update the local single balance. The ledger currently needs server-side rules/RPCs to guarantee both balances and atomicity.
- Activity records and activity-management code already exist, including `class_activities` and `student_activity_records`; the full workflow and schema must be inspected before extending it.
- Current branch tip at inspection: `004e4a34b20141889ebe46c91b8a700300d516b0`.
- Repository tree on this branch currently exposes `index.html` and `CNAME`; no migration directory was present in the branch tree at inspection.

These are inspection findings, not completed fixes. No production database or production branch changes have been made as part of this record.

## 4. Implementation sequence and progress

| Workstream | Planned work | Status |
|---|---|---|
| A. Baseline and record | Record approved requirements; inspect branch and current code/schema | In progress |
| B. Points foundation | Define Aggregate/Spendable ledger, summaries, trusted atomic award/deduction/purchase operations, migration and tests | In progress — schema and legacy purchase accounting inspection required before migration |
| C. Achievements and leadership | Thresholds, milestone ordering, class-period records, leadership appointments/history and teacher controls | In progress — Champion threshold corrected in UI to 500; leadership implementation pending schema inspection |
| D. Activity foundation | Activity/question schema and versioning; six formats; assignments and eligibility | Not started |
| E. Student assessment | Individual timers, autosave, offline recovery, navigation, submission and expiry | Not started |
| F. Teacher assessment | Live monitoring, grading, feedback, publication, interventions and audit | Not started |
| G. Portals and reporting | Separate balance displays, student/teacher dashboards, reports and exports | Not started |
| H. Verification | Functional, security, regression and realistic teacher/student testing | Not started |
| I. Release | Controlled deployment only after explicit user approval | Not started |

## 5. Safety and implementation rules

1. Work only on `cloud-test`; do not commit to or modify `main`.
2. Do not run unverified SQL against the live Supabase project.
3. Use a reviewed migration and isolated test fixtures before any live schema/data changes.
4. Keep Aggregate Points, Spendable Points, academic marks and behaviour/reward records semantically separate.
5. Preserve existing records and legacy compatibility; do not silently reset balances.
6. Make trusted server operations idempotent where retries are possible and protect against duplicate transactions.
7. Test one student independently from every other student; no bulk operation may leak balance changes across students.
8. Update this file after each meaningful implementation step with files changed, migration/function names, tests run, outcomes, commit SHA and unresolved blockers.
9. A commit to the development branch is not a production deployment.

## 6. Next concrete step

Inspect the complete existing Supabase schema and the relevant current activity/points RPCs and policies. Then prepare the first reviewed migration for the two-balance ledger and server-side atomic operations, with isolated test cases. Do not alter live data until the migration and tests are reviewed.


## 7. Progress update — 2026-11-25 (implementation pass 1)

- Updated `index.html` on `cloud-test` so the Champion achievement threshold is 500 Aggregate Points throughout the existing class summary, student leaderboard, reward-level helper, reports, student progress panel and student portal.
- Verified that the old 200-point Champion threshold no longer appears in the checked UI patterns.
- Commit: `e254e21b0edf313c0bf202febbd557372994e352`.
- No database migration or live data change has been applied.
- The separate Aggregate/Spendable ledger cannot safely be migrated from repository code alone: the hosted schema and existing marketplace purchase deduction function need read-only inspection first. Known existing objects include `students`, `point_transactions`, `purchases`, `marketplace_rewards`; `point_transactions` currently records a single signed `points` value. Existing historical purchases must not be double-counted or silently converted.
- Added read-only schema inspection script: `supabase/preflight_points_and_leadership.sql` (commit `8792bd611dc8b15138041aefd7e68551a7786ded`). It retrieves table columns, constraints, RLS policies, triggers and function bodies for points, marketplace, activity and leadership objects. It makes no changes.
- Next: run that preflight in the Supabase SQL Editor and use its results to write a reviewed, additive migration and server-side atomic RPCs. Keep `main` untouched.


## 8. Database preflight completed — 2026-11-25

The six original read-only preflight sections have now been run against the hosted Supabase project.

Confirmed findings:
- All inspected core tables have RLS enabled. Existing policies are teacher-oriented and scoped through each teacher's classes; there are no student-specific table policies in the inspected results. Student access currently relies on access-code SECURITY DEFINER functions and must be preserved/secured deliberately.
- No user-defined triggers were returned for the inspected points, purchase, student, or activity tables.
- Existing point history is stored in `point_transactions` as a single signed integer `points` amount. The existing marketplace purchase function calculates a balance from that legacy ledger, inserts a negative `marketplace_purchase` transaction and creates a purchase record.
- The existing purchase function is `public.purchase_marketplace_reward(uuid, uuid, uuid[])`, is SECURITY DEFINER, locks the request, reward and student rows, validates all selected students before processing, and stores a request result for retry idempotency. Preserve these protections when updating purchase accounting.
- The existing `submit_student_activity(text, uuid, text)` function rejects a previously submitted activity, but the inspected table has no unique constraint on `(activity_id, student_id)`; concurrent duplicate protection needs a database-level safeguard in the activity workstream.
- The proposed `student_point_accounts` and `student_leadership_appointments` tables do not currently exist.
- The original section-6 signature check used `to_regprocedure('public.purchase_marketplace_reward')` without argument types, so its NULL result did not establish absence. Section 5 supplied the exact existing signature.

A supplemental read-only script, `supabase/preflight_points_backfill.sql`, was added to inspect the legacy purchase-request table and constraints, classify existing point transactions by action/source, compare purchase totals with marketplace deductions, and verify the exact purchase function signature. This is required before selecting a safe, non-destructive opening-balance backfill rule.

No migration has been applied to Supabase and no production data has been changed.

- Supplemental preflight script commit: 44aa30a6801630973562a0c078b6a9651665e711
- Next: run the supplemental read-only script; use its results to finalize the additive points-account/ledger migration and preserve the existing purchase idempotency workflow.


## 9. Legacy points classification — 2026-11-25

The hosted ledger aggregation returned:
- `activity_score / game`: 5 positive transactions, +78 net.
- `activity_score / teacher`: 11 transactions (7 positive, 4 negative), +9 net.
- `marketplace_purchase / teacher`: 6 negative transactions, -210 net.
- `negative / teacher`: 37 negative transactions, -105 net.
- `positive / teacher`: 158 positive transactions, +671 net.
- `undo / teacher`: 25 transactions (9 positive, 16 negative), -74 net.

Totals across the entire database:
- Aggregate opening total under the approved rule (all legacy transactions except `marketplace_purchase`): +579.
- Spendable opening total (all signed legacy transactions including marketplace purchases): +369.

These are global totals only, not per-student balances. The migration must calculate each student's opening balances independently from that student's transaction rows. Historical marketplace deductions are excluded from Aggregate Points but remain deducted from Spendable Points. Existing non-marketplace positive, negative, activity and undo transactions contribute according to their signed amount, preserving the recorded history rather than guessing transaction intent.

The purchase function's exact signature is confirmed as `public.purchase_marketplace_reward(uuid, uuid, uuid[])`. Its request idempotency key is protected by primary key `(teacher_id, request_id)`.

Added a focused read-only reconciliation script, `supabase/preflight_points_reconciliation.sql`, to retrieve the request-table columns, per-student proposed opening balances, purchase-versus-deduction reconciliation by student, and exact purchase-function signature. It does not modify schema or data.

No points migration has been applied. Before choosing whether to backfill directly, verify the per-student reconciliation and ensure the proposed Spendable opening balance does not become negative; do not silently clamp or rewrite a legacy balance.

- Reconciliation script commit: 22b87ab52a63bfbf46030e086ed4232d821d053d
- Next: inspect the per-student results and purchase reconciliation; then implement the additive account ledger and update the existing purchase RPC without removing its idempotency/locking protections.


## 10. Per-student purchase reconciliation and account foundation — 2026-11-25

The focused read-only reconciliation returned eight students. Proposed opening balances are all non-negative:
- Student `04e6d02b…`: Aggregate 315; Spendable 315; 143 legacy transactions.
- Student `0cf1c3fc…`: Aggregate 210; Spendable 0; 74 legacy transactions.
- Three students have zero balances and no legacy transactions.
- Remaining students: Aggregate/Spendable 22/22 (9 transactions), 20/20 (12), and 12/12 (4).

The purchase-versus-deduction comparison returned one student with historical purchases: 6 purchase rows / 210 points and 6 marketplace deduction rows / 210 points; difference = 0. This reconciles the recorded historical marketplace spending for that student. The per-student account backfill rule is therefore supported by the inspected legacy data supplied so far.

Added the first additive migration file:
- `supabase/migrations/20261125000100_create_student_point_accounts.sql`
- Creates one account summary row per student with separate Aggregate and Spendable balances.
- Backfills each student's balances from their own legacy `point_transactions` rows; marketplace deductions are excluded from Aggregate and included in Spendable.
- Uses `ON CONFLICT DO NOTHING` so rerunning the backfill cannot overwrite a subsequently initialized account.
- Enables RLS and revokes direct browser-role access; future approved SECURITY DEFINER functions will provide the controlled application interface.
- Includes a transaction guard that aborts if any opening Spendable balance is negative.

Migration commit on `cloud-test`: `9455c490ccf8b717098d3ba5e34f3b602266b48b`.

**Important:** this is a repository migration file only. It has NOT been run against Supabase. Do not apply it to the hosted database yet. Next work is to inspect exact existing points RPC definitions and client call paths, then add atomic/idempotent award and purchase integration plus isolated tests before asking for migration review.


## 11. Atomic teacher transaction RPC prepared — 2026-11-25

Added `supabase/migrations/20261125000200_add_atomic_point_transaction_rpc.sql` on `cloud-test`.

The migration adds:
- `student_point_operation_requests`, keyed by `(teacher_id, request_id)`, to preserve request payloads/results and make retries idempotent.
- `record_student_point_transactions(uuid, uuid, jsonb)`, a SECURITY DEFINER RPC for non-marketplace teacher point transactions.
- Authenticated teacher check, active-class ownership validation, active-student/class validation, deterministic student/account row locking, duplicate-student rejection, request-payload reuse protection, negative Spendable guard, ledger inserts and atomic Aggregate/Spendable updates.
- RLS enabled and direct browser-role access revoked on the idempotency table; function execution granted only to authenticated users.

The RPC deliberately excludes `marketplace_purchase`; the existing purchase RPC must be updated separately while preserving its currently confirmed request-locking/idempotency behaviour. The browser UI still uses direct ledger inserts in award, undo and activity-score paths; those call sites must be switched to the new RPC before this migration is applied in any shared environment.

Commit: `567e7b9bf7576a9b036da781ef76fa4464a4b136`.

Validation status: reviewed statically against the inspected table/function architecture, but not executed against PostgreSQL/Supabase. It has not been applied to the hosted database. The exact hosted purchase function body and a complete test environment are still required before replacing purchase accounting and declaring the points workflow ready.



## 12. Teacher point-entry paths connected to atomic RPC — 2026-11-25

Updated `index.html` on `cloud-test`:
- Standard teacher awards now call `record_student_point_transactions` with a fresh request UUID, class ID and validated transaction entries instead of inserting directly into `point_transactions`.
- Undo now uses the same RPC and records the reversal as an `undo` transaction.
- Activity scoring now uses the same RPC for the score difference, preserving the existing activity-record rollback when the RPC reports an error.
- All three paths require a positive server confirmation before showing success or updating the local history.
- A source scan after the change found no remaining direct browser-side `INSERT` calls to `point_transactions`. The remaining ledger access in the file is read-only history/balance loading. Punctuality continues to use its existing dedicated `record_student_punctuality` RPC and was not changed.

Commit: `e0d2c03d2c4a83860ad5714c5646fc761f5a0f5f`.

Validation status:
- Verified the three intended call sites now invoke the atomic RPC and the old direct-insert calls are absent.
- This is a static source review only. No browser integration test or PostgreSQL execution has been performed because the migration is not applied to Supabase.
- The current class loader still calculates a single legacy balance from the transaction ledger; Aggregate/Spendable display separation is not yet complete.
- The existing marketplace purchase RPC remains unchanged and still calculates spendable funds from the legacy ledger. It must be replaced only after retrieving its exact hosted definition, preserving its locks and request idempotency.
- Activity score record updates and point RPC calls remain two sequential requests; a later hardening step should make score finalisation and its point delta one database transaction to remove any ambiguous network-failure window.

Next: implement a controlled server-side account-summary read for teacher/student views, then migrate the UI to display Aggregate and Spendable separately. In parallel, retrieve the full current `purchase_marketplace_reward(uuid,uuid,uuid[])` definition before preparing its replacement. Do not run either migration in Supabase yet.


## 13. Controlled teacher balance-summary RPC prepared — 2026-11-25

Added `supabase/migrations/20261125000300_add_teacher_point_account_summary_rpc.sql` on `cloud-test`.

The new `get_teacher_student_point_accounts()` RPC:
- Returns class ID, student ID, Aggregate Points and Spendable Points as separate values.
- Is SECURITY DEFINER with an empty search path.
- Returns only active students in active classes owned by the authenticated teacher.
- Uses zero defaults for a student account row not yet created; the atomic write RPC will initialise that account on the first point transaction.
- Revokes execution from PUBLIC and anon and grants it to authenticated users only.
- Does not grant direct browser access to `student_point_accounts`.

Commit: `9e13b824f96f8d09df678eb4575037bb0f2be0da`.

Validation: static SQL review only. The migration has not been executed in PostgreSQL/Supabase. The teacher UI has not yet been switched to this read RPC. The next UI pass must use Aggregate Points for ranking/reward levels and Spendable Points for marketplace selection and purchase affordance; the purchase RPC remains the final authority for affordability.


## 14. Teacher class loader and marketplace selector use separate balances — 2026-11-25

Updated `index.html` on `cloud-test`:
- Replaced the teacher class loader's legacy single-ledger sum with `get_teacher_student_point_accounts()`.
- Each cloud student now carries `aggregatePoints` and `spendablePoints` separately. The legacy `points` compatibility property is temporarily mapped to Aggregate Points so existing achievement/ranking/award screens continue to use the approved achievement measure while the remaining displays are migrated.
- Marketplace student selection now shows Spendable Points, while its displayed rank remains based on Aggregate Points.
- The purchase modal explicitly states that affordability is based on Spendable Points and that Supabase remains authoritative for all-or-nothing purchase validation.
- Static source scan confirmed the old class-loader aggregation from `point_transactions` and the old marketplace selector display of the single `points` value are gone.

Commit: `cb397c538f26108952638af60f2387e5ee385d83`.

Validation: static source review only. The summary RPC migration is not applied, so the new class loader cannot yet be exercised against the hosted database. Other student/teacher surfaces still need explicit Aggregate/Spendable labels and balances. The marketplace purchase RPC still needs to be updated to deduct Spendable only while preserving its existing request idempotency and locking. No Supabase changes have been made.


## 15. Marketplace purchase RPC updated for Spendable Points — 2026-11-25

The complete hosted definition of `public.purchase_marketplace_reward(uuid, uuid, uuid[])` was supplied and used as the source for the replacement. Added:

- `supabase/migrations/20261125000400_update_marketplace_purchase_spendable_account.sql`
- Preserves the existing authenticated-teacher check, request claim/row lock, request-detail reuse protection, completed-result replay, reward ownership/active check and reward lock, selected-student validation/locks, all-students-before-any-purchase validation, purchase records and result payload.
- Changes affordability checks to read `student_point_accounts.spendable_points`, not a sum of the legacy transaction ledger.
- Ensures any missing selected-student account is initialized from that student's own legacy transactions, with marketplace deductions excluded from Aggregate and included in Spendable.
- Locks account rows in deterministic student order.
- Inserts the same auditable negative marketplace transaction and purchase row, then decreases Spendable Points only. Aggregate Points are not modified.
- The account check constraint and row lock protect against a negative Spendable balance; all purchase inserts, account deductions and idempotency result storage remain in the same database transaction.

Migration commit on `cloud-test`: `9abe5f6f9006cf758c5256544dc69d59fe5fb7bc`.

Validation status: source-level review against the exact hosted function supplied by the user. It has not been executed in PostgreSQL, tested under concurrent requests, or applied to Supabase. The four points migrations remain repository files only. Before application, run the migrations in order in an isolated test database and verify: (1) a purchase lowers Spendable only; (2) Aggregate is unchanged; (3) insufficient funds for any selected student leaves every student's balances and purchase rows unchanged; (4) same request retry returns the stored result without a second deduction; (5) same request ID with different details is rejected; and (6) concurrent purchase/award operations cannot overspend.

Next: continue migrating remaining student and teacher balance displays to explicit Aggregate/Spendable labels, then prepare an isolated database verification checklist. Do not run these migrations against the hosted project until the complete migration set is reviewed and explicit approval is given.


## 16. Teacher-facing balance labels — 2026-11-25

Updated `index.html` on `cloud-test`:
- The main class leaderboard now labels its two balance columns as Aggregate Points and Spendable Points.
- Class summary now shows total Aggregate Points and total Spendable Points separately; average remains an Aggregate Points measure.
- Individual student history/profile now shows both balances separately, and reward progress is explicitly calculated from Aggregate Points.
- Teacher class cards now show both class totals.
- Existing rank and reward-level logic continues to use the compatibility `points` property, which the cloud class loader maps to Aggregate Points.

Commit: `e74aa58c24ca148c456d7a37af2871aa768af78d`.

Validation: reviewed the changed source sections and confirmed the old duplicate table/class-card markup was removed. No browser test has been run. The report renderer and student portal still need separate-balance labels/data. The student portal must receive its balances through a secure access-code RPC; it must not be given direct table access or infer Spendable Points from the visible transaction-history rows.

No Supabase migration has been applied.


## 17. Reports balance separation — 2026-11-25

Updated the teacher reports renderer in `index.html`:
- Shows total Aggregate Points and total Spendable Points separately.
- Average, ranking, top-student selection, and reward-level counts explicitly use Aggregate Points.
- Student report table displays both balances and the reward level derived from Aggregate Points.

Commit: `fbec646019b79e562149f90dbdcccc121fb44214`.

Source review completed; browser verification remains outstanding. The student portal balance display is not yet changed because it requires a secure access-code RPC that returns the account balances. The existing access-code verification function's exact definition must be inspected before designing that RPC. No Supabase migration has been applied.


## 18. Secure student point balances — 2026-11-25

The exact hosted definitions of both access-code functions were supplied and reviewed:
- `verify_student_access_code(text)` verifies the supplied code against the active access-code hash and returns the active student identity.
- `get_student_point_history(text)` uses that verifier to scope history to the verified student.

Added `supabase/migrations/20261125000500_add_student_point_account_summary_rpc.sql`:
- Adds `get_student_point_account_summary(text)`, a read-only SECURITY DEFINER RPC with an empty search path.
- Uses the existing `verify_student_access_code(text)` function and returns only Aggregate Points and Spendable Points for the verified active student.
- Returns zero balances if the student's account row has not yet been initialised.
- Revokes default/public execution and grants only the `anon` and `authenticated` roles needed by the access-code student portal. It does not grant direct access to `student_point_accounts`.

Updated the student portal in `index.html`:
- Loads the two balances through the new access-code RPC.
- Displays Aggregate Points and Spendable Points separately.
- Uses Aggregate Points for the student's reward level and reward progress.
- Keeps today's net transaction change separate from the two current balances.
- Shows an explicit error if the balance RPC cannot be loaded; it does not derive Spendable Points from the visible transaction history.
- Clears balance and history state on student logout.

Commits on `cloud-test`:
- Student portal UI: `55ce6d41d44332cec32bcf10229d4c6f2082dbd6`
- Student balance RPC migration: `23d787675ea89d4f6e7fa186b7aef5ab99f64ba2`

Validation status: source-level review only. The new migration has not been run against Supabase, and the portal change has not been browser-tested against the hosted database. All five points migrations remain repository files only; none has been applied. Next: review the complete migration set and perform isolated PostgreSQL tests before requesting approval to apply anything to the hosted project.


## 19. Five-migration static review and isolated test plan — 2026-11-25

Reviewed all five points migrations together and made two consistency corrections on `cloud-test`:

- In `20261125000200_add_atomic_point_transaction_rpc.sql`, student eligibility now requires `students.active IS TRUE`, matching the marketplace RPC, teacher balance summary and access-code verification. Previously, the award RPC treated a NULL active flag as active.
- In `20261125000400_update_marketplace_purchase_spendable_account.sql`, lazy account initialization now aggregates the student's complete legacy ledger, without filtering by the current teacher. This matches the global per-student account backfill and avoids silently omitting historical transactions if a student changes teacher/class.

Added `docs/POINTS_MIGRATION_TEST_PLAN.md` with:
- Required schema/role preconditions.
- Per-student backfill reconciliation queries.
- Functional tests for awards, deductions, undo, marketplace purchases, retries and mismatched request IDs.
- Teacher/student access and privilege checks.
- Multi-student rollback and concurrent spending tests.
- Post-test account-to-ledger reconciliation.

Commits on `cloud-test`:
- Active-student validation correction: `9fcc8d223065b418d83a266881634abe88a7027a`
- Complete-ledger lazy initialization correction: `e202aef27da33cbea89b14bc3ddaf9bb1c39cd53`
- Isolated verification plan: `64cb33e08139654d00d6e238b0a22a4c340fa8c2`

Review findings still requiring execution-based verification:
- The five SQL migrations have only been statically reviewed; no PostgreSQL/Supabase test database has been run.
- Confirm the test snapshot's exact foreign-key identity relationship between `teacher_profiles.id`, `auth.uid()` and `classes.teacher_id`.
- Exercise RPC grants and direct-table denials under real `anon` and `authenticated` roles.
- Exercise multi-session concurrent award/purchase calls; deterministic locking and SQL inspection alone do not prove race-safety.
- The activity score update and point-account RPC are separate browser requests and are not yet a single atomic transaction.

No migration has been applied to the hosted Supabase project. Production `main` remains untouched.


## 20. Five points migrations applied to isolated Supabase test project — 2026-11-25

The user confirmed the separate Supabase project `temmy-smart-classroom-test` is healthy and used its SQL Editor for the five points migrations. The project dashboard's branch selector displays `main` with a `PRODUCTION` label, but the Supabase project itself is the separately named test project; the live production project was not selected or modified.

Before migration execution, read-only checks confirmed the test project contains the expected baseline dataset:
- 8 students, 1 class, 2 teacher profiles.
- 242 point transactions, 6 purchases, 2 marketplace rewards, 3 class activities, 2 student activity records and 4 marketplace purchase requests.
- Per-student Aggregate/Spendable opening balances exactly matched the prior reconciliation; all Spendable balances were non-negative.
- The only student with purchases had 6 purchase rows / 210 points and 6 marketplace deduction transactions / 210 points; difference = 0.

The user then ran all five migrations successfully in `temmy-smart-classroom-test` (Supabase returned “Success. No rows returned” for each):
1. `20261125000100_create_student_point_accounts.sql` — account table and historical backfill. Post-migration query returned all 8 expected student balances, matching the pre-migration ledger calculation.
2. `20261125000200_add_atomic_point_transaction_rpc.sql` — atomic teacher point transaction RPC and idempotency table. A follow-up catalog check confirmed SECURITY DEFINER, empty search path, authenticated EXECUTE and no anon EXECUTE.
3. `20261125000300_add_teacher_point_account_summary_rpc.sql` — teacher summary RPC. Catalog/function-definition check confirmed SECURITY DEFINER, STABLE, empty search path, authenticated EXECUTE, no anon EXECUTE, and active teacher-owned class/student filtering.
4. `20261125000400_update_marketplace_purchase_spendable_account.sql` — marketplace RPC update. Catalog/function-definition check confirmed SECURITY DEFINER, empty search path, authenticated EXECUTE and no anon EXECUTE; inspected definition deducts Spendable only.
5. `20261125000500_add_student_point_account_summary_rpc.sql` — access-code student balance RPC. Catalog check confirmed SECURITY DEFINER, STABLE, empty search path, and EXECUTE for anon/authenticated as intentionally required by the student portal.

A small hardening edit was also made on `cloud-test` to the atomic RPC migration: JSON input array type and empty-array validation are now separate IF checks. This avoids relying on SQL boolean evaluation order when handling malformed JSON. The revised migration was used for the test-project application. Commit: `ccdf251` (verify exact full SHA from repository history if needed).

**Current verification boundary:** migration application, opening-balance reconciliation and function catalog/definition checks have passed. Actual behavioural tests have NOT yet been run. Still required: real access-code ownership test; direct table privilege denial; teacher-scope RPC test under authenticated identity; award/negative/undo and idempotency tests; purchase Spendable-only, insufficient-funds rollback and retry tests; account-to-ledger reconciliation after test transactions; ideally concurrent award/purchase tests using separate sessions. Browser integration of teacher/student UI against this test project is also outstanding.

No migration has been applied to the separate live production Supabase project. Do not deploy or alter production without explicit approval. The repository working branch remains `cloud-test`; production Git branch `main` remains untouched.



## 21. Punctuality point-account integration prepared — 2026-11-25

Inspected the exact hosted definition of `record_student_punctuality(uuid, uuid[], text, integer, date)`. The legacy function wrote directly to `point_transactions` and did not update `student_point_accounts`, which would leave Aggregate/Spendable balances stale after punctuality awards or adjustments.

The punctuality table has a primary key and a unique index on `(student_id, class_id, punctuality_date)`.

Added `supabase/migrations/20261125000600_route_punctuality_through_point_accounts.sql` on `cloud-test`:
- Replaces the punctuality function while preserving its return columns and recorded/updated/unchanged actions.
- Requires an active teacher-owned class and active students; rejects empty or duplicate student lists and invalid inputs.
- Locks the class row to serialize punctuality updates and avoid the absent-record insert race; locks each target student and existing punctuality row.
- Builds only the non-zero award/adjustment deltas and sends them through `record_student_point_transactions(uuid, uuid, jsonb)`.
- Because the nested RPC call is in the same PostgreSQL transaction, a rejected points change (including a negative Spendable result) rolls back the punctuality record changes too.
- Uses a fresh server-generated request UUID for the atomic points operation.

Migration commit: `971b77dc96b05ef1a91f187fcb458a3996042440`.

Validation status: static review only; this new migration has NOT been run in Supabase or tested with concurrent sessions. The six-migration set now needs a complete review and isolated behavioural tests. Do not apply this migration to any production project. The earlier five migrations are already applied only to the separately named `temmy-smart-classroom-test` project. GitHub `main` remains untouched.


### Follow-up static-review hardening for migration 006

A cross-RPC lock-order review found that the first draft locked punctuality students in caller-supplied array order, while marketplace and points operations lock students by ID. Updated migration 006 to lock and validate the complete student set in deterministic ID order before processing the punctuality rows. This reduces deadlock risk when punctuality overlaps marketplace or other points operations.

Updated migration commit: `afb9927ca375a4bee0c1c1456c0158ec22f27851`.

This remains static review only. Migration 006 is not applied; PostgreSQL execution and concurrent-session tests are still required.


### Punctuality RPC installed and rollback trial passed — 2026-11-25

In the isolated `temmy-smart-classroom-test` project, migration 006 was applied successfully. Read-only inspection confirmed the installed `record_student_punctuality` signature, `SECURITY DEFINER`, empty `search_path`, and nested call to `record_student_point_transactions`.

A transaction-wrapped trial for Code Final (initial Aggregate 22, Spendable 22) recorded an On Time award of +1. Inside the transaction both balances read 23. The transaction was explicitly rolled back. A subsequent independent query confirmed Aggregate 22, Spendable 22, zero punctuality records for 2026-11-25, and zero punctuality ledger entries for that date. This verifies the basic award path and rollback behaviour in the isolated project.

Next: test punctuality adjustment and unchanged paths within a transaction that is rolled back, then proceed to the other atomic point-operation and marketplace behavioural tests. No production database or GitHub `main` changes.


### Punctuality adjustment / unchanged trial passed — 2026-11-25

A transaction-wrapped trial for Code Final recorded On Time with +2 points, changed the same date's status to Late with 1 point (a -1 adjustment), and repeated the identical Late/1 submission. Temporary inspection showed Aggregate 23, Spendable 23, and exactly two punctuality transactions, consistent with the unchanged repeat creating no extra transaction. After rollback, an independent query confirmed Aggregate 22, Spendable 22, zero punctuality records, and zero punctuality transactions for the date.

### Generic atomic points RPC idempotency trial passed — 2026-11-25

Submitted the same `record_student_point_transactions` request twice using the same request UUID and identical payload, inside an explicitly rolled-back transaction. Temporary inspection showed Aggregate 23, Spendable 23, and exactly one matching ledger transaction, confirming an identical retry does not award twice. A subsequent independent query confirmed Aggregate 22, Spendable 22, and zero matching test transactions, verifying rollback.

Next: test that reusing the same request UUID with a different payload is rejected without changing balances or ledger entries. All tests remain isolated to `temmy-smart-classroom-test`; production remains untouched.


### Generic atomic points RPC rejects changed-payload request-ID reuse — 2026-11-25

In the isolated `temmy-smart-classroom-test` project, a transaction-wrapped test submitted a +1 request and then reused the same request UUID with a changed +2 payload. The PL/pgSQL test was written to re-raise a deliberate test-failure exception if the changed payload were accepted; the SQL script proceeded to its temporary balance query, indicating the changed-payload call was rejected as expected. Temporary balances were 23/23. After explicit rollback, an independent query confirmed Aggregate 22, Spendable 22, and zero matching test transactions. This verifies rejection of changed payload reuse and rollback.

The generic points RPC behavioural tests now cover identical-request idempotency, changed-payload rejection, and rollback. Next: proceed to marketplace purchase behaviour tests in the isolated project. No production database or GitHub `main` changes.
