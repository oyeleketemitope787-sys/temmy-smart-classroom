# Classroom Transaction Test Specification v1.0

**Status:** Approved business rules; review-only test specification (marketplace policy clarified 2026-11-21)  
**Branch:** `security-review/student-login-hardening`  
**Scope:** Trusted teacher point transactions, activity scoring, marketplace purchases, idempotency, authorization, auditability, and concurrency.  
**Environment:** Disposable PostgreSQL CI/local database only. No hosted Supabase connection.  
**Explicit exclusions:** This is not a migration, deployment plan, or authorization to change Supabase. Do not modify `main` or `cloud-test`.

## 1. Purpose

Specify the business behaviour and acceptance tests for moving sensitive Classroom ledger operations out of browser-controlled writes and into a narrow trusted transaction layer. The ledger remains the source of truth for point balances. The browser may request an operation but may not directly create point transactions or alter protected scoring fields.

The existing game platform is retired from this plan. Classroom security and launch readiness are the priority. Temmy Gateway is a future integration boundary; this specification does not authorize implementing or deploying it.

## 2. Approved business rules

### 2.1 Teacher awards

- Only an authenticated teacher who owns the student's active class may award or deduct points.
- Awards are positive whole numbers.
- The default maximum for one individual manual teacher award is **50 points**. An authorised school administrator or authorised system administrator controls the configured limit; teachers may award up to the current limit but cannot change it.
- A manual award above the configured limit is rejected with a clear explanation and no ledger write. The system must never silently truncate the requested amount.
- An exceptional award above the normal limit requires a separately authorised, auditable override process. Its authority, scope, and approval workflow must be specified before implementation.
- This cap applies only to individual manual teacher awards, not activity scores or other separately approved earning sources.
- The server derives the acting teacher identity from the trusted authenticated request context; it must not trust a teacher ID supplied by the browser.
- Award and deduction requests are idempotent. Replaying the same request ID and same payload returns the recorded outcome; reusing the request ID with a different payload is rejected.

### 2.2 Deductions and balance clamping

- A deduction cannot reduce a student's available balance below zero.
- If the requested deduction exceeds the available balance, deduct only the available balance and record the actual deducted amount.
- If the available balance is zero, return a zero-balance/no-op outcome and create no point transaction.
- Balance calculation is derived from the ledger; no independently editable balance is authoritative.
- Concurrent deductions must serialize safely so that the total actual deduction never exceeds the balance available at the time each operation is applied.

### 2.3 Undo

- Undo means a full reversal of the original eligible transaction, not a partial reversal.
- A transaction may be reversed at most once.
- The reversal must reference the original transaction and be recorded as a compensating ledger entry; do not edit or delete the original ledger row.
- If the student has spent some of the awarded points and the full reversal would take the balance below zero, reject the undo completely. Do not partially reverse and do not create a negative balance.
- Undo must be authorized to the teacher who is permitted to reverse the original action under the final ownership policy.
- Concurrent/repeated undo requests must not create multiple reversals.

### 2.4 Activity scoring

- The activity record stores the teacher-assigned score.
- Point transactions record the change (delta) from the previous score, not the new total score.
- Example: score 6 to 9 produces +3; score 9 to 5 requests -4.
- A downward score change is subject to the approved deduction clamp: record only the points actually deducted if the student's available balance is lower than the requested deduction. The activity record still stores the teacher-assigned score.
- The activity record update and corresponding ledger entry must be atomic: both commit or neither commits.
- A zero delta or zero actual deduction creates no zero-value point transaction.
- Teacher must own the activity's class and the student's class relationship must be valid.
- Duplicate activity submission behaviour is not changed by this specification. Preserve the current verified behaviour until its exact deployed semantics are established. Include duplicate-submission tests; do not add a unique constraint on (activity_id, student_id) in this design.

### 2.5 Marketplace purchases

