# Temmy Smart Classroom — Points Migration Verification Plan

**Target:** isolated Supabase/PostgreSQL test project only  
**Branch:** `cloud-test`  
**Status:** prepared; not executed  
**Production rule:** do not apply these migrations to `main` or the hosted production database as part of this test.

## Migration order

Apply the five reviewed migration files in timestamp order:

1. `20261125000100_create_student_point_accounts.sql`
2. `20261125000200_add_atomic_point_transaction_rpc.sql`
3. `20261125000300_add_teacher_point_account_summary_rpc.sql`
4. `20261125000400_update_marketplace_purchase_spendable_account.sql`
5. `20261125000500_add_student_point_account_summary_rpc.sql`

Run them against a disposable database populated with a schema and representative data snapshot matching the hosted project. Do not use production credentials or real student access codes.

## Preconditions and schema checks

Before applying, confirm the test database contains the expected tables, columns, constraints and roles:

- `students(id, class_id, active, first_name, last_name)`
- `classes(id, teacher_id, active)`
- `teacher_profiles(id)`
- `point_transactions(student_id, teacher_id, points, action_name, action_type, reason, source, created_at)`
- `marketplace_rewards(id, teacher_id, active, price, name)`
- `purchases(student_id, teacher_id, reward_id, reward_name, points_spent)`
- `marketplace_purchase_requests(teacher_id, request_id, reward_id, student_ids, result)`
- `student_access(student_id, code_hash, active)`
- Existing `verify_student_access_code(text)` and `get_student_point_history(text)` definitions.
- Supabase roles `anon` and `authenticated`, and `auth.uid()`.

Confirm the foreign-key target `teacher_profiles(id)` is the teacher identity used by `auth.uid()`, and verify that `classes.teacher_id` references the same identity.

## Backfill assertions

Immediately after migration 1, compare every account row against the legacy ledger:

```sql
select
  s.id as student_id,
  a.aggregate_points,
  a.spendable_points,
  coalesce(sum(pt.points) filter (
    where pt.action_type is distinct from 'marketplace_purchase'
  ), 0)::bigint as expected_aggregate,
  coalesce(sum(pt.points), 0)::bigint as expected_spendable
from public.students s
join public.student_point_accounts a on a.student_id = s.id
left join public.point_transactions pt on pt.student_id = s.id
group by s.id, a.aggregate_points, a.spendable_points
having a.aggregate_points <> coalesce(sum(pt.points) filter (
         where pt.action_type is distinct from 'marketplace_purchase'
       ), 0)::bigint
    or a.spendable_points <> coalesce(sum(pt.points), 0)::bigint;
```

Expected result: **zero rows**. Also confirm no negative Spendable balance exists.

## Functional acceptance tests

Use dedicated disposable teacher, class, student, reward and access-code fixtures. Record the initial account and ledger values before each test.

1. **Positive award:** award +5 to one active student in the authenticated teacher's class. Expect one ledger row, Aggregate +5, Spendable +5.
2. **Negative adjustment:** apply -2 where Spendable is sufficient. Expect one ledger row, Aggregate -2, Spendable -2.
3. **Insufficient negative adjustment:** attempt a deduction that would make Spendable negative. Expect an RPC error and no ledger or account change.
4. **Undo:** submit the reversal through the same atomic RPC. Expect the signed reversal to affect both balances and appear as an auditable `undo` transaction.
5. **Request retry:** call the award RPC twice with the same teacher, request ID and identical payload. Expect the same stored result and exactly one set of ledger/account changes.
6. **Request ID reuse:** reuse that request ID with a different class or payload. Expect rejection and no additional changes.
7. **Class/student scope:** attempt to award a student outside the teacher's active class, an inactive student, and a student in an inactive class. Expect rejection and no changes.
8. **Marketplace purchase:** buy a reward for one student. Expect Spendable reduced by the price, Aggregate unchanged, one negative `marketplace_purchase` ledger row and one purchase record.
9. **All-or-nothing multi-student purchase:** include one student with insufficient Spendable Points. Expect the entire call to fail with no purchase records, ledger rows or balance changes for any selected student.
10. **Purchase retry:** repeat the same purchase request ID and details. Expect the cached result and no second deduction or purchase record.
11. **Purchase request mismatch:** reuse a purchase request ID with different reward/student details. Expect rejection.
12. **Concurrent spending:** race two purchases against a balance sufficient for only one. Expect no negative balance and at most one completed purchase.
13. **Concurrent award/purchase:** race an award and purchase for the same student. Expect both committed operations to be reflected exactly once and no lost update.
14. **Teacher balance RPC:** authenticated teacher sees only active students in their own active classes; a different teacher sees none of those rows.
15. **Student balance RPC:** valid active access code returns only that student's two balances; invalid, inactive or unknown code returns zero rows. It must not reveal another student's identity or balances.
16. **History compatibility:** existing `get_student_point_history(text)` still returns the verified student's transaction history.
17. **Privilege checks:** `anon` and `authenticated` cannot select directly from `student_point_accounts` or `student_point_operation_requests`; only the intended RPC grants work.
18. **New-student initialization:** a student without an account row is initialized from their complete legacy ledger exactly once before the first award or purchase. Confirm the initialization rule is consistent regardless of which teacher currently owns the class.

## Concurrency and transaction checks

- Confirm the award RPC and purchase RPC lock student rows before account rows and lock multiple students in deterministic ID order.
- Confirm a failed multi-student request rolls back its request claim, ledger inserts, purchases and account changes.
- Confirm a retry after a committed response returns the cached result.
- Confirm a retry after a transaction rollback can safely execute.
- Run concurrency tests with separate database sessions; sequential tests alone are insufficient.

## Post-test audit queries

Check that the account summaries still reconcile to the ledger under the approved definitions:

```sql
select
  a.student_id,
  a.aggregate_points,
  coalesce(sum(pt.points) filter (
    where pt.action_type is distinct from 'marketplace_purchase'
  ), 0)::bigint as ledger_aggregate,
  a.spendable_points,
  coalesce(sum(pt.points), 0)::bigint as ledger_spendable
from public.student_point_accounts a
left join public.point_transactions pt on pt.student_id = a.student_id
group by a.student_id, a.aggregate_points, a.spendable_points
having a.aggregate_points <> coalesce(sum(pt.points) filter (
         where pt.action_type is distinct from 'marketplace_purchase'
       ), 0)::bigint
    or a.spendable_points <> coalesce(sum(pt.points), 0)::bigint;
```

Expected result: zero rows after all test operations. Also verify every purchase record has exactly one matching negative marketplace transaction and that account Spendable deltas equal those transaction deltas.

## Review notes / known boundaries

- The account model is global per student. New-account initialization in every write path must therefore aggregate the student's complete ledger, not only transactions associated with the current teacher.
- The teacher point RPC requires an active class and an active student. Inactive students must be rejected consistently by award, marketplace and student access paths.
- The activity-score record update and point RPC are still separate calls in the browser. This plan does not certify that workflow as one atomic operation; it remains a follow-up hardening item.
- No test in this document has been run. A successful static review is not evidence of PostgreSQL execution, RLS correctness, or concurrency safety.
