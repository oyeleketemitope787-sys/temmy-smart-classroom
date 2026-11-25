-- Temmy Smart Classroom: read-only per-student legacy points reconciliation
-- Run in Supabase SQL Editor. SELECT statements only; no data/schema changes.
-- Returns student UUIDs, not names or access codes.

-- 1) Inspect the existing purchase-request structure.
select ordinal_position, column_name, data_type, udt_name,
       is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'marketplace_purchase_requests'
order by ordinal_position;

-- 2) Calculate proposed opening balances from the existing signed ledger.
-- Aggregate excludes marketplace deductions; Spendable includes all transactions.
select
  s.id as student_id,
  coalesce(sum(pt.points) filter (
    where pt.action_type is distinct from 'marketplace_purchase'
  ), 0)::bigint as proposed_aggregate_points,
  coalesce(sum(pt.points), 0)::bigint as proposed_spendable_points,
  count(pt.id) as legacy_transaction_count
from public.students s
left join public.point_transactions pt on pt.student_id = s.id
group by s.id
order by s.id;

-- 3) Reconcile purchase records against marketplace deduction transactions,
-- by student, to identify any historical mismatch before backfilling.
with purchase_totals as (
  select student_id, coalesce(sum(points_spent), 0)::bigint as purchase_points,
         count(*) as purchase_count
  from public.purchases
  group by student_id
),
deduction_totals as (
  select student_id, coalesce(sum(abs(points)), 0)::bigint as deducted_points,
         count(*) as deduction_count
  from public.point_transactions
  where action_type = 'marketplace_purchase' and points < 0
  group by student_id
)
select
  coalesce(p.student_id, d.student_id) as student_id,
  coalesce(p.purchase_count, 0) as purchase_count,
  coalesce(p.purchase_points, 0) as purchase_points,
  coalesce(d.deduction_count, 0) as deduction_count,
  coalesce(d.deducted_points, 0) as deducted_points,
  coalesce(p.purchase_points, 0) - coalesce(d.deducted_points, 0) as difference
from purchase_totals p
full join deduction_totals d on d.student_id = p.student_id
order by student_id;

-- 4) Verify exact existing purchase function signature.
select to_regprocedure(
  'public.purchase_marketplace_reward(uuid,uuid,uuid[])'
) as existing_purchase_function;
