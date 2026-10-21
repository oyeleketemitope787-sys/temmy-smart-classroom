-- READ-ONLY ONLY: class, game, assignment, session, and result schema inventory
-- Purpose: inspect the existing model before designing searchable game assignment and durable completion.
-- This script reads catalog metadata only. It does not read student records or change data/schema/permissions.
-- Run in Supabase SQL Editor and share the output. Do not add test writes.

-- 1) Relevant table/view names and columns (names/types/nullability/defaults only).
SELECT
  c.table_schema,
  c.table_name,
  c.column_name,
  c.ordinal_position,
  c.data_type,
  c.udt_name,
  c.is_nullable,
  c.column_default
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND (
    c.table_name ILIKE '%class%'
    OR c.table_name ILIKE '%student%'
    OR c.table_name ILIKE '%game%'
    OR c.table_name ILIKE '%assign%'
    OR c.table_name ILIKE '%activity%'
    OR c.table_name ILIKE '%point%'
    OR c.table_name ILIKE '%result%'
    OR c.table_name ILIKE '%session%'
  )
ORDER BY c.table_name, c.ordinal_position;

-- 2) Foreign keys involving those tables; helps identify existing class/game/student relationships.
SELECT
  tc.table_schema,
  tc.table_name,
  kcu.column_name,
  ccu.table_schema AS referenced_schema,
  ccu.table_name AS referenced_table,
  ccu.column_name AS referenced_column,
  tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_schema = kcu.constraint_schema
 AND tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_schema = ccu.constraint_schema
 AND tc.constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
  AND (
    tc.table_name ILIKE '%class%'
    OR tc.table_name ILIKE '%student%'
    OR tc.table_name ILIKE '%game%'
    OR tc.table_name ILIKE '%assign%'
    OR tc.table_name ILIKE '%activity%'
    OR tc.table_name ILIKE '%point%'
    OR tc.table_name ILIKE '%result%'
    OR tc.table_name ILIKE '%session%'
    OR ccu.table_name ILIKE '%class%'
    OR ccu.table_name ILIKE '%student%'
    OR ccu.table_name ILIKE '%game%'
    OR ccu.table_name ILIKE '%assign%'
    OR ccu.table_name ILIKE '%activity%'
    OR ccu.table_name ILIKE '%point%'
    OR ccu.table_name ILIKE '%result%'
    OR ccu.table_name ILIKE '%session%'
  )
ORDER BY tc.table_name, kcu.ordinal_position;

-- 3) Candidate public functions and signatures related to games, assignments, sessions, and rewards.
-- Definitions are intentionally omitted here; inspect only the specific signatures returned.
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
  END AS volatility
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND (
    p.proname ILIKE '%game%'
    OR p.proname ILIKE '%assign%'
    OR p.proname ILIKE '%session%'
    OR p.proname ILIKE '%result%'
    OR p.proname ILIKE '%point%'
    OR p.proname ILIKE '%activity%'
  )
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

-- Safety: this is catalog-only inventory. Do not run any INSERT/UPDATE/DELETE/DDL/GRANT/REVOKE
-- during this review. No student names, access codes, session tokens, or point-history rows are queried.
