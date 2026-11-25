-- Temmy Smart Classroom: route punctuality point changes through dual-balance accounting.
-- Apply only to the isolated temmy-smart-classroom-test project after review.
-- Replaces the legacy direct point_transactions inserts with the atomic,
-- idempotent Aggregate/Spendable points RPC.

begin;

create or replace function public.record_student_punctuality(
  p_class_id uuid,
  p_student_ids uuid[],
  p_status text,
  p_points integer,
  p_punctuality_date date default current_date
)
returns table(student_id uuid, status text, points_awarded integer, action text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_teacher_id uuid := auth.uid();
  v_student_id uuid;
  v_existing public.punctuality_records%rowtype;
  v_delta integer;
  v_action text;
  v_entries jsonb := '[]'::jsonb;
  v_student_count integer;
  v_distinct_count integer;
begin
  if v_teacher_id is null then
    raise exception 'Teacher authentication required';
  end if;

  if p_class_id is null or p_punctuality_date is null
     or p_status is null or p_points is null
     or p_student_ids is null or cardinality(p_student_ids) = 0 then
    raise exception 'Class, date, status, points and at least one student are required';
  end if;

  if p_status not in ('On Time','Late','Absent','Excused') then
    raise exception 'Invalid punctuality status';
  end if;

  if p_points < 0 then
    raise exception 'Points cannot be negative';
  end if;

  select count(*), count(distinct x.student_id)
    into v_student_count, v_distinct_count
  from unnest(p_student_ids) as x(student_id);

  if v_student_count <> v_distinct_count then
    raise exception 'A student may appear only once in a punctuality request';
  end if;

  -- Serialize punctuality changes for this class. This also closes the
  -- absent-row race before the unique student/class/date record is inserted.
  perform 1
  from public.classes c
  where c.id = p_class_id
    and c.teacher_id = v_teacher_id
    and c.active is true
  for update;

  if not found then
    raise exception 'The active class does not belong to the signed-in teacher';
  end if;

  foreach v_student_id in array p_student_ids
  loop
    perform 1
    from public.students s
    where s.id = v_student_id
      and s.class_id = p_class_id
      and s.active is true
    for update;

    if not found then
      raise exception 'Student does not belong to the selected active class';
    end if;

    select *
      into v_existing
    from public.punctuality_records pr
    where pr.student_id = v_student_id
      and pr.class_id = p_class_id
      and pr.punctuality_date = p_punctuality_date
    for update;

    if not found then
      insert into public.punctuality_records (
        student_id, class_id, teacher_id, punctuality_date, status, points_awarded
      )
      values (
        v_student_id, p_class_id, v_teacher_id,
        p_punctuality_date, p_status, p_points
      );

      v_delta := p_points;
      v_action := 'recorded';

      if v_delta <> 0 then
        v_entries := v_entries || jsonb_build_array(jsonb_build_object(
          'student_id', v_student_id,
          'points', v_delta,
          'action_name', 'Punctuality',
          'action_type', 'positive',
          'reason', 'Punctuality: ' || p_status,
          'source', 'teacher'
        ));
      end if;
    else
      v_delta := p_points - v_existing.points_awarded;

      update public.punctuality_records
      set teacher_id = v_teacher_id,
          status = p_status,
          points_awarded = p_points
      where id = v_existing.id;

      if v_delta <> 0 then
        v_entries := v_entries || jsonb_build_array(jsonb_build_object(
          'student_id', v_student_id,
          'points', v_delta,
          'action_name', 'Punctuality Adjustment',
          'action_type', case when v_delta > 0 then 'positive' else 'negative' end,
          'reason', 'Punctuality changed to ' || p_status,
          'source', 'teacher'
        ));
        v_action := 'updated';
      else
        v_action := 'unchanged';
      end if;
    end if;

    student_id := v_student_id;
    status := p_status;
    points_awarded := p_points;
    action := v_action;
    return next;
  end loop;

  -- The RPC call participates in this transaction. If it rejects a negative
  -- Spendable balance or any other invalid entry, all punctuality changes above
  -- are rolled back as well.
  if jsonb_array_length(v_entries) > 0 then
    perform public.record_student_point_transactions(
      gen_random_uuid(),
      p_class_id,
      v_entries
    );
  end if;
end;
$function$;

commit;
