# Temmy Classroom Global Lock-Ordering Rule

**Status:** Approved design rule; review-only documentation  
**Approval:** User approved class/student locking on 2026-11-09.  
**Not implemented:** No SQL, code, hosted database, or deployment changes are authorized by this document.

## Decision

Every transaction that depends on a student's class membership or class status must lock and validate the class row before locking the student row. This closes the race where a class is deactivated or a student is transferred while a point operation is in progress.

Use one global order for all related mutating paths:

1. Claim/lock the idempotency request row (for request-based operations).
2. Lock the relevant class row(s), in ascending stable UUID order when more than one class is involved.
3. Lock the student row.
4. Lock operation-specific rows: activity record, original point transaction, then reward row, as applicable.
5. Write ledger, activity, purchase, request result and audit records.

The precise order among operation-specific rows must be applied consistently if an operation ever needs more than one of them. No workflow may acquire a later-ranked row and then request an earlier-ranked row.

## Safe student-to-class validation

A transaction must not lock the student first merely to discover its class, because that reverses the approved class-before-student order.

Instead:

1. Read the student's current class ID as a preliminary, non-locking lookup.
2. Lock that class row using the appropriate lock mode.
3. Lock the student row.
4. Re-read the student's class ID and validate it still matches the preliminary class ID.
5. Verify the class is active and belongs to the authenticated teacher, and verify the student is active.
6. If the class ID changed between steps 1 and 4, abort with a retryable conflict/stale-membership result. Do not proceed using the stale class lock.

The initial lookup is not trusted for authorization; it only identifies which class row to lock. The ownership and active-state checks occur after the locks are held.

For a business transaction, use a lock mode that conflicts with class deactivation, ownership changes and student-transfer administration (normally a row-level FOR SHARE on the class, subject to PostgreSQL's exact row-lock compatibility). Administrative changes use a conflicting stronger lock (normally FOR UPDATE) before changing class ownership/status or student membership.

## Student transfer and class administration

A student transfer must:

1. Read the current class ID.
2. Lock both old and new class rows in ascending UUID order (one row if same class).
3. Lock the student row.
4. Re-check that the student's current class is still the expected old class.
5. Validate the new class is active and permitted.
6. Update the student's class membership and commit.

Class deactivation or ownership change must lock the class row before changing its status/owner. If it also changes student rows, it follows class-before-student order. Any operation affecting multiple classes locks them in ascending UUID order to avoid opposite-order deadlocks.

## Operation-specific ordering

- **Award/deduction:** idempotency request → class → student → ledger/request-result/audit writes.
- **Activity score:** request → preliminary activity/record lookup → class → student → activity record → ledger and audit writes. Re-read and validate the activity/record relationship after locks are held.
- **Undo:** request → preliminary original-transaction lookup → class → student → original transaction → reversal ledger/audit writes. Re-read original transaction after locks are held.
- **Marketplace purchase:** request → class → student → reward → purchase/ledger/audit writes.
- **Activity administration:** class → activity (and any affected student/activity rows only in the same class-before-student order).
- **Reward maintenance:** reward row only; it must never lock a reward and then attempt to lock a student. Purchase takes student before reward.
- **Class administration/student transfer:** class row(s), sorted by UUID → student row(s), sorted by UUID if more than one student is touched.

The idempotency request row is a per-request serialization key and is acquired before business-entity locks. Administrative paths that do not use idempotency do not acquire request rows.

## Lock modes and caveats

The exact PostgreSQL lock mode must be verified against the pinned version and the actual foreign keys/triggers. A normal business transaction should hold a class lock that prevents concurrent deactivation, owner change or transfer from invalidating its authorization decision, while allowing compatible business reads. Administrative writes must take a conflicting lock.

Do not assume FOR SHARE is interchangeable with FOR KEY SHARE; verify the conflict matrix. Foreign-key checks, cascades, triggers, and implicit locks can add edges to the lock graph. Inventory all actual class/student/activity administration paths before implementation.

## Retry and failure behaviour

If the student membership changed after the preliminary lookup, return a stable retryable conflict result or abort the transaction. The caller retries the exact same request UUID and canonical payload only when the operation contract says that retry is safe. Deadlock (40P01) and serialization failures require bounded retry using the same request key and payload. Never silently switch to a new request ID after an uncertain outcome.

## Required disposable-environment tests

1. A point award racing with class deactivation: exactly one serial order; no award based on a deactivated class.
2. A point award racing with class ownership change: no cross-teacher award.
3. A point award racing with student transfer: stale class lookup is detected; no transaction under the old class after transfer.
4. Two simultaneous transfers in opposite directions: sorted class lock order avoids avoidable deadlock.
5. Activity score racing with activity edit/deactivation: operation sees a consistent authorized state.
6. Marketplace purchase racing with student transfer/class deactivation: no purchase under stale membership.
7. Reward deactivation racing with purchase: exactly one valid serial order; no purchase after deactivation commits.
8. Confirm every path follows the same lock order and capture actual PostgreSQL lock waits/SQLSTATEs.

## Safety boundary

This is a design rule only. No SQL was executed, no hosted database was queried or changed, and no production code or deployment was modified. The existing Phase 1–3 SQL drafts still require revision and isolated verification before any execution.
