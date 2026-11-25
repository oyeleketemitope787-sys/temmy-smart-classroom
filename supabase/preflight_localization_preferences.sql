-- Temmy Smart Classroom: localization preference preflight
-- READ ONLY. Run only in the separately named temmy-smart-classroom-test project.
-- This script performs catalog/metadata SELECTs only. It creates or changes nothing.
-- Do not run against the production Supabase project.

-- 1. Confirm current database and schema context.
SELECT
  current_database() AS database_name,
  current_user AS executing_role,
  current_schema() AS current_schema,
  current_setting('server_version') AS postgres_version;

-- 2. Confirm target tables and any existing candidate preference columns.
SELECT
  table_schema,
  table_name,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('teacher_profiles', 'students', 'classes')
ORDER BY table_name, ordinal_position;

-- 3. Check whether a language registry or equivalent configuration table already exists.
SELECT
  table_schema,
  table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND (
    table_name ILIKE '%language%'
    OR table_name ILIKE '%locale%'
    OR table_name ILIKE '%translation%'
    OR table_name ILIKE '%time_zone%'
    OR table_name ILIKE '%timezone%'
  )
ORDER BY table_name;

-- 4. Constraints and indexes on the three preference-owner tables.
SELECT
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  cc.check_clause
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.check_constraints cc
  ON cc.constraint_schema = tc.constraint_schema
 AND cc.constraint_name = tc.constraint_name
WHERE tc.table_schema = 'public'
  AND tc.table_name IN ('teacher_profiles', 'students', 'classes')
ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name;

SELECT
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('teacher_profiles', 'students', 'classes')
ORDER BY tablename, indexname;

-- 5. RLS state and policies on the preference-owner tables.
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('teacher_profiles', 'students', 'classes')
  AND c.relkind = 'r'
ORDER BY c.relname;

SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('teacher_profiles', 'students', 'classes')
ORDER BY tablename, policyname;

-- 6. Table-level and column-level privileges for browser roles.
SELECT
  grantee,
  table_name,
  privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('teacher_profiles', 'students', 'classes')
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY table_name, grantee, privilege_type;

SELECT
  grantee,
  table_name,
  column_name,
  privilege_type
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name IN ('teacher_profiles', 'students', 'classes')
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY table_name, column_name, grantee, privilege_type;

-- 7. Exact existing student verification helper definition, owner, security mode,
--    search_path and effective EXECUTE ACL. Do not change this legacy helper here.
SELECT
  p.oid::regprocedure AS function_signature,
  pg_get_userbyid(p.proowner) AS function_owner,
  p.prosecdef AS security_definer,
  p.provolatile AS volatility,
  p.proconfig AS function_settings,
  pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  pg_get_function_result(p.oid) AS result_type,
  pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'verify_student_access_code'
ORDER BY p.oid::regprocedure::text;

SELECT
  p.oid::regprocedure AS function_signature,
  COALESCE(grantee.rolname, 'PUBLIC') AS grantee,
  acl.privilege_type,
  acl.is_grantable
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(
  COALESCE(p.proacl, acldefault('f', p.proowner))
) AS acl
LEFT JOIN pg_roles grantee ON grantee.oid = acl.grantee
WHERE n.nspname = 'public'
  AND p.proname = 'verify_student_access_code'
ORDER BY p.oid::regprocedure::text, grantee, acl.privilege_type;

-- 8. Detect existing functions that could collide with the proposed language RPC names.
SELECT
  p.oid::regprocedure AS function_signature,
  p.proname AS function_name,
  pg_get_userbyid(p.proowner) AS function_owner,
  p.prosecdef AS security_definer,
  p.proconfig AS function_settings,
  pg_get_function_result(p.oid) AS result_type
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'get_teacher_interface_language',
    'set_teacher_interface_language',
    'get_class_default_interface_language',
    'set_class_default_interface_language',
    'get_student_interface_language',
    'set_student_interface_language'
  )
ORDER BY p.proname, p.oid::regprocedure::text;

-- 9. Relevant Supabase roles and whether the expected roles exist.
SELECT
  rolname,
  rolsuper,
  rolcanlogin,
  rolinherit,
  rolbypassrls
FROM pg_roles
WHERE rolname IN ('anon', 'authenticated', 'service_role', 'postgres')
ORDER BY rolname;

-- 10. Verify representative IANA zones are present in PostgreSQL's time-zone catalog.
--     This is a read-only capability check, not a proposed persisted preference list.
SELECT
  name,
  abbrev,
  utc_offset,
  is_dst
FROM pg_timezone_names
WHERE name IN ('Asia/Muscat', 'Europe/London', 'Africa/Lagos')
ORDER BY name;

-- 11. Confirm the initial language registry does not already exist as a table
--     under a different common name; inspect matching public relations.
SELECT
  n.nspname AS schema_name,
  c.relname AS relation_name,
  c.relkind AS relation_kind
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'v', 'm')
  AND (
    c.relname ILIKE '%language%'
    OR c.relname ILIKE '%locale%'
    OR c.relname ILIKE '%translation%'
  )
ORDER BY c.relname;

-- End of read-only preflight.
