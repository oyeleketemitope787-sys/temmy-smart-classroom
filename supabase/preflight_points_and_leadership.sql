-- Temmy Smart Classroom: read-only Supabase implementation preflight
-- Run in Supabase SQL Editor against the existing project.
-- This script performs SELECTs only. It does not modify data or schema.

-- 1) Exact columns and types for the current points, marketplace, student and activity tables.
select
  table_name,
  ordinal_position,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'students',
    'classes',
    'teacher_profiles',
    'point_transactions',
    'purchases',
    'marketplace_rewards',
    'class_activities',
    'student_activity_records',
    'groups',
    'group_members'
  )
order by table_name, ordinal_position;

-- 2) Primary keys, foreign keys, unique constraints and check constraints.
select
  t.relname as table_name,
  c.conname as constraint_name,
  c.contype as constraint_type,
  pg_get_constraintdef(c.oid, true) as definition
from pg_constraint c
join pg_class t on t.oid = c.conrelid
join pg_namespace n on n.oid = t.relnamespace
where n.nspname = 'public'
  and t.relname in (
    'students','classes','teacher_profiles','point_transactions',
    'purchases','marketplace_rewards','class_activities',
    'student_activity_records','groups','group_members'
  )
order by t.relname, c.contype, c.conname;

-- 3) Row-level security state and policies for the same tables.
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  p.polname as policy_name,
  p.polcmd as command,
  pg_get_expr(p.polqual, p.polrelid) as using_expression,
  pg_get_expr(p.polwithcheck, p.polrelid) as with_check_expression,
  array(
    select r.rolname
    from pg_roles r
    where r.oid = any(p.polroles)
    order by r.rolname
  ) as roles
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policy p on p.polrelid = c.oid
where n.nspname = 'public'
  and c.relname in (
    'students','classes','teacher_profiles','point_transactions',
    'purchases','marketplace_rewards','class_activities',
    'student_activity_records','groups','group_members'
  )
order by c.relname, p.polname;

-- 4) Trigger definitions attached to the relevant tables.
select
  c.relname as table_name,
  t.tgname as trigger_name,
  pg_get_triggerdef(t.oid, true) as trigger_definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and not t.tgisinternal
  and c.relname in (
    'students','point_transactions','purchases',
    'marketplace_rewards','class_activities','student_activity_records'
  )
order by c.relname, t.tgname;

-- 5) Existing relevant function signatures and full definitions.
select
  p.oid::regprocedure as function_signature,
  p.prosecdef as security_definer,
  pg_get_function_result(p.oid) as return_type,
  pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (
    p.proname ilike '%point%'
    or p.proname ilike '%purchase%'
    or p.proname ilike '%marketplace%'
    or p.proname ilike '%student_activity%'
    or p.proname ilike '%leadership%'
    or p.proname ilike '%prefect%'
    or p.proname ilike '%captain%'
  )
order by p.proname, p.oid::regprocedure::text;

-- 6) Confirm the active schema objects and whether any earlier proposed migration
-- tables/functions already exist. This is a read-only existence check.
select
  to_regclass('public.student_point_accounts') as student_point_accounts,
  to_regclass('public.student_leadership_appointments') as student_leadership_appointments,
  to_regprocedure('public.purchase_marketplace_reward') as purchase_marketplace_reward;