- **Governing policy: independent per-student outcomes.** A multi-student selection is a batch of independently committed student purchase operations, not one all-or-nothing database transaction. A failure for one student must never roll back another student's successful purchase.
- Each individual student's purchase, points deduction, purchase-history row, finite-stock decrement (when applicable), and that student's completed idempotency outcome must be atomic: all commit together or none of that student's purchase effects commit.
- The batch response must contain one stable, independently identifiable outcome per requested student. Successful students remain successful even when other students are rejected; retries must reproduce each student's original outcome without reprocessing completed purchases.
- A shared reward-stock lock/conditional decrement must prevent overselling across concurrent requests. Stock contention is resolved per student: students who obtain available units may succeed; students who cannot obtain a unit receive an out_of_stock outcome, without affecting already committed purchases.
- The implementation may use one database transaction per student or an equivalent savepoint/isolated subtransaction design, but it must demonstrate the same independent commit/rollback semantics. A single exception that aborts the entire multi-student request is non-compliant.
- A student with insufficient points is rejected without a points deduction, purchase row, or stock decrement.
- A student may not be charged twice for a retried request. Each per-student purchase uses a stable idempotency key and payload binding.
- Reward must belong to the acting teacher and be active at the time of purchase.
- Before the first successful purchase, the teacher may edit the reward's points price. After the first successful purchase, the points price is permanently locked for that reward, including after deactivation; a different price requires creating a new reward item.
- Failed or rejected purchase attempts do not lock the price. The first successful purchase and the price-lock transition must be atomic with purchase processing so concurrent edits/purchases cannot produce inconsistent prices.
- Other permitted reward details (for example description, image, and stock) may remain editable under their own validation rules; price is the specifically locked field.
- A deactivated reward is unavailable for new purchases, but its purchase history and historical reward description/name remain preserved.
- Stock model: `NULL` means unlimited stock; a non-negative finite value means limited stock. A finite stock decrement and the purchase must occur atomically. If stock is zero, reject without charging points. Concurrent purchases must not oversell.
- For a multi-student selection, return an independent result for each student (e.g. purchased, insufficient_balance, out_of_stock, reward_unavailable, invalid_student, or retry_result). Do not use all-or-nothing batch semantics.

### 2.6 Marketplace, achievement levels, student rewards, avatars, and class leadership

#### Separate point measures
- Maintain two distinct class- and academic-year-scoped measures:
  - **Aggregate points earned:** cumulative qualifying points earned in the relevant class and academic year. This drives achievement levels, class ranking, and leadership eligibility. Marketplace spending does not reduce aggregate points.
  - **Current point balance:** the spendable balance derived from qualifying ledger transactions (earned points less spending and other valid deductions). Purchases are limited by this available balance.
- Aggregate points use an **earned-only** rule: qualifying positive points earned in the class/academic-year period contribute to aggregate achievement. Marketplace spending and ordinary deductions (including disciplinary deductions) reduce current point balance but do not reduce aggregate points earned.
- A successful purchase therefore reduces current point balance only. It does not reduce aggregate points earned, revoke an already-earned achievement level, or retroactively change a leadership appointment.
- A formal reversal/correction of an incorrectly awarded earning reduces both current spendable balance and aggregate points earned. It is a correction of the original earning, not an ordinary deduction.
- If that correction takes the student's aggregate below an achievement threshold, retain the historical achievement record but mark it no longer currently valid for that class/academic period. Do not delete the record.
- If a formal correction reduces the aggregate below the milestone that originally qualified a student for a leadership position, the previously appointed leader retains that leadership position. Do not automatically transfer the post or appoint a successor because of the correction.
- Preserve the appointment as an active leadership appointment and retain its original historical milestone/appointment details. The correction is recorded in the points and achievement history, but it does not remove the leader from the post.
- Ordinary deductions (including disciplinary deductions) reduce current spendable balance only and do not reduce aggregate points earned.
- When a student progresses or transfers from one class to another (for example, Class 5 to Class 6), the student's points earned in the previous class end with that class. The student is enrolled as a new member of the receiving class and starts with zero aggregate points and zero spendable balance there, even if the move occurs during the same academic year and the receiving class has a different teacher.
- Previous-class points, achievements, transactions, and leadership appointments remain attached to the previous class and its teacher's historical records. They must not be transferred, carried forward, or counted in the receiving class.
- On progression to a new academic year, the new period starts with its own aggregate and spendable balance. Previous-period achievements and transactions remain historical and do not roll over.
- Previous-period leadership appointments remain in the historical record and remain viewable as history; they do not carry forward as active appointments into the new class/academic year.
- Leadership positions for each new class/academic year start afresh. Students must qualify again through the new period's milestones.
- Previous-period points, achievements, and leadership history must remain accessible without being counted toward the new period's totals or appointments.

