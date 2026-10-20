-- READ-ONLY ONLY: student access-code call graph and execution grants
-- Review branch: security-review/student-login-hardening
-- This script does not change database objects, permissions, data, or secrets.
-- Run in Supabase SQL Editor only as a read-only inventory query.

WITH candidates AS (
  SELECT
    p.oid,
    n.nspname AS schema_name,
    p.proname AS function_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    p.prosecdef AS security_definer,
    p.provolatile AS volatility_code,
    p.proconfig AS function_settings,
    p.proacl AS function_acl,
    p.prosrc AS function_source,
    p.proargnames AS argument_names,
    pg_get_function_result(p.oid) AS result_type
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
    AND p.prokind = 'f'
    AND (
      COALESCE(p.prosrc, '') ILIKE '%verify_student_access_code%'
      OR COALESCE(p.prosrc, '') ILIKE '%student_access%'
      OR COALESCE(p.prosrc, '') ILIKE '%p_access_code%'
      OR COALESCE(array_to_string(p.proargnames, ','), '') ILIKE '%access_code%'
    )
),
expanded_grants AS (
  SELECT
    c.oid,
    CASE
      WHEN a.grantee = 0 THEN 'PUBLIC'
      ELSE pg_get_userbyid(a.grantee)
    END AS grantee,
    a.privilege_type,
    a.is_grantable
  FROM candidates c
  LEFT JOIN LATERAL aclexplode(
    COALESCE(c.function_acl, acldefault('f', c.oid::regrole::oid))
  ) a ON TRUE
)
SELECT
  c.schema_name,
  c.function_name,
  c.identity_arguments,
  c.result_type,
  CASE c.volatility_code
    WHEN 'i' THEN 'IMMUTABLE'
    WHEN 's' THEN 'STABLE'
    WHEN 'v' THEN 'VOLATILE'
    ELSE c.volatility_code::text
  END AS volatility,
  c.security_definer,
  c.function_settings AS proconfig,
  COALESCE(
    string_agg(
      DISTINCT eg.grantee || ':' || eg.privilege_type ||
      CASE WHEN eg.is_grantable THEN ' (grantable)' ELSE '' END,
      '; ' ORDER BY eg.grantee || ':' || eg.privilege_type ||
      CASE WHEN eg.is_grantable THEN ' (grantable)' ELSE '' END
    ) FILTER (WHERE eg.grantee IS NOT NULL),
    '(no explicit ACL entries; inspect default privileges)'
  ) AS execute_grants,
  c.function_source AS function_definition
FROM candidates c
LEFT JOIN expanded_grants eg ON eg.oid = c.oid
GROUP BY
  c.oid,
  c.schema_name,
  c.function_name,
  c.identity_arguments,
  c.result_type,
  c.volatility_code,
  c.security_definer,
  c.function_settings,
  c.function_source
ORDER BY c.schema_name, c.function_name, c.identity_arguments;

-- Important review notes:
-- 1. This is a broad candidate search, not proof that every match is student-facing.
-- 2. Review complete definitions for all matches. Dynamic SQL or indirect calls may not be found.
-- 3. PUBLIC/default privileges and explicit anon grants must be interpreted together.
-- 4. Do not execute any REVOKE/GRANT or migration as part of this audit.
