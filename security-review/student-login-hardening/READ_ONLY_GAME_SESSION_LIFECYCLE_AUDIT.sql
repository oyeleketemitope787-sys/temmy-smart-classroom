-- READ-ONLY ONLY: inspect exact game session lifecycle function definitions.
-- This query reads PostgreSQL catalog metadata only; it does not change data, schema, privileges, or secrets.
-- It returns function definitions for review, not student records or access codes.

SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  pg_get_function_result(p.oid) AS result_type,
  p.prosecdef AS security_definer,
  CASE p.provolatile
    WHEN 'i' THEN 'IMMUTABLE'
    WHEN 's' THEN 'STABLE'
    WHEN 'v' THEN 'VOLATILE'
    ELSE p.provolatile::text
  END AS volatility,
  p.proconfig AS function_settings,
  pg_get_userbyid(p.proowner) AS function_owner,
  p.prosrc AS function_definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND p.proname IN (
    'start_teacher_game_session',
    'start_student_game_session',
    'get_student_game_sessions',
    'record_student_game_result'
  )
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

-- Review questions for the returned definitions:
-- 1. Does get_student_game_sessions filter by expires_at, used_at, or both?
-- 2. Is there a durable assignment identifier independent of the session row?
-- 3. Can a completed student/game assignment receive a new session?
-- 4. Does record_student_game_result atomically mark the session used and award points once?
-- 5. Does session creation validate game IDs against an approved catalogue?
--
-- Safety: do not add test writes, GRANT/REVOKE, DDL, or migration statements to this query.
