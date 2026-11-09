# Temmy Smart Classroom — Consolidated Security Decision and Readiness Review

**Review date:** 2026-11-09  
**Status:** Consolidated design review — implementation and execution not authorized  
**Repository:** `oyeleketemitope787-sys/temmy-smart-classroom`  
**Review branch:** `security-review/student-login-hardening`  
**Protected branches:** `main` (production) and `cloud-test` (shared development) — do not modify  
**Supabase project:** `temmy-smart-classroom-test` — hosted database remains out of scope

## 1. Executive summary

The security direction for Temmy Smart Classroom is now sufficiently defined at the business-rule and architecture level to guide the next design phase. The classroom must be secured and made independently launch-ready before any new game platform is connected. The old game platform is retired from this plan. A future game platform will be a separate project and will communicate with the classroom only through a deliberately designed Temmy Gateway.

The central security principle is that the browser is an untrusted requester, not an authority. Verified identity, ownership checks, point calculations, purchase handling, idempotency, and audit guarantees must be enforced by trusted server-side components and narrowly scoped database operations.

**No implementation readiness claim is made.** Existing SQL drafts remain unexecuted and contain known design gaps. No application code, hosted database, grants, migrations, Edge Functions, or deployment have been changed or authorized by this review.

## 2. Scope and safety boundaries

- Complete the classroom security work first; classroom launch must not depend on the future games project.
- Design and implement Temmy Gateway as the future controlled bridge between classroom and games.
- Keep all review work on `security-review/student-login-hardening`.
- Do not modify `main` or `cloud-test`.
- Do not perform hosted Supabase writes, migrations, grants/revokes, deployments, or test-data changes without separate explicit approval.
- Do not execute SQL drafts in the existing local database `temmy_classroom_local`; it is not an approved scratch target.
- Any SQL execution must wait for explicit approval of a newly provisioned disposable database/cluster, positively verified to contain synthetic data only and to have no production network/credential path.
- Approval of a design or document is not approval to implement, execute, deploy, or alter a database.
- Continue one command or decision at a time, explaining its effect before any operation.

## 3. Approved classroom transaction business rules

### 3.1 Point awards and deductions

- Teacher awards are positive whole numbers.
- Initial system-wide maximum: **20 points per individual student award**.
- The same maximum applies to every teacher.
- For a multi-student award action, the 20-point maximum is checked independently for each student, not against the batch total.
- An individual award above the configured maximum is rejected in full; it is not truncated or partially awarded.
- Only an authorized System Administrator may change the system-wide maximum. Teachers cannot set their own limits.
- The trusted transaction layer enforces the maximum. Browser checks are supplementary only.
- Deductions cannot produce a negative balance. If requested deduction exceeds a positive balance, deduct only the available balance.
- If the balance is already zero, the deduction is an accepted no-op: no ledger row and no balance change, but a lightweight attributable audit event is required.
- A zero-value ledger transaction must not be created.
- The signed point ledger remains the source of truth for balances.

### 3.2 Undo/reversal

- Undo is a full compensating reversal linked to the original eligible transaction; original ledger rows are not edited or deleted.
- An original transaction may be reversed at most once.
- If the student has spent some of an awarded amount and a full reversal would make the balance negative, reject the undo completely. No partial reversal and no negative balance.
- Authorization must be tied to the permitted actor/ownership policy for the original action.

### 3.3 Activity scoring

- The activity record stores the teacher-assigned score.
- The ledger records the score delta, not the new score total.
- Example: 6 to 9 produces +3; 9 to 5 requests -4.
- A downward score change is clamped to the student's available balance; the activity record still stores the assigned score even if the actual deduction is smaller.
- Activity record update and corresponding ledger entry must commit atomically or both roll back.
- Zero delta or zero actual deduction creates no zero-value ledger transaction.
- Preserve existing duplicate activity-submission behaviour until deployed semantics are verified. Test duplicates; do not add a unique constraint on `(activity_id, student_id)` in this design.

### 3.4 Marketplace purchases

- Process each student's purchase independently; one student's failure does not roll back another student's successful purchase.
- For each student, purchase history, point debit, and finite-stock decrement must be atomic.
- Insufficient balance, inactive/unavailable reward, or out-of-stock means no purchase, no debit, and no stock decrement.
- A retry must not charge twice.
- Reward must belong to the acting teacher and be active at purchase time.
- Deactivation blocks new purchases but preserves purchase history and historical reward details.
- `NULL` stock means unlimited; finite stock is non-negative and decremented atomically.
- Concurrent purchases must not oversell finite stock.
- The future UI/API must return independent per-student outcomes rather than all-or-nothing batch semantics.

## 4. Idempotency, rejection, failure, and audit policy

