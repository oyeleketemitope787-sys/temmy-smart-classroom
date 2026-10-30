-- Security and edge-case integration tests. Disposable PostgreSQL only.
-- Requires POSTGRES_CENTRAL_SCORING_SMOKE_TESTS.sql to have run first.
-- All records are synthetic. Raises on any failed assertion.
DO $edge$
DECLARE
  r jsonb;
  q jsonb := '[]'::jsonb;
  i integer;
  tx_count integer;
  expired_token uuid := '10000000-0000-0000-0000-000000000011';
  used_token uuid := '10000000-0000-0000-0000-000000000012';
  order_token uuid := '10000000-0000-0000-0000-000000000013';
  challenge_token uuid := '10000000-0000-0000-0000-000000000014';
BEGIN
  INSERT INTO public.students(id, class_id, first_name, last_name)
  VALUES
    ('40000000-0000-0000-0000-000000000011','30000000-0000-0000-0000-000000000001','Edge','Expired'),
    ('40000000-0000-0000-0000-000000000012','30000000-0000-0000-0000-000000000001','Edge','Used'),
    ('40000000-0000-0000-0000-000000000013','30000000-0000-0000-0000-000000000001','Edge','Order'),
    ('40000000-0000-0000-0000-000000000014','30000000-0000-0000-0000-000000000001','Edge','Challenge');

  INSERT INTO public.student_game_sessions(student_id,class_id,game_id,session_token,expires_at,used_at)
  VALUES
    ('40000000-0000-0000-0000-000000000011','30000000-0000-0000-0000-000000000001','ci-one-point-game',expired_token,now()-interval '1 minute',NULL),
    ('40000000-0000-0000-0000-000000000012','30000000-0000-0000-0000-000000000001','ci-one-point-game',used_token,now()+interval '30 minutes',now()),
    ('40000000-0000-0000-0000-000000000013','30000000-0000-0000-0000-000000000001','ci-one-point-game',order_token,now()+interval '30 minutes',NULL),
    ('40000000-0000-0000-0000-000000000014','30000000-0000-0000-0000-000000000001','grade3-temmy-number-challenge',challenge_token,now()+interval '30 minutes',NULL);

  -- Expired and already-consumed sessions cannot start new attempts.
  r := public.begin_game_attempt(expired_token,'ci-one-point-game','practice','[]'::jsonb);
  IF r->>'ok' IS DISTINCT FROM 'false' OR r->>'error' IS DISTINCT FROM 'invalid_session' THEN
    RAISE EXCEPTION 'Expired session was not rejected: %', r;
  END IF;

  r := public.begin_game_attempt(used_token,'ci-one-point-game','practice','[]'::jsonb);
  IF r->>'ok' IS DISTINCT FROM 'false' OR r->>'error' IS DISTINCT FROM 'invalid_session' THEN
    RAISE EXCEPTION 'Used session was not rejected: %', r;
  END IF;

  -- Build a trusted 20-question set for ordering and retry checks.
  FOR i IN 0..19 LOOP
    q := q || jsonb_build_array(jsonb_build_object(
      'question_index',i,'prompt','Edge question '||i,
      'options',jsonb_build_array('A','B','C','D'),
      'hint',null,'correct_choice_index',0
    ));
  END LOOP;

  r := public.begin_game_attempt(order_token,'ci-one-point-game','practice',q);
  IF r->>'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Ordering test attempt failed to start: %',r;
  END IF;

  r := public.record_game_attempt_answer(order_token,'ci-one-point-game',1::smallint,0::smallint);
  IF r->>'ok' IS DISTINCT FROM 'false' OR r->>'error' IS DISTINCT FROM 'unexpected_question' THEN
    RAISE EXCEPTION 'Out-of-order answer was not rejected: %',r;
  END IF;

  r := public.record_game_attempt_answer(order_token,'ci-one-point-game',0::smallint,0::smallint);
  IF r->>'ok' IS DISTINCT FROM 'true' OR r->>'status' IS DISTINCT FROM 'in_progress' THEN
    RAISE EXCEPTION 'First ordered answer failed: %',r;
  END IF;

  r := public.record_game_attempt_answer(order_token,'ci-one-point-game',0::smallint,1::smallint);
  IF r->>'ok' IS DISTINCT FROM 'false' OR r->>'error' IS DISTINCT FROM 'answer_conflict' THEN
    RAISE EXCEPTION 'Conflicting duplicate answer was not rejected: %',r;
  END IF;

  -- Challenge mode must complete immediately on the third incorrect answer,
  -- preserve the exact score earned, consume the session and award once.
  q := '[]'::jsonb;
  FOR i IN 0..14 LOOP
    q := q || jsonb_build_array(jsonb_build_object(
      'question_index',i,'prompt','Challenge question '||i,
      'options',jsonb_build_array('A','B','C','D'),
      'hint',null,'correct_choice_index',0
    ));
  END LOOP;

  r := public.begin_game_attempt(challenge_token,'grade3-temmy-number-challenge','challenge',q);
  IF r->>'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Challenge attempt failed to start: %',r;
  END IF;

  FOR i IN 0..2 LOOP
    r := public.record_game_attempt_answer(
      challenge_token,'grade3-temmy-number-challenge',i::smallint,1::smallint
    );
    IF r->>'ok' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Challenge incorrect answer % failed: %',i,r;
    END IF;
  END LOOP;

  IF r->>'status' IS DISTINCT FROM 'completed'
     OR (r->>'score')::integer <> 0
     OR (r->>'max_score')::integer <> 41
     OR (r->>'points_awarded')::integer <> 0
     OR (r->>'lives_remaining')::integer <> 0 THEN
    RAISE EXCEPTION 'Third incorrect answer did not complete at exact score: %',r;
  END IF;

  SELECT count(*) INTO tx_count
  FROM public.point_transactions
  WHERE student_id='40000000-0000-0000-0000-000000000014' AND source='game';
  IF tx_count <> 1 THEN
    RAISE EXCEPTION 'Early challenge completion should create exactly one reward record; got %',tx_count;
  END IF;

  RAISE NOTICE 'PASS: expired/used sessions rejected; out-of-order/conflicting answers rejected; third challenge miss completes once at exact score.';
END
$edge$;
