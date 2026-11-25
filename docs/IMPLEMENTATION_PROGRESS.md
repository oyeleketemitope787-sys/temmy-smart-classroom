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