- Each mutation has a request ID scoped to operation and verified actor, bound to a deterministic, operation-specific canonical payload hash.
- Same scope + same request ID + same payload returns the previously stored outcome without repeating or re-evaluating the operation.
- Same request ID with a different payload rejects as key reuse; the alternate payload must never execute.
- A new request ID evaluates current business state.
- Durable expected business rejections return a structured `rejected` result and persist the rejection outcome plus safe rejection audit atomically, without business mutation.
- Illustrative rejection codes include `INSUFFICIENT_POINTS`, `AWARD_LIMIT_EXCEEDED`, `REWARD_INACTIVE`, `OUT_OF_STOCK`, and `IDEMPOTENCY_KEY_REUSED`.
- Retryable stale-state/concurrency conflicts are not durable business rejections and must not be permanently stored as final outcomes.
- Unexpected database/system failures propagate and roll back fully; do not suppress them or map them to ordinary business rejections.
- Successful mutation, final request result, and success audit must commit together.
- Required audit failure rolls back the operation.
- A zero-balance deduction no-op is stored idempotently and has one lightweight audit event; same-key retries do not duplicate it.
- Separate audit treatment for idempotency-key reuse attempts remains an implementation decision.
- The exact canonical encoding/hash implementation and retry mapping remain to be verified.

## 5. Approved identity, administrator, and recovery architecture

### 5.1 Gateway authentication boundary

- Teacher signs in through Supabase Auth.
- Browser sends the access token to a server-side Gateway (initially planned as an Edge Function).
- Gateway validates the token and derives teacher identity from verified `sub`; it never trusts a teacher ID or role from the browser body.
- Gateway checks class/student ownership and invokes narrowly scoped trusted database functions.
- Browser never receives a service-role key.
- Gateway implementation and deployment are not authorized yet.

### 5.2 System Administrator authority

- One designated Platform Owner appoints and removes System Administrators.
- Teachers cannot self-promote or grant privileges to themselves.
- Role authority must come from a protected server-side source, not request body, browser state, editable profile fields, or user-controlled metadata.
- System Administrators may change the system-wide award maximum but cannot bypass Gateway/transaction invariants or directly alter point ledgers.
- Fresh MFA/re-authentication is mandatory before changing the award maximum and before the Platform Owner appoints or removes a System Administrator—even during an active signed-in session.
- Administrative actions must be attributable and audited.
- Exact role storage, bootstrap, MFA provider, challenge freshness, and audit implementation remain open.

### 5.3 Platform Owner recovery

- Recovery is controlled and offline; it is not public, self-service, or available through teacher UI.
- Two-person approval is mandatory: two separately authorized ownership representatives must independently verify and approve.
- The representatives must be different natural persons, use independent channels, and not share credentials.
- They are recovery custodians, not automatically System Administrators.
- The remaining representative cannot appoint a replacement alone if the Platform Owner is unavailable.
- If the two-person condition cannot be met, recovery pauses; the safeguard must not be bypassed.
- Representative designation, replacement, periodic review, identity verification, and recovery outcome must be auditable.
- The governance policy is approved, but actual legal/business ownership authority, representative identities, verification evidence, custodians, and the offline runbook still need to be established.
- No person has been appointed by this design.

## 6. Approved concurrency and locking rule

The approved global lock order for sensitive transactions is:

1. Idempotency request row.
2. Relevant class row(s), sorted by stable UUID.
3. Student row.
4. Operation-specific activity, original transaction, or reward rows.
5. Writes.

For a student's class, perform an initial non-locking class lookup, lock the class, lock the student, then re-read class membership. If membership changed, abort with a retryable conflict. Student transfer locks old/new class rows in sorted order, then student, and revalidates. Class deactivation/owner changes lock class before update. Reward maintenance must not lock reward before student.

Exact PostgreSQL lock modes and interactions with FKs/triggers must be verified against the target database version.

**Known draft conflict:** Existing Phase 1–3 function drafts use student-first locking and must be revised to match this approved global order before any execution.

## 7. Confirmed audit findings and risks

These findings were observed in the reviewed source/schema material; they are not claims that production has already been changed.

### High-priority authorization/integrity findings

1. **Direct point-ledger INSERT is too permissive.** Authenticated users have INSERT permission across point transaction columns, while the RLS policy primarily checks teacher ownership. No relevant table trigger was found in the inspected snapshot. Recommendation: remove direct browser/client ledger insertion only after full caller inventory and move mutations to narrow trusted workflows.
2. **Activity-record UPDATE is too broad.** Authenticated users can update all inspected columns; the policy primarily checks teacher ownership. This can permit modification of protected student/activity/score fields within an owned row. Recommendation: restrict column-level updates and strengthen trusted mutation boundaries.
3. **Activity record and ledger update are currently separate browser operations.** A rollback attempt exists in the UI, but rollback can fail, risking inconsistency. Move this to one trusted atomic operation.
4. **Student access codes:** inspected generator creates six random bytes but uses the first eight hex characters, giving 32-bit effective entropy. No visible custom-RPC rate limiting, expiry, failed-attempt counter, or lockout was found in inspected schema/functions. This requires a separate access-code hardening design and tests.
5. **Game result path:** inspected result function accepted client-supplied score/max and did not verify answers against a server-held answer key. The review-only Gateway/result scaffold deliberately fails closed. The existing game platform is retired from this plan; the future game platform must use trusted scoring.

### Important schema/caller uncertainties