#### Achievement levels and Champion
- Achievement thresholds are Bronze: 50+, Silver: 100+, Gold: 150+, and Champion: 500+ aggregate points.
- Achievement progression is based on aggregate points, never current spendable balance. Once earned in the relevant class/academic year, a level remains earned for that period even after points are spent.
- Separately, the **Class Champion title** identifies the student with the highest aggregate points in the class/academic-year ranking. The highest-ranked student may hold this title even when their aggregate is below 500; the 500+ threshold remains the Champion achievement-level milestone.
- If multiple students are tied for the highest aggregate points, recognise them as Class Champions for that class/academic year.
- The teacher administers a live task to distinguish the final 1st, 2nd, and 3rd positions among the tied students. The live-task result determines the order of these awards; the tie-break is teacher-administered and must be recorded with the class/period result.
- The top three students from that tie-break receive Champion recognition as 1st, 2nd, and 3rd position awards. All three are recognised as Champions; the position labels distinguish their award placements.
- The live-task tie-break ranks the Class Champion awards only. It does not alter aggregate points earned, the 500+ Champion achievement threshold, or milestone-based leadership appointments.

#### Leadership appointments
- Leadership is linked to aggregate points and achievement milestones, not current point balance.
- At each reward-level milestone, the first student to reach that level becomes or retains Classroom Captain.
- The next three qualifying students are appointed in sequence to the prefect positions: Disciplinary Prefect, Sanitary Prefect 1, and Sanitary Prefect 2.
- Milestone ordering is determined by the database's server-recorded achievement timestamp, not a browser clock. If timestamps are identical, use a deterministic database-generated sequence/ordering value as the tie-breaker.
- Teachers can edit the prefect hierarchy/titles for their class. The system automatically records and displays appointments when the applicable milestone/eligibility is reached.
- Leadership appointments are scoped to the relevant class and academic year and retain historical records. Spending points does not remove an appointment.
- A student may hold only one leadership position in a class during an academic year. Reaching additional reward-level milestones does not automatically assign that student another position.
- When a student who already holds a leadership position reaches another milestone, the next qualifying student in the milestone order is considered for the available position. Do not duplicate leadership positions for the same student within that class/academic year.
- A teacher may deliberately change an appointment; any manual change must preserve the appointment history and record who made the change and when.
- The precise handling of ties or simultaneous milestone attainment must be deterministic and specified before implementation; do not use client-side timing as the authority.


#### Student withdrawal, absence, and re-enrolment in the same class

- A student who temporarily leaves or is absent but whose original student record remains associated with the same class/academic period resumes from that same record. Their existing aggregate points, spendable balance, achievements, transactions, and applicable leadership history are preserved; do not create a duplicate student record.
- If the student is deactivated, reactivation must restore the same student record and its preserved class-period history.
- If the student record is soft-deleted but remains within the approved recovery/retention window, restore that same record and its preserved history after verifying identity and class-period eligibility. Do not create a second record while a recoverable original exists.
- A UI action labelled “delete” must not be assumed to mean permanent erasure. The implementation must distinguish deactivation, recoverable soft deletion, and legally authorised permanent deletion.
- If the record and associated history have been permanently erased under the applicable retention/deletion process and cannot lawfully be recovered, a later re-enrolment creates a new student record and starts at zero aggregate points and zero spendable balance for the new enrolment. Do not reconstruct or invent erased scores.
- This same-class continuity rule does not override the separate class-transfer rule: moving to another class/teacher starts a new class membership with zero points in the receiving class; the previous class history remains with the previous class.
- Re-enrolment must verify whether a recoverable original exists before creating a new record, and must preserve auditability of the restore or new-enrolment decision.

#### Gifts, images, and avatars
- Teachers create and manage marketplace rewards/gifts, set their point prices, and may attach a suitable uploaded image or select an available icon.
- Reward-level achievement and marketplace gift redemption are separate concepts: earning a level does not automatically grant or debit a gift. A gift purchase uses the student's current point balance and follows the independent per-student purchase rules in section 2.5.
- Students may select an avatar only from the approved in-platform avatar library through their student portal. Student avatar uploads are not permitted.
- Avatar selection has no effect on points, achievement levels, rankings, or leadership.
- Teacher-uploaded reward images and the student avatar library must use controlled file types, size limits, and safe storage/access rules.

