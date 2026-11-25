-- Temmy Smart Classroom
-- PostgreSQL-backed student localization rate limiter
-- TEST PROJECT ONLY. Review before applying.
-- This migration is intentionally separate from localization preference storage.
--
-- Security model:
--   * Edge Function computes HMAC-SHA-256 fingerprints; raw IP/access code never enter SQL.
--   * The Edge Function calls public.consume_student_language_rate_limit() using service_role.
--   * The RPC is SECURITY DEFINER and writes to a non-exposed private table.
--   * No browser role receives schema/table/function access.
--
-- Provisional TEST thresholds only; do not treat as production-approved:
--   source:     20 / 10 minutes, 100 / hour
--   credential: 5 / 10 minutes, 20 / hour
--
-- No scheduler is installed. Cleanup is a bounded, manually/scheduled invocation.

BEGIN;

CREATE SCHEMA private AUTHORIZATION postgres;

REVOKE ALL ON SCHEMA private FROM PUBLIC;
REVOKE ALL ON SCHEMA private FROM anon;
REVOKE ALL ON SCHEMA private FROM authenticated;
REVOKE ALL ON SCHEMA private FROM service_role;

CREATE TABLE private.student_language_rate_limits (
  scope text NOT NULL
    CHECK (scope IN ('source', 'credential')),
  key_fingerprint bytea NOT NULL
    CHECK (octet_length(key_fingerprint) = 32),
  window_seconds integer NOT NULL
    CHECK (window_seconds IN (600, 3600)),
  window_started_at timestamptz NOT NULL,
  attempts integer NOT NULL
    CHECK (attempts > 0),
  expires_at timestamptz NOT NULL,
  CONSTRAINT student_language_rate_limits_pkey
    PRIMARY KEY (scope, key_fingerprint, window_seconds, window_started_at)
);

CREATE INDEX student_language_rate_limits_expires_at_idx
  ON private.student_language_rate_limits (expires_at);

ALTER TABLE private.student_language_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.student_language_rate_limits FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE private.student_language_rate_limits FROM PUBLIC;
REVOKE ALL ON TABLE private.student_language_rate_limits FROM anon;
REVOKE ALL ON TABLE private.student_language_rate_limits FROM authenticated;
REVOKE ALL ON TABLE private.student_language_rate_limits FROM service_role;

