-- Verify two concurrent identical final submissions create one reward only.
-- Disposable PostgreSQL only; run after the workflow launches both submissions.
DO $verify$
DECLARE
  tx_count integer;
  tx_points integer;
  attempt_count integer;
  attempt_score integer;
  attempt_status text;
BEGIN
  SELECT count(*), max(points)
  INTO tx_count, tx_points
  FROM public.point_transactions
  WHERE student_id='40000000-0000-0000-0000-000000000021'
    AND source='game';

  IF tx_count <> 1 OR tx_points <> 20 THEN
    RAISE EXCEPTION 'Concurrent final retry must create exactly one 20-point transaction; count %, points %',
      tx_count,tx_points;
  END IF;

  SELECT count(*), max(verified_score), max(status)
  INTO attempt_count, attempt_score, attempt_status
  FROM public.student_game_attempts
  WHERE session_id = (
    SELECT id FROM public.student_game_sessions
    WHERE session_token='10000000-0000-0000-0000-000000000021'
  );

  IF attempt_count <> 1 OR attempt_score <> 20 OR attempt_status <> 'completed' THEN
    RAISE EXCEPTION 'Concurrent final retry left unexpected attempt state: count %, score %, status %',
      attempt_count,attempt_score,attempt_status;
  END IF;

  RAISE NOTICE 'PASS: concurrent identical final submissions produce one completed attempt and one exact 20-point reward.';
END
$verify$;
