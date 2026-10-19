-- READ-ONLY AUDIT ONLY
-- Run in Supabase SQL Editor only when you are ready to inspect.
-- This script contains SELECT statements only: no CREATE/ALTER/INSERT/UPDATE/DELETE/GRANT/REVOKE.
-- Because TEST and production share this database, inspect the result before sharing it.
-- Do not include student access codes, hashes, or personal student records in screenshots.

-- 1) List public functions that explicitly name p_access_code, plus known helper/portal functions.
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  pg_get_function_result(p.oid) AS return_type,
  p.prosecdef AS security_definer,
  p.provolatile AS volatility,
  p.proconfig AS function_settings,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute,
  pg_get_userbyid(p.proowner) AS function_owner
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND (
    'p_access_code' = ANY (p.proargnames)
    OR p.proname IN (
      'verify_student_access_code',
      'student_portal_login',
      'generate_student_access_code',
      'get_student_game_sessions',
      'get_student_live_activities',
      'get_student_messages',
      'get_student_point_history',
      'mark_student_messages_read',
      'send_student_message',
      'start_student_game_session',
      'submit_student_activity'
    )
  )
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

-- 2) Read the exact definitions of functions from the same inventory.
-- The output may be long; if necessary, run this query for one function name at a time.
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND (
    'p_access_code' = ANY (p.proargnames)
    OR p.proname IN (
      'verify_student_access_code',
      'student_portal_login',
      'generate_student_access_code',
      'get_student_game_sessions',
      'get_student_live_activities',
      'get_student_messages',
      'get_student_point_history',
      'mark_student_messages_read',
      'send_student_message',
      'start_student_game_session',
      'submit_student_activity'
    )
  )
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

-- 3) Optional: list all explicit EXECUTE grants for those functions.
-- This supplements has_function_privilege above with grantor/grantee detail.
SELECT
  routine_schema,
  routine_name,
  specific_name,
  grantee,
  privilege_type,
  is_grantable
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN (
    'verify_student_access_code',
    'student_portal_login',
    'generate_student_access_code',
    'get_student_game_sessions',
    'get_student_live_activities',
    'get_student_messages',
    'get_student_point_history',
    'mark_student_messages_read',
    'send_student_message',
    'start_student_game_session',
    'submit_student_activity'
  )
ORDER BY routine_name, specific_name, grantee, privilege_type;
