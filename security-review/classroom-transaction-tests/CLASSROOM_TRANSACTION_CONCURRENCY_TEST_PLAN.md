# Classroom Transaction Concurrency Test Plan

**Status:** Review-only test protocol. Not executed.  
**Environment:** Fresh disposable PostgreSQL database only.  
**Scope:** Synthetic classroom transaction fixture and Phase 1–3 function drafts.

## Safety boundary

- Never run this plan against Supabase, production, `cloud-test`, or any shared database.
- Do not use real student or teacher records.
- Do not change production grants, policies, functions, or deployments.
- Install the synthetic fixture, function drafts and seed only in a fresh disposable database after separate static review.
- Use two independent database sessions for each race. Do not simulate concurrency by running calls sequentially in one session.
- Capture both session outputs and final state queries. Roll back or recreate the disposable database after each scenario.

## Preconditions

Before these tests can be trusted, independently verify:

1. The fixture and Phase 1–3 function drafts compile on the pinned PostgreSQL version.
2. The Gateway role context works through nested `SECURITY DEFINER` calls.
3. Function ownership, fixed search paths, and ACL assertions pass.
4. Every balance-changing function uses the same student-row lock before reading the ledger.
5. Every purchase locks the student first and reward second.
6. The test runner can invoke functions as `temmy_ctest_gateway` in each session.
7. Each scenario starts from a known seed state, with no leftover request IDs or test mutations.

If any precondition fails, stop; do not interpret concurrency results.

## Session invocation pattern

Use two independent psql terminals connected to the same disposable test database. In each session, invoke the relevant function while acting as the Gateway role. The following is a pattern, not a complete executable test:

```sql
BEGIN;
SET LOCAL ROLE temmy_ctest_gateway;

SELECT classroom_test.purchase_reward_for_student(
  '<teacher-uuid>',
  '<student-uuid>',
  '<reward-uuid>',
  '<unique-request-uuid>'
);

COMMIT;
```

Use distinct request UUIDs unless the scenario explicitly tests a duplicate request. For a deliberately rejected call, capture the error and end/roll back that transaction before inspecting state from a separate administrator session. The current drafts roll back the idempotency claim on expected business exceptions.

## Scenario 1 — Last item, two different students

**Setup:** A reward owned by Teacher A has finite stock = 1. Two active students in Teacher A's class each have sufficient balance.  
**Sessions:** A and B purchase the same reward for different students, each with a different request UUID. Start both calls as close together as possible.

**Expected:**
- Exactly one purchase succeeds.
- Exactly one marketplace debit is committed.
- Stock becomes 0, never negative.
- The losing call receives `reward_out_of_stock` after it obtains the reward lock.
- No purchase, debit, or stock decrement is committed for the losing call.

**Why:** The reward row lock serializes competing purchases against finite stock.

## Scenario 2 — Two deductions competing for one balance

**Setup:** Student One has 10 points.  
**Sessions:** A requests a deduction of 7; B requests a deduction of 7. Use different request UUIDs.

**Expected:**
- Both requests may complete according to the approved clamp-to-balance rule.
- Combined committed deduction must be exactly 10, not 14.
- One call deducts 7; the other deducts the remaining 3, regardless of which obtains the lock first.
- Final balance is 0; no zero-value ledger transaction is inserted.

**Why:** Both functions must lock the same student row before reading the ledger balance.

## Scenario 3 — Two different purchases competing for one student's balance

**Setup:** Student One has 10 points. Two active rewards owned by Teacher A each cost 8 and have stock available.  
**Sessions:** A purchases Reward X; B purchases Reward Y, using different request UUIDs.

**Expected:**
- Exactly one purchase succeeds.
- Exactly one debit of 8 is committed.
- The other request rejects for insufficient points.
- Final balance is 2.
- No second purchase record or stock decrement is committed.

**Why:** The student-row mutex serializes all balance-changing operations for that student, even when reward rows differ.

## Scenario 4 — Same request ID and same payload, simultaneous retry

**Setup:** Student One has sufficient balance and Reward X is active/in stock.  
**Sessions:** A and B call the same purchase operation with exactly the same teacher, student, reward and request UUID.

**Expected:**
- One purchase, one ledger debit, one stock decrement, one success audit and one completed request row.
- Both calls return the same stored successful result; the second response should indicate replay.
- The student is charged once only.