#### Purchase routes
- A student may purchase an available reward for themselves through their own student portal.
- A teacher may initiate a purchase for one selected student or a selected group, but may not bypass the selected student's current point balance.
- For teacher-initiated group purchases, each student is evaluated independently: students with sufficient balances may succeed, while students without sufficient balances receive an individual rejection and explanation. One student's rejection does not cancel another student's successful purchase.
- Student self-purchases and teacher-initiated purchases must use the same trusted transaction, stock, authorization, idempotency, and audit controls.


### Student withdrawal and re-enrolment continuity
- A student who returns to the same class while their record remains present continues from the same record with unchanged class-period aggregate, spendable balance, achievements, and history.
- Deactivating and reactivating a student restores the same record and history; no duplicate is created.
- Soft-deleting and restoring a student within the permitted recovery window restores the same record and history.
- Re-enrolment checks for a recoverable original before creating a new student record.
- Permanent erasure followed by re-enrolment creates a new record with zero aggregate and zero spendable balance; erased history is not reconstructed.
- A class transfer remains distinct: the receiving class starts at zero while the former class history remains preserved there.
- Restore/new-enrolment actions are authorised, auditable, and do not permit identity collision or duplicate active membership.


### Classroom Rules
- Each classroom teacher manages a separate set of rules for each class they teach; a teacher must not edit another teacher's class rules without an explicitly authorised role.
- A teacher can create, edit, reorder, publish, and remove draft rules. Each rule may contain a title, explanatory text, and optional illustration subject to controlled upload validation.
- Draft changes do not alter the currently published version seen by students.
- Publishing creates an immutable, versioned snapshot. Editing published rules creates a new version; it does not overwrite the prior published version.
- A student must see and acknowledge the current published version before entering the normal student portal on first login and whenever a new version is published.
- A student who has acknowledged the current version is not repeatedly blocked by the same version on later logins.
- Students can reopen and read the current rules at any time.
- A class change causes the student to be evaluated against the receiving class's current rules and acknowledgement state.
- Acknowledgement is verified and recorded server-side with student, class, published version, and timestamp. A browser-only flag or client-supplied acknowledgement is not authoritative.
- Prior published versions and student acknowledgements remain available for audit; publishing a new version does not erase earlier acknowledgements.
- Acknowledging rules is separate from points: it must not automatically award or deduct points.
- Test concurrent publish/acknowledgement, version replacement, class transfer, teacher ownership, unauthorised access, and attempts to bypass the login gate.

## 3. Shared transaction and security requirements

1. **Trusted identity:** Teacher identity comes from verified server-side authentication context. Never accept client-selected teacher identity as authority.
2. **Narrow entrypoints:** Expose only specific business operations; do not expose arbitrary table writes or arbitrary RPC names.
3. **Least privilege:** Browser roles must not directly INSERT into `point_transactions` or UPDATE protected `student_activity_records` columns. Exact grants must be designed only after full caller inventory and verified deployed ACL/schema metadata.
4. **Ownership checks:** Every operation checks teacher ownership, student-to-class membership, activity/reward ownership, and active-state requirements inside the trusted transaction boundary.
5. **Ledger integrity:** Use append-only compensating entries; never rewrite/delete prior point history to simulate corrections.
6. **Idempotency:** Store a unique request identity scoped to the operation/actor and bind it to a canonical payload hash. Same key/same payload returns the stored result. Same key/different payload is rejected.
7. **Concurrency:** Lock the relevant student/reward/request rows or use equivalent serializable/atomic conditional updates. Never rely on a browser-read balance.
8. **Atomicity:** All related state changes for one business operation commit together.
9. **Audit:** Successful business changes and their audit records commit atomically. Rejected attempts may require a separate safe audit path; do not claim a rolled-back transaction can preserve its own audit insert. Do not log access codes, tokens, secrets, or unnecessary student data.
10. **No hidden negative balances:** The ledger and server response must report actual amounts. UI clamping alone is not a security control.
11. **No unverified schema assumptions:** Current production schema for marketplace rewards, purchases, request records, audit records, and purchase RPC is not present in the reviewed repository snapshot. Treat all proposed objects as synthetic test design until independently verified.
12. **No client secrets:** Service-role credentials or other privileged secrets must never be shipped to the browser.

