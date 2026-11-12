-- TEST-ONLY transaction prototypes. Not production authentication functions.

CREATE OR REPLACE FUNCTION rl_test.record_failure(
    p_code_fingerprint text,
    p_source_fingerprint text
)
-- TRUE means this failure was counted; FALSE means a cooldown blocked counting.
RETURNS boolean
LANGUAGE plpgsql
AS $function$
DECLARE
    v_bucket record;
    v_now timestamptz := clock_timestamp();
    v_new_count integer;
BEGIN
    IF p_code_fingerprint IS NULL OR p_source_fingerprint IS NULL
       OR p_code_fingerprint = '' OR p_source_fingerprint = '' THEN
        RAISE EXCEPTION 'Invalid test fingerprint';
    END IF;

    INSERT INTO rl_test.rate_limit_buckets (
        bucket_type, bucket_fingerprint
    )
    VALUES
        ('code_source', p_code_fingerprint),
        ('source', p_source_fingerprint)
    ON CONFLICT DO NOTHING;

    -- Lock both bucket rows in the same deterministic order for every caller.
    -- Do not make the cooldown decision using a timestamp captured before a possible lock wait.
    PERFORM 1
    FROM rl_test.rate_limit_buckets
    WHERE (bucket_type = 'code_source'
           AND bucket_fingerprint = p_code_fingerprint)
       OR (bucket_type = 'source'
           AND bucket_fingerprint = p_source_fingerprint)
    ORDER BY bucket_type, bucket_fingerprint
    FOR UPDATE;

    v_now := clock_timestamp();

    IF EXISTS (
        SELECT 1
        FROM rl_test.rate_limit_buckets
        WHERE ((bucket_type = 'code_source'
                AND bucket_fingerprint = p_code_fingerprint)
            OR (bucket_type = 'source'
                AND bucket_fingerprint = p_source_fingerprint))
          AND cooldown_until > v_now
    ) THEN
        RETURN false;
    END IF;

    FOR v_bucket IN
        SELECT bucket_type, bucket_fingerprint,
               failure_count, window_started_at
        FROM rl_test.rate_limit_buckets
        WHERE (bucket_type = 'code_source'
               AND bucket_fingerprint = p_code_fingerprint)
           OR (bucket_type = 'source'
               AND bucket_fingerprint = p_source_fingerprint)
        ORDER BY bucket_type, bucket_fingerprint
    LOOP
        IF v_bucket.window_started_at <= v_now - interval '5 minutes' THEN
            v_new_count := 1;
        ELSE
            v_new_count := v_bucket.failure_count + 1;
        END IF;

        UPDATE rl_test.rate_limit_buckets
        SET failure_count = v_new_count,
            window_started_at = CASE
                WHEN v_bucket.window_started_at <= v_now - interval '5 minutes'
                THEN v_now ELSE window_started_at END,
            cooldown_until = CASE
                WHEN v_new_count = 6 THEN v_now + interval '30 seconds'
                WHEN v_new_count = 7 THEN v_now + interval '1 minute'
                WHEN v_new_count = 8 THEN v_now + interval '5 minutes'
                WHEN v_new_count >= 9 THEN v_now + interval '15 minutes'
                ELSE NULL END,
            updated_at = v_now
        WHERE bucket_type = v_bucket.bucket_type
          AND bucket_fingerprint = v_bucket.bucket_fingerprint;
    END LOOP;

    RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION rl_test.create_portal_session(
    p_student_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
AS $function$
DECLARE
    v_student_active boolean;
    v_active_count integer;
    v_session_id uuid;
BEGIN
    -- Student-row lock serializes all session creation for this student.
    SELECT active INTO v_student_active
    FROM rl_test.students
    WHERE student_id = p_student_id
    FOR UPDATE;

    IF NOT FOUND OR v_student_active IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Student unavailable';
    END IF;

    UPDATE rl_test.portal_sessions
    SET revoked_at = clock_timestamp()
    WHERE student_id = p_student_id
      AND revoked_at IS NULL
      AND expires_at <= clock_timestamp();

    SELECT count(*) INTO v_active_count
    FROM rl_test.portal_sessions
    WHERE student_id = p_student_id
      AND revoked_at IS NULL
      AND expires_at > clock_timestamp();

    IF v_active_count >= 2 THEN
        UPDATE rl_test.portal_sessions
        SET revoked_at = clock_timestamp()
        WHERE session_id = (
            SELECT session_id
            FROM rl_test.portal_sessions
            WHERE student_id = p_student_id
              AND revoked_at IS NULL
              AND expires_at > clock_timestamp()
            ORDER BY created_at, session_id
            LIMIT 1
        );
    END IF;

    INSERT INTO rl_test.portal_sessions (student_id)
    VALUES (p_student_id)
    RETURNING session_id INTO v_session_id;

    RETURN v_session_id;
END;
$function$;
