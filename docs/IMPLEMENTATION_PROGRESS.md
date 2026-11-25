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
