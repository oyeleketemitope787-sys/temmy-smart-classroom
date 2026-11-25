-- Temmy Smart Classroom: supplemental read-only points migration preflight
-- Run in Supabase SQL Editor. SELECT statements only; no data/schema changes.

-- 1) Exact structure and constraints for the idempotency table used by the
-- existing purchase_marketplace_reward(uuid, uuid, uuid[]) function.
select table_name, ordinal_position, column_name, data_type, udt_name,
       is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'marketplace_purchase_requests'
order by ordinal_position;

select t.relname as table_name, c.conname as constraint_name,
       c.contype as constraint_type,
       pg_get_constraintdef(c.oid, true) as definition
from pg_constraint c
join pg_class t on t.oid = c.conrelid
join pg_namespace n on n.oid = t.relnamespace
where n.nspname = 'public'
  and t.relname = 'marketplace_purchase_requests'
order by c.contype, c.conname;

-- 2) Classify existing point history before any balances are backfilled.
-- Aggregation only; no student-identifying information is returned.
select action_type, source, count(*) as transaction_count,
       count(*) filter (where points > 0) as positive_count,
       count(*) filter (where points < 0) as negative_count,
       coalesce(sum(points), 0) as signed_points_total,
       coalesce(sum(points) filter (where points > 0), 0) as positive_points_total,
       coalesce(sum(points) filter (where points < 0), 0) as negative_points_total
from public.point_transactions
group by action_type, source
order by action_type, source;

-- 3) Compare the purchase history with marketplace deduction transactions.
select
  (select count(*) from public.purchases) as purchase_rows,
  (select coalesce(sum(points_spent), 0) from public.purchases) as purchase_points_spent,
  (select count(*) from public.point_transactions
   where action_type = 'marketplace_purchase' and points < 0) as marketplace_deduction_rows,
  (select coalesce(sum(abs(points)), 0) from public.point_transactions
   where action_type = 'marketplace_purchase' and points < 0) as marketplace_deduction_points;

-- 4) Verify the exact existing purchase function signature.
select to_regprocedure(
  'public.purchase_marketplace_reward(uuid,uuid,uuid[])'
) as existing_purchase_function;