## 4. Required test fixture model (synthetic only)

A separate classroom transaction fixture must be created; do not extend or repurpose the existing game-scoring fixture. The fixture may define synthetic versions of:

- teacher profiles, classes, and students;
- point transaction ledger;
- student activity records and class activities;
- marketplace rewards and purchase history;
- idempotency/request records;
- audit events;
- narrowly scoped test roles and transaction entrypoints.

Every fixture object must be labelled test-only. Do not present the synthetic definitions as verified production schema. Do not impose a unique (activity_id, student_id) constraint pending duplicate-semantics verification. Add only constraints required by the explicitly approved contract and clearly label assumptions.

The test harness must model the trusted Gateway identity boundary. A client must not be able to choose another teacher's identity by setting an ordinary request parameter or user-writable session variable. Any test-only identity injection must be confined to a privileged harness and documented as such; it must not become a production pattern.

## 5. Acceptance test matrix

### Authorization and privilege boundaries
- Unauthenticated/anonymous caller cannot execute transaction entrypoints.
- Authenticated browser role cannot directly insert point transactions.
- Authenticated browser role cannot update protected score, student, teacher, activity, or points fields.
- Teacher A cannot award/deduct for Teacher B's student.
- Teacher A cannot score an activity outside Teacher A's class.
- Teacher A cannot purchase or modify Teacher B's reward.
- A browser-supplied teacher ID cannot override trusted actor identity.
- Gateway/test execution role has only the privileges needed for the transaction functions.

### Awards and deductions
- Positive integer award within configured cap succeeds once.
- Zero, negative, fractional/non-integer, malformed, and above-cap award requests are rejected.
- Repeated same request key and payload does not duplicate the ledger entry.
- Same request key with changed amount/student/reason is rejected.
- Deduction below balance deducts requested amount.
- Deduction above balance deducts only the remaining balance.
- Deduction at zero balance returns no-op and creates no zero-value transaction.
- Concurrent deductions never produce a negative balance or over-deduct.

### Academic-year and class transition
- Verify that a student transferred from one class/teacher to another is enrolled as a new member of the receiving class with zero aggregate points and zero spendable balance, including transfers during the same academic year.
- Verify previous-class points, achievements, transactions, and leadership appointments remain attached to the previous class and teacher's historical records and are not transferred or counted in the receiving class.
- Verify a new class/academic-year period starts with its own aggregate points and spendable balance; no previous-period points roll over.
- Verify previous-period points, achievements, transactions, and leadership appointments remain accessible as historical records.
- Verify previous-period leadership appointments are not active appointments in the new period.
- Verify leadership positions start afresh in the new period and students must qualify again through its milestones.
- Verify historical records are not included in new-period balances, rankings, achievements, or leadership eligibility.

### Leadership position uniqueness
- Verify one student cannot automatically hold more than one leadership position in the same class and academic year.
- When an existing leader reaches another reward-level milestone, verify no second position is assigned to that student and the next qualifying student is considered for the available position.
- Verify leadership position uniqueness is scoped to class and academic year; historical appointments in previous periods remain intact.
- Verify a teacher's deliberate manual appointment change records the change and preserves prior appointment history.

### Class Champion ranking and tie-break
- A single student with the highest aggregate points receives the 1st-position Class Champion award.
- If multiple students tie at the highest aggregate, the teacher administers a live task to distinguish 1st, 2nd, and 3rd positions.
- Verify the top three receive Champion recognition with distinct 1st, 2nd, and 3rd position awards.
- Verify the live-task result is recorded and does not change aggregate points, achievement thresholds, or leadership appointments.
- Do not use browser timestamps or arbitrary database ordering to decide the live-task ranking.