**Why:** The unique request key and `INSERT ... ON CONFLICT` claim must serialize duplicate requests. The second caller should read the completed result after the first commits.

## Scenario 5 — Same request ID, different payload

**Setup:** Use the same request UUID in two concurrent calls, but change the student or reward in one call.  
**Expected:**
- At most one payload is accepted for that request UUID.
- The other call rejects with `idempotency_key_reused_with_different_payload`.
- No second ledger mutation, purchase or stock decrement occurs.
- Which payload wins is intentionally nondeterministic; the invariant is that only one payload binds to the key.

## Scenario 6 — Same request ID, simultaneous awards

**Setup:** Student One; same teacher, amount and reason.  
**Sessions:** Both call `award_points` with the same request UUID.

**Expected:**
- One positive ledger transaction.
- One success audit.
- One completed request row.
- Both calls return the same result, with replay indicated on the retry.
- Balance increases once only.

## Scenario 7 — Different award and deduction requests for the same student

**Setup:** Student One has 10 points.  
**Sessions:** A awards 5; B deducts 7, each with a different request UUID.

**Expected:**
- Both operations serialize through the student row.
- Final balance is 8 regardless of lock order (10 + 5 - 7).
- Both ledger transactions are present exactly once.
- No lost update or stale-balance result.

## Additional class/student administration race scenarios\n\n8. **Award versus class deactivation:** run an award while another session deactivates the student's class. The outcome must be equivalent to one serial order; no award may commit based on a class already deactivated.\n9. **Award versus class ownership change:** change class ownership concurrently with an award. No operation may authorize using stale ownership.\n10. **Award versus student transfer:** force the preliminary class lookup to occur before a transfer, then verify the transaction detects changed membership after acquiring the class and student locks and does not award under the stale class.\n11. **Opposite-direction student transfers:** transfer students between the same two classes in opposite directions. Both sessions must lock class IDs in ascending order to avoid avoidable deadlocks.\n12. **Activity score versus activity edit/deactivation:** verify class-before-activity locking produces a consistent result.\n13. **Purchase versus class deactivation/student transfer:** no purchase may rely on stale class membership or active state.\n14. **Reward deactivation versus purchase:** reward maintenance and purchase must serialize on the reward row; no purchase may proceed after deactivation commits.\n\n## Evidence to capture

For each scenario, record:

- Scenario ID and disposable database identifier.
- PostgreSQL version.
- Start state (balance, reward stock, relevant row counts).
- Session A and B start times and complete outputs.
- Whether either session blocked and approximate wait duration.
- Final balance, ledger rows, purchase rows, stock, request rows and audit rows.
- Any SQLSTATE/error text.
- Whether the result matches every expected invariant.

Do not use wall-clock timing alone as proof of concurrency. Confirm overlap by holding one session at a deliberate test-only synchronization point or by observing lock waits in a separate administrator session. Any such instrumentation must remain confined to the disposable environment.

## Current design caveats to resolve

1. **Rejected request durability:** Expected business exceptions roll back the request claim and in-transaction audit. This plan can assert no partial mutation, but it cannot establish durable rejection idempotency. Decide whether expected rejections should be stored as completed `rejected` results in a committed transaction or intentionally remain retryable.
2. **Duplicate same-key error race:** Verify the unique-key conflict path and result visibility under the actual PostgreSQL isolation level. Default READ COMMITTED is assumed; repeat under the chosen production isolation level before approval.
3. **Lock ordering:** Follow TEMMY_CLASSROOM_GLOBAL_LOCK_ORDERING_RULE.md. The class row is locked before the student row; purchases then lock reward. Verify class administration, student transfers, activity edits and reward management use compatible ordering.
4. **Activity scoring:** Test concurrent score changes and activity administration under the approved class → student → activity order. Revise the current draft, which still uses student-first locking.
5. **Deadlock handling:** Define retry behaviour for SQLSTATE `40P01` and serialization failures, reusing the same request UUID and identical payload.
6. **Idempotency retention:** Define how long completed request rows are retained. Do not delete keys while a client may legitimately retry.
7. **No execution claim:** No concurrency test has been run. This document describes expected experiments only.

## Exit criteria

Do not approve the transaction layer until all scenarios pass repeatedly, no duplicate ledger/purchase rows appear, balances and finite stock remain correct, no partial mutation survives a rejected/failing request, and all lock waits/deadlocks are understood with an explicit safe retry policy.
