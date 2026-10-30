-- Prepare a synthetic attempt at its final question for concurrent retry testing.
-- Disposable PostgreSQL only; run after smoke and edge-case scripts.
DO $setup$
DECLARE
  q jsonb := '[]'::jsonb;
  r jsonb;
  i integer;
  token uuid := '10000000-0000-0000-0000-000000000021';
BEGIN
  INSERT INTO public.students(id,class_id,first_name,last_name)
  VALUES ('40000000-0000-0000-0000-000000000021',
          '30000000-0000-0000-0000-000000000001','Concurrent','Final');

  INSERT INTO public.student_game_sessions(student_id,class_id,game_id,session_token)
  VALUES ('40000000-0000-0000-0000-000000000021',
          '30000000-0000-0000-0000-000000000001',
          'ci-one-point-game',token);

  FOR i IN 0..19 LOOP
    q := q || jsonb_build_array(jsonb_build_object(
      'question_index',i,'prompt','Concurrent question '||i,
      'options',jsonb_build_array('A','B','C','D'),
      'hint',null,'correct_choice_index',0
    ));
  END LOOP;

  r := public.begin_game_attempt(token,'ci-one-point-game','practice',q);
  IF r->>'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Concurrent attempt failed to start: %',r;
  END IF;

  FOR i IN 0..18 LOOP
    r := public.record_game_attempt_answer(token,'ci-one-point-game',i::smallint,0::smallint);
    IF r->>'ok' IS DISTINCT FROM 'true' OR r->>'status' IS DISTINCT FROM 'in_progress' THEN
      RAISE EXCEPTION 'Could not prepare question % for concurrency test: %',i,r;
    END IF;
  END LOOP;
END
$setup$;