### Undo
- Full undo succeeds when the full reversal is affordable.
- Second undo of the same original transaction is rejected/idempotently returns the first result.
- Undo of an incorrectly awarded earning removes the erroneous amount from both current spendable balance and aggregate points earned; it is recorded as a compensating ledger entry linked to the original earning.
- If the corrected aggregate falls below an achievement threshold, the achievement remains in history but is marked no longer currently valid; it is not deleted.
- If a formal correction reduces the aggregate below the milestone that originally qualified a student for a leadership position, the previously appointed leader retains that post. The appointment remains active; do not automatically transfer the post or appoint a successor because of the correction.
- Verify that the correction is reflected in points/achievement history while the leader's appointment and leadership status remain intact.
- Undo is rejected completely when the student has spent enough points that full reversal would make the balance negative; no partial reversal or negative balance is allowed.
- Ordinary disciplinary/behaviour deductions do not reduce aggregate points earned.
- Concurrent undo attempts create at most one reversal.
- Original ledger row remains unchanged.

### Activity scoring
- Score increase writes the positive delta and updates the activity record atomically.
- Score decrease writes the actual clamped deduction and updates the teacher-assigned score atomically.
- Zero delta creates no point transaction.
- Forced ledger failure rolls back the activity record update.
- Forced activity-record failure leaves no ledger transaction.
- Duplicate submission scenarios are tested against documented current semantics; no uniqueness constraint is added by this specification.
- Concurrent score changes serialize and leave a consistent activity record and ledger.

### Marketplace
- The reward price is editable before the first successful purchase and becomes permanently locked after that first success.
- Failed purchase attempts do not lock the price.
- Concurrent first purchases and price edits serialize so every successful purchase uses one authoritative price and the price-lock transition cannot be bypassed.
- After price lock, attempted price changes are rejected; a new price requires a new reward item.
- Each selected student receives one independent, stable outcome, including in a mixed batch containing successes and failures.
- A successful student's purchase remains committed when another selected student has insufficient balance, invalid ownership/student state, an unavailable reward, or encounters out-of-stock stock.
- A failed student's operation creates no debit, purchase-history row, or stock decrement; it does not cancel or reverse another student's successful operation.
- A retry of the same batch reproduces each student's stored outcome and does not repeat any completed student's debit, purchase row, or stock decrement.
- Concurrent batches competing for limited stock never oversell; each student receives a deterministic purchased or out_of_stock result based on the serialized stock allocation.
- Successful purchase deducts points and writes purchase history atomically.
- Failed purchase does not deduct points or decrement stock.
- `NULL` stock permits purchases without decrement.
- Finite stock decrements exactly once per successful purchase.
- Stock zero rejects purchase.
- Concurrent purchases cannot oversell finite stock.
- Deactivated reward rejects new purchase and retains historical purchase rows.
- Retry of a successful student's purchase does not charge twice or decrement stock twice.
- Same idempotency key with altered reward/student/payload is rejected.

### Audit and failure handling
- Successful operation and success audit event commit together.
- Failed/rolled-back operation leaves no success audit event.
- Rejected-operation telemetry, if implemented, does not expose secrets or rely on a rolled-back insert.
- Unknown outcome can be resolved by retrying/querying the same idempotency key; clients must not invent a new key after a timeout.

## 6. Test execution and release gates

- Run only against disposable local PostgreSQL or isolated CI PostgreSQL with synthetic data and no hosted Supabase credentials/network.
- Preserve existing game-scoring workflows unchanged; classroom transaction tests must have a separate fixture and workflow.
- Test sequential, failure-injection, privilege, concurrency, and idempotency behaviour.
- Record PostgreSQL version and test command/output.
- Static SQL review and passing disposable tests do not authorize production deployment.
- Before any production change, separately verify actual deployed schema, constraints, triggers, effective grants, all application callers, and current marketplace function/table definitions.
- Production rollout requires a separate explicit approval of exact migration/function/grant changes and rollback plan.

## 7. Known unresolved implementation inputs

- Exact exceptional-award override authority, workflow, and limits above the 50-point default.
- Classroom Rules presentation details, allowed image formats/limits, and final teacher/administrator permission matrix.
- Verified deployed definitions/columns/constraints for marketplace rewards and purchases.
- Exact current duplicate activity submission semantics and all deployed callers.
- Trusted Gateway-to-database identity propagation and role model.
- Exact audit retention and rejected-attempt telemetry policy.
- Whether the deployed system permits negative point transactions and any legacy transaction types beyond those seen in the reviewed frontend.