- The reviewed repository snapshot did not contain verified production definitions for marketplace purchases, rewards, and the current purchase RPC.
- Current deployed duplicate activity-submission semantics are not yet established.
- Existing source contained direct browser RPC calls for several student/classroom operations; every caller must be inventoried before changing grants or function permissions.
- Some SQL ACL output showed function EXECUTE grants to roles, but Data API exposure results differed; effective reachability must be tested from actual deployed configuration and not inferred from ACL output alone.
- Local review indicated no deployed Edge Functions at the time inspected; re-check before any implementation planning.
- Existing game sessions inspected were all expired; cleanup policy and current deployment state require confirmation if those tables remain relevant.
- Do not infer that an absent source definition means a deployed function or table does not exist.

## 8. Current test and SQL draft status

The review branch contains a synthetic transaction fixture, function drafts (Phase 1–3), seed data, smoke tests, edge-case tests, ACL assertions, concurrency plan, atomicity plan, and static review findings.

**None of these SQL drafts/tests have been executed or syntax/runtime validated.**

Known required corrections/gates:
- Change synthetic fixture award maximum from 100 to approved 20 before any future test execution.
- Rewrite Phase 1–3 lock order from student-first to request → sorted class rows → student → operation rows → writes.
- Reconcile SECURITY DEFINER ownership and nested role-context checks; the current test-only `current_setting('role')` approach is not yet proven safe or correct in nested SECURITY DEFINER calls.
- Verify SHA-256 helper/function availability and deterministic canonical encoding.
- Resolve durable expected rejection and rejection-audit persistence. An insert followed by exception in the same transaction will roll back; drafts must not claim durable audit until a correct design is tested.
- Resolve idempotency-key-reuse audit treatment.
- Define final API result schema for success, durable rejection, retryable conflict, and unexpected failure.
- Verify lock modes, FKs, triggers, transaction isolation, and deadlock/serialization retry policy.
- Verify actor identity propagation in a real Gateway-to-database boundary; synthetic privileged-runner identity injection is test-only.
- Validate all fixtures against actual production schema only after read-only schema/caller inventory; synthetic schema must never be presented as production schema.
- Run failure-injection, concurrency, ACL, authorization, idempotency, and business-rule tests in a newly provisioned disposable database only after explicit approval.

## 9. Outstanding implementation gates

The following must be completed before production implementation:

1. Full deployed schema, constraints, triggers, effective grants/RLS, function definitions, Edge Function inventory, and application caller inventory.
2. Decide the final trusted role source and verify Gateway-to-database identity propagation.
3. Finalize role provisioning/bootstrap and Platform Owner initial setup.
4. Confirm actual legal/business ownership authority and designate two independent recovery representatives.
5. Define independent identity verification, offline recovery custodians, notification path, and runbook.
6. Select MFA provider and technically enforce fresh challenge/session freshness for award-cap changes and administrator appointment/removal.
7. Define protected administrative audit schema, retention, access, and failure behaviour.
8. Complete transaction function design with approved global lock order and correct durable rejection/idempotency handling.
9. Align synthetic fixture cap to 20 and revise stale SQL drafts.
10. Positively provision and verify a fresh disposable PostgreSQL environment; do not reuse the existing local classroom DB without separate approval.
11. Execute and retain test evidence for sequential paths, edge cases, ACL/privilege boundaries, failure atomicity, concurrency races, idempotency, and recovery/admin controls.
12. Perform independent review of all findings and test failures.
13. Prepare exact production migration/function/grant changes, rollback plan, staged rollout, and post-deployment verification.
14. Obtain separate explicit approval for every production-impacting change and deployment.

## 10. Recommended phase sequence

**Phase A — Read-only verification:** Finish deployed schema, caller, grants, function, and Edge Function inventory. Do not change permissions.

**Phase B — Design reconciliation:** Update transaction function drafts, fixture, API outcomes, rejection/audit path, identity propagation, administrator role model, and recovery runbook to match every approved decision.

**Phase C — Disposable implementation/testing:** Only after explicit approval, use a fresh isolated database with synthetic data. Compile and run all test suites, including concurrency and failure injection. Preserve evidence and fix all failures.

**Phase D — Classroom launch readiness:** Review classroom security independently of future games. Confirm the existing classroom works without relying on the retired game platform. Do not make game integration a launch dependency.

**Phase E — Future Temmy Gateway and games:** After classroom readiness, implement Gateway and a separate new game platform against the approved contract. Use trusted score verification, short-lived single-use sessions, game allowlisting, replay prevention, and server-side result validation.

**Phase F — Production change approval:** Present exact changes, risks, rollback, and test evidence. Obtain explicit approval before any hosted database write, grant change, migration, Edge Function deployment, or application deployment.

## 11. Release decision

**Current decision: NOT READY for SQL execution, production implementation, or deployment.**

The approved business and architecture rules provide a strong design baseline, but known draft conflicts, unverified production schema/callers, untested function security, and incomplete operational recovery details remain. The next safe action is read-only verification and design reconciliation—not execution.

This document consolidates approved decisions and known gates as of 2026-11-09. It does not authorize any code, SQL, database, permission, configuration, or deployment change.