-- PostgREST must expose public (or another approved API schema) for RPC calls.
-- This function is deliberately in public while its backing table remains private.
CREATE FUNCTION public.consume_student_language_rate_limit(
  p_source_fingerprint bytea,
  p_credential_fingerprint bytea
)
RETURNS TABLE (
  allowed boolean,
  retry_after_seconds integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_scope text;
  v_window integer;
  v_fingerprint bytea;
  v_limit integer;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_bucket timestamptz;
  v_attempts integer;
  v_retry integer := 0;
  v_blocked boolean := false;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;

  IF p_source_fingerprint IS NULL
     OR pg_catalog.octet_length(p_source_fingerprint) <> 32
     OR p_credential_fingerprint IS NULL
     OR pg_catalog.octet_length(p_credential_fingerprint) <> 32 THEN
    RAISE EXCEPTION 'invalid rate-limit fingerprint' USING ERRCODE = '22023';
  END IF;

  FOREACH v_scope IN ARRAY ARRAY['source', 'credential'] LOOP
    IF v_scope = 'source' THEN
      v_fingerprint := p_source_fingerprint;
    ELSE
      v_fingerprint := p_credential_fingerprint;
    END IF;

    FOREACH v_window IN ARRAY ARRAY[600, 3600] LOOP
      IF v_scope = 'source' AND v_window = 600 THEN
        v_limit := 20;
      ELSIF v_scope = 'source' AND v_window = 3600 THEN
        v_limit := 100;
      ELSIF v_scope = 'credential' AND v_window = 600 THEN
        v_limit := 5;
      ELSE
        v_limit := 20;
      END IF;

      v_bucket := pg_catalog.to_timestamp(
        pg_catalog.floor(
          pg_catalog.extract(epoch FROM v_now) / v_window
        ) * v_window
      );

      INSERT INTO private.student_language_rate_limits AS current_counter (
        scope, key_fingerprint, window_seconds,
        window_started_at, attempts, expires_at
      )
      VALUES (
        v_scope, v_fingerprint, v_window,
        v_bucket, 1,
        v_bucket + pg_catalog.make_interval(secs => v_window) + interval '1 day'
      )
      ON CONFLICT (scope, key_fingerprint, window_seconds, window_started_at)
      DO UPDATE SET
        attempts = current_counter.attempts + 1,
        expires_at = EXCLUDED.expires_at
      RETURNING current_counter.attempts
      INTO v_attempts;

      IF v_attempts > v_limit THEN
        v_blocked := true;
        v_retry := pg_catalog.greatest(
          v_retry,
          pg_catalog.ceil(
            pg_catalog.extract(
              epoch FROM (v_bucket + pg_catalog.make_interval(secs => v_window) - v_now)
            )
          )::integer
        );
      END IF;
    END LOOP;
  END LOOP;

  RETURN QUERY SELECT NOT v_blocked, v_retry;
END;
$function$;

ALTER FUNCTION public.consume_student_language_rate_limit(bytea, bytea)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.consume_student_language_rate_limit(bytea, bytea)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.consume_student_language_rate_limit(bytea, bytea)
  FROM anon;
REVOKE ALL ON FUNCTION public.consume_student_language_rate_limit(bytea, bytea)
  FROM authenticated;
GRANT EXECUTE ON FUNCTION public.consume_student_language_rate_limit(bytea, bytea)
  TO service_role;

-- Bounded cleanup. Invoke from a controlled maintenance process; do not run
-- an unbounded DELETE on every student request. The caller receives only a
-- deleted-row count, never keys or fingerprints.
CREATE FUNCTION public.cleanup_student_language_rate_limits(
  p_batch_size integer DEFAULT 500
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_deleted integer;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;

  IF p_batch_size IS NULL OR p_batch_size < 1 OR p_batch_size > 1000 THEN
    RAISE EXCEPTION 'batch size must be between 1 and 1000'
      USING ERRCODE = '22023';
  END IF;

  DELETE FROM private.student_language_rate_limits AS rate_limit
  WHERE rate_limit.ctid IN (
    SELECT expired.ctid
    FROM private.student_language_rate_limits AS expired
    WHERE expired.expires_at < pg_catalog.clock_timestamp()
    ORDER BY expired.expires_at
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  );

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$function$;

ALTER FUNCTION public.cleanup_student_language_rate_limits(integer)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.cleanup_student_language_rate_limits(integer)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cleanup_student_language_rate_limits(integer)
  FROM anon;
REVOKE ALL ON FUNCTION public.cleanup_student_language_rate_limits(integer)
  FROM authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_student_language_rate_limits(integer)
  TO service_role;

COMMIT;

-- Post-apply verification (run separately after review and explicit approval):
-- SELECT has_schema_privilege('anon', 'private', 'USAGE') AS anon_private_usage,
--        has_schema_privilege('authenticated', 'private', 'USAGE') AS auth_private_usage,
--        has_schema_privilege('service_role', 'private', 'USAGE') AS service_private_usage;
-- SELECT has_table_privilege('anon', 'private.student_language_rate_limits', 'SELECT') AS anon_table_read,
--        has_table_privilege('authenticated', 'private.student_language_rate_limits', 'SELECT') AS auth_table_read,
--        has_table_privilege('service_role', 'private.student_language_rate_limits', 'SELECT') AS service_table_read;
-- SELECT has_function_privilege('anon', 'public.consume_student_language_rate_limit(bytea,bytea)', 'EXECUTE') AS anon_limiter_exec,
--        has_function_privilege('authenticated', 'public.consume_student_language_rate_limit(bytea,bytea)', 'EXECUTE') AS auth_limiter_exec,
--        has_function_privilege('service_role', 'public.consume_student_language_rate_limit(bytea,bytea)', 'EXECUTE') AS service_limiter_exec;
-- Never test with real student access codes or production credentials.
