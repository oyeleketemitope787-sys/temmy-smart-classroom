-- Temmy Smart Classroom: atomic, idempotent teacher point transactions
-- Target: cloud-test only. Review/test in an isolated Supabase project first.
-- This RPC handles non-marketplace teacher awards, deductions, undo and
-- activity-score adjustments. Marketplace purchases remain on their existing
-- RPC until that function is safely replaced with its full current definition.

begin;

create table public.student_point_operation_requests (
  teacher_id uuid not null references public.teacher_profiles(id) on delete cascade,
  request_id uuid not null,
  class_id uuid not null references public.classes(id) on delete cascade,
  payload jsonb not null,
  result jsonb,
  created_at timestamptz not null default now(),
  primary key (teacher_id, request_id)
);

alter table public.student_point_operation_requests enable row level security;
revoke all on table public.student_point_operation_requests from anon, authenticated;

create or replace function public.record_student_point_transactions(
  p_request_id uuid,
  p_class_id uuid,
  p_entries jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_teacher_id uuid := auth.uid();
  v_request public.student_point_operation_requests%rowtype;
  v_result jsonb;
  v_entry_count integer;
  v_distinct_count integer;
  v_student_count integer;
begin
  if v_teacher_id is null then
    raise exception 'Teacher authentication is required.';
  end if;
  if p_request_id is null or p_class_id is null then
    raise exception 'Request ID and class ID are required.';
  end if;
  if jsonb_typeof(p_entries) is distinct from 'array' then
    raise exception 'Point transactions must be supplied as a JSON array.';
  end if;
  if jsonb_array_length(p_entries) = 0 then
    raise exception 'At least one point transaction is required.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_entries) as e(
      student_id uuid,
      points integer,
      action_name text,
      action_type text,
      reason text,
      source text
    )
    where e.student_id is null
       or e.points is null
       or e.points = 0
       or nullif(btrim(e.action_name), '') is null
       or nullif(btrim(e.action_type), '') is null
       or nullif(btrim(e.reason), '') is null
       or nullif(btrim(e.source), '') is null
       or e.action_type = 'marketplace_purchase'
  ) then
    raise exception 'Each entry needs a student, non-zero points, action details and a non-marketplace action type.';
  end if;

  select count(*), count(distinct e.student_id)
    into v_entry_count, v_distinct_count
  from jsonb_to_recordset(p_entries) as e(student_id uuid);
  if v_entry_count <> v_distinct_count then
    raise exception 'A student may appear only once in a request.';
  end if;

  insert into public.student_point_operation_requests
    (teacher_id, request_id, class_id, payload)
  values
    (v_teacher_id, p_request_id, p_class_id, p_entries)
  on conflict (teacher_id, request_id) do nothing;

  select *
    into v_request
  from public.student_point_operation_requests
  where teacher_id = v_teacher_id
    and request_id = p_request_id
  for update;

  if v_request.class_id <> p_class_id or v_request.payload <> p_entries then
    raise exception 'This request ID has already been used with different transaction details.';
  end if;

  if v_request.result is not null then
    return v_request.result;
  end if;

  perform 1
  from public.classes c
  where c.id = p_class_id
    and c.teacher_id = v_teacher_id
    and c.active = true
  for update;
  if not found then
    raise exception 'The selected active class does not belong to this teacher.';
  end if;

  -- Lock every target student in deterministic order and verify class scope.
  perform 1
  from public.students s
  join (
    select distinct e.student_id
    from jsonb_to_recordset(p_entries) as e(student_id uuid)
  ) target on target.student_id = s.id
  where s.class_id = p_class_id
    and s.active IS TRUE
  order by s.id
  for update of s;

  get diagnostics v_student_count = row_count;
  if v_student_count <> v_entry_count then
    raise exception 'One or more selected students are inactive or do not belong to this class.';
  end if;

  -- Ensure account rows exist for legacy or newly-added students, then lock
  -- them in the same deterministic order.
  insert into public.student_point_accounts
    (student_id, aggregate_points, spendable_points)
  select
    s.id,
    coalesce(sum(pt.points) filter (
      where pt.action_type is distinct from 'marketplace_purchase'
    ), 0)::bigint,
    coalesce(sum(pt.points), 0)::bigint
  from public.students s
  join (
    select distinct e.student_id
    from jsonb_to_recordset(p_entries) as e(student_id uuid)
  ) target on target.student_id = s.id
  left join public.point_transactions pt on pt.student_id = s.id
  group by s.id
  on conflict (student_id) do nothing;

  perform 1
  from public.student_point_accounts a
  join (
    select distinct e.student_id
    from jsonb_to_recordset(p_entries) as e(student_id uuid)
  ) target on target.student_id = a.student_id
  order by a.student_id
  for update of a;

  if exists (
    select 1
    from jsonb_to_recordset(p_entries) as e(
      student_id uuid,
      points integer
    )
    join public.student_point_accounts a on a.student_id = e.student_id
    where a.spendable_points + e.points < 0
  ) then
    raise exception 'This transaction would make a student Spendable balance negative.';
  end if;

  insert into public.point_transactions (
    student_id, teacher_id, points, action_name,
    action_type, reason, source, created_at
  )
  select
    e.student_id, v_teacher_id, e.points, e.action_name,
    e.action_type, e.reason, e.source, now()
  from jsonb_to_recordset(p_entries) as e(
    student_id uuid,
    points integer,
    action_name text,
    action_type text,
    reason text,
    source text
  );

  update public.student_point_accounts a
  set aggregate_points = a.aggregate_points + e.points,
      spendable_points = a.spendable_points + e.points,
      updated_at = now()
  from jsonb_to_recordset(p_entries) as e(
    student_id uuid,
    points integer
  )
  where a.student_id = e.student_id;

  select jsonb_build_object(
    'success', true,
    'request_id', p_request_id,
    'processed_students', v_entry_count,
    'processed_at', now()
  ) into v_result;

  update public.student_point_operation_requests
  set result = v_result
  where teacher_id = v_teacher_id
    and request_id = p_request_id;

  return v_result;
end;
$function$;

revoke all on function public.record_student_point_transactions(uuid, uuid, jsonb)
  from public, anon;
grant execute on function public.record_student_point_transactions(uuid, uuid, jsonb)
  to authenticated;

commit;
