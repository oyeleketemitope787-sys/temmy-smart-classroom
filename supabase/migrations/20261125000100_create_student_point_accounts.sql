-- Temmy Smart Classroom: additive Aggregate/Spendable account foundation
-- Target branch: cloud-test
-- REVIEW ONLY: do not run against Supabase until reviewed and tested in an isolated project.
-- Historical opening balances are derived from each student's existing signed ledger.
-- Marketplace deductions reduce Spendable only; every other legacy transaction
-- contributes its signed value to both balances.

begin;

create table public.student_point_accounts (
  student_id uuid primary key
    references public.students(id) on delete cascade,
  aggregate_points bigint not null default 0,
  spendable_points bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint student_point_accounts_spendable_nonnegative
    check (spendable_points >= 0)
);

comment on table public.student_point_accounts is
  'Server-maintained point summaries. Aggregate and Spendable are distinct; do not write from clients.';
comment on column public.student_point_accounts.aggregate_points is
  'Achievement total. Marketplace purchases do not reduce this balance.';
comment on column public.student_point_accounts.spendable_points is
  'Available marketplace balance. Purchases and ordinary signed point adjustments affect this balance.';

-- Keep this table inaccessible to browser roles. Approved SECURITY DEFINER
-- functions will be the only application interface for reading/changing it.
alter table public.student_point_accounts enable row level security;
revoke all on table public.student_point_accounts from anon, authenticated;

-- Backfill each student independently. ON CONFLICT DO NOTHING makes a retry
-- non-destructive: it never overwrites an account already initialized by
-- a later trusted points operation.
insert into public.student_point_accounts (
  student_id,
  aggregate_points,
  spendable_points
)
select
  s.id,
  coalesce(sum(pt.points) filter (
    where pt.action_type is distinct from 'marketplace_purchase'
  ), 0)::bigint,
  coalesce(sum(pt.points), 0)::bigint
from public.students s
left join public.point_transactions pt
  on pt.student_id = s.id
group by s.id
on conflict (student_id) do nothing;

-- Fail the migration transaction if any opening Spendable balance is negative.
do $$
begin
  if exists (
    select 1
    from public.student_point_accounts
    where spendable_points < 0
  ) then
    raise exception
      'Points backfill stopped: at least one student has a negative Spendable balance. Reconcile before proceeding.';
  end if;
end;
$$;

commit;
