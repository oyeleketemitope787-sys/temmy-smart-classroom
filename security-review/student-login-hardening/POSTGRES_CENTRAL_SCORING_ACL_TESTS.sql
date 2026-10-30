-- Assert browser roles cannot execute privileged scoring functions or read
-- the server-held answer key. Run only in the disposable PostgreSQL CI database.
DO $acl$
BEGIN
  IF pg_catalog.has_function_privilege(
       'anon',
       'public.begin_game_attempt(uuid,text,text,jsonb)',
       'EXECUTE'
     )
     OR pg_catalog.has_function_privilege(
       'authenticated',
       'public.begin_game_attempt(uuid,text,text,jsonb)',
       'EXECUTE'
     )
     OR NOT pg_catalog.has_function_privilege(
       'service_role',
       'public.begin_game_attempt(uuid,text,text,jsonb)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'begin_game_attempt EXECUTE grants do not match backend-only policy';
  END IF;

  IF pg_catalog.has_function_privilege(
       'anon',
       'public.record_game_attempt_answer(uuid,text,smallint,smallint)',
       'EXECUTE'
     )
     OR pg_catalog.has_function_privilege(
       'authenticated',
       'public.record_game_attempt_answer(uuid,text,smallint,smallint)',
       'EXECUTE'
     )
     OR NOT pg_catalog.has_function_privilege(
       'service_role',
       'public.record_game_attempt_answer(uuid,text,smallint,smallint)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'record_game_attempt_answer EXECUTE grants do not match backend-only policy';
  END IF;

  IF pg_catalog.has_table_privilege('anon','public.student_game_attempt_questions','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','public.student_game_attempt_questions','SELECT')
     OR pg_catalog.has_table_privilege('anon','public.student_game_attempt_questions','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.student_game_attempt_questions','INSERT') THEN
    RAISE EXCEPTION 'Browser role has direct access to private attempt question table';
  END IF;

  IF NOT (
    SELECT c.relrowsecurity
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname='student_game_attempt_questions'
  ) THEN
    RAISE EXCEPTION 'RLS is not enabled on private attempt question table';
  END IF;

  RAISE NOTICE 'PASS: privileged scoring functions and private answer-key table are backend-only.';
END
$acl$;