## 8. Approval record

Marketplace policy decision recorded 2026-11-21:
- The user explicitly adopted **independent per-student purchases** as the governing marketplace policy.
- This decision supersedes any earlier all-or-nothing batch direction or interpretation. It does not change the approved stock model: NULL remains unlimited, zero remains out of stock, and finite stock is decremented atomically for each successful student's purchase.
- A mixed batch may therefore contain both committed purchases and rejected student outcomes. Each student's debit, purchase history, applicable stock decrement, and idempotency result remain atomic at that student's boundary.

The user approved all three final business-rule recommendations on 2026-11-09:
- configurable maximum for positive whole-number teacher awards;
- unlimited/finite stock with atomic stock and purchase handling, deactivation preserving history;
- preserve existing duplicate activity submission behaviour pending verification, with tests and no new uniqueness constraint.

Additional Classroom reward and leadership decisions recorded 2026-11-21:
- The user approved separate aggregate-points-earned and current-point-balance measures. Aggregate points govern achievement levels, class ranking, and leadership; current balance governs purchases. The aggregate rule is earned-only: marketplace spending and ordinary deductions do not reduce aggregate points.
- Reward thresholds are Bronze 50+, Silver 100+, Gold 150+, and Champion 500+.
- The Class Champion title belongs to the highest aggregate-point student in the class/academic-year ranking, even if the highest score is below 500. This ranking title is distinct from the 500+ Champion achievement level.
- The first student to reach each reward-level milestone becomes or retains Classroom Captain; the next three qualifying students receive the Disciplinary Prefect, Sanitary Prefect 1, and Sanitary Prefect 2 positions. Teachers may edit the prefect hierarchy/titles. Appointments should appear automatically and remain tied to aggregate points.
- Teachers may upload suitable images for rewards. Students may select avatars only from the approved library; student avatar uploads are not allowed.
- Students may purchase for themselves; teachers may purchase for one student or a group, always using each selected student's own current balance and preserving independent per-student outcomes.

This document is a test specification only. It is not a production schema or migration.


Additional approved decisions recorded 2026-11-21:
- Individual manual teacher awards have a default maximum of 50 points. An authorised school or system administrator controls the configured limit; teachers cannot change it. Above-limit requests are rejected, never silently truncated. Exceptional awards require a separate authorised and audited override. This cap does not apply to activity scores or other separately approved earning sources.
- Marketplace reward price is editable only before the first successful purchase. After that purchase, the price is locked permanently for that reward; a different price requires a new reward item. Failed purchases do not lock the price, and the lock must be concurrency-safe.
- Classroom Rules are teacher-managed separately for each class. Students acknowledge the current published rules at first login and whenever a new version is published, before entering the normal student portal. Published versions and prior acknowledgements are preserved; students can revisit the current rules at any time. Acknowledgement is server-verified and has no automatic points effect.


### Approved Teacher Manual Award Corrections — 2026-11-21
- The manual-award default maximum is 50 points per individual award, controlled only by an authorised school or system administrator. Teachers cannot change the limit.
- A request above the configured limit is rejected with a clear, stable result and no ledger mutation; it is never silently truncated. Any exceptional award above the limit requires a separate authorised, audited override workflow. The override authority, approval steps and limits remain an implementation gate.
- Expected business rejections, including above-cap awards, must be durably idempotent: store the request payload binding, rejected status/result and safe rejection audit in a committed transaction, without a points-ledger mutation. Retrying the same request returns the stored rejection. Reusing the request ID with a different actor, operation or payload is rejected. Unexpected internal/system failures still roll back and must not be converted into committed business rejections.
- All balance-changing award operations follow the approved global lock order: request/idempotency row; relevant class row(s) sorted by UUID; student row; operation-specific rows; writes. The class membership is preliminarily read without a lock, then revalidated after the class and student locks are acquired. A changed membership produces a retryable conflict.
- Award configuration reads must be authoritative and protected. Configuration changes require an authorised administrator; teachers and student/client roles cannot update the limit. Configuration concurrency and audit requirements must be tested.
- The synthetic fixture's prior 100-point seed is obsolete and must be changed to 50 before any disposable test execution. Older 20/100 references must not be treated as current policy.
