-- Integration smoke tests against disposable PostgreSQL only.
-- All records are synthetic. Raises an exception on any failed assertion.
DO $test$
DECLARE
  q jsonb;
  r jsonb;
  i integer;
  token_20 uuid := '10000000-0000-0000-0000-000000000001';
  token_41 uuid := '10000000-0000-0000-0000-000000000002';
  attempt_id uuid;
  tx_count integer;
  tx_points integer;
BEGIN
  INSERT INTO public.teacher_profiles(id)
  VALUES ('20000000-0000-0000-0000-000000000001');

  INSERT INTO public.classes(id, teacher_id, name)
  VALUES ('30000000-0000-0000-0000-000000000001',
          '20000000-0000-0000-0000-000000000001', 'CI Synthetic Class');

  INSERT INTO public.students(id, class_id, first_name, last_name)
  VALUES
    ('40000000-0000-0000-0000-000000000001',
     '30000000-0000-0000-0000-000000000001', 'Synthetic', 'Sixteen'),
    ('40000000-0000-0000-0000-000000000002',
     '30000000-0000-0000-0000-000000000001', 'Synthetic', 'FortyOne');

  INSERT INTO public.student_game_sessions(
    student_id, class_id, game_id, session_token
  ) VALUES
    ('40000000-0000-0000-0000-000000000001',
     '30000000-0000-0000-0000-000000000001',
     'ci-one-point-game', token_20),
    ('40000000-0000-0000-0000-000000000002',
     '30000000-0000-0000-0000-000000000001',
     'grade3-temmy-number-challenge', token_41);

  INSERT INTO public.game_scoring_catalogue
    (game_id, rule_version, display_name, question_count, max_score, active)
  VALUES
    ('ci-one-point-game', 'one-point-per-correct-v1',
     'CI One Point Game', 20, 20, true);

  -- 20-question game: 16 correct answers must award exactly 16 points.
  q := '[]'::jsonb;
  FOR i IN 0..19 LOOP
    q := q || jsonb_build_array(jsonb_build_object(
      'question_index', i,
      'prompt', 'Synthetic question ' || i,
      'options', jsonb_build_array('A', 'B', 'C', 'D'),
      'hint', null,
      'correct_choice_index', 0
    ));
  END LOOP;

  r := public.begin_game_attempt(token_20, 'ci-one-point-game', 'practice', q);
  IF r->>'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION '20-point game attempt did not begin: %', r;
  END IF;

  FOR i IN 0..19 LOOP
    r := public.record_game_attempt_answer(
      token_20, 'ci-one-point-game', i::smallint,
      CASE WHEN i < 16 THEN 0 ELSE 1 END::smallint
    );
    IF r->>'ok' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION '20-point game answer % failed: %', i, r;
    END IF;
  END LOOP;

  IF r->>'status' <> 'completed'
     OR (r->>'score')::integer <> 16
     OR (r->>'max_score')::integer <> 20
     OR (r->>'points_awarded')::integer <> 16 THEN
    RAISE EXCEPTION 'Expected 16/20 and 16 points, got %', r;
  END IF;

  SELECT count(*), max(points)
  INTO tx_count, tx_points
  FROM public.point_transactions
  WHERE student_id = '40000000-0000-0000-0000-000000000001'
    AND source = 'game';

  IF tx_count <> 1 OR tx_points <> 16 THEN
    RAISE EXCEPTION 'Expected exactly one 16-point transaction; count %, points %',
      tx_count, tx_points;
  END IF;

  -- Replaying the final identical answer must return the stored completion
  -- and must not create a second reward transaction.
  r := public.record_game_attempt_answer(
    token_20, 'ci-one-point-game', 19::smallint, 1::smallint
  );
  IF r->>'ok' IS DISTINCT FROM 'true'
     OR r->>'duplicate' IS DISTINCT FROM 'true'
     OR (r->>'points_awarded')::integer <> 16 THEN
    RAISE EXCEPTION 'Identical final-answer retry was not idempotent: %', r;
  END IF;

  SELECT count(*) INTO tx_count
  FROM public.point_transactions
  WHERE student_id = '40000000-0000-0000-0000-000000000001'
    AND source = 'game';
  IF tx_count <> 1 THEN
    RAISE EXCEPTION 'Duplicate retry created extra reward transaction: %', tx_count;
  END IF;

  -- Number Challenge v1: all 15 correct answers must produce 41/41.
  q := '[]'::jsonb;
  FOR i IN 0..14 LOOP
    q := q || jsonb_build_array(jsonb_build_object(
      'question_index', i,
      'prompt', 'Synthetic Number Challenge question ' || i,
      'options', jsonb_build_array('A', 'B', 'C', 'D'),
      'hint', null,
      'correct_choice_index', 0
    ));
  END LOOP;

  r := public.begin_game_attempt(
    token_41, 'grade3-temmy-number-challenge', 'practice', q
  );
  IF r->>'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Number Challenge attempt did not begin: %', r;
  END IF;

  FOR i IN 0..14 LOOP
    r := public.record_game_attempt_answer(
      token_41, 'grade3-temmy-number-challenge',
      i::smallint, 0::smallint
    );
    IF r->>'ok' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Number Challenge answer % failed: %', i, r;
    END IF;
  END LOOP;

  IF r->>'status' <> 'completed'
     OR (r->>'score')::integer <> 41
     OR (r->>'max_score')::integer <> 41
     OR (r->>'points_awarded')::integer <> 41 THEN
    RAISE EXCEPTION 'Expected Number Challenge 41/41 and 41 points, got %', r;
  END IF;

  SELECT count(*), max(points)
  INTO tx_count, tx_points
  FROM public.point_transactions
  WHERE student_id = '40000000-0000-0000-0000-000000000002'
    AND source = 'game';

  IF tx_count <> 1 OR tx_points <> 41 THEN
    RAISE EXCEPTION 'Expected exactly one 41-point transaction; count %, points %',
      tx_count, tx_points;
  END IF;

  RAISE NOTICE 'PASS: 16/20 awards 16; duplicate final retry awards once; Number Challenge 41/41 awards 41.';
END
$test$;
