-- Sequential functional assertions for the test-only rate limiter.
-- TRUE means the failed attempt was counted; FALSE means an active cooldown blocked it.
DO $tests$
DECLARE
    i integer;
    counted boolean;
    v_count integer;
    v_cooldown timestamptz;
    v_remaining interval;
BEGIN
    FOR i IN 1..5 LOOP
        counted := rl_test.record_failure('functional-code-source', 'functional-source');
        IF counted IS DISTINCT FROM true THEN
            RAISE EXCEPTION 'Failure % should be counted before cooldown', i;
        END IF;
    END LOOP;

    counted := rl_test.record_failure('functional-code-source', 'functional-source');
    IF counted IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Sixth failure should be counted and initiate cooldown';
    END IF;

    counted := rl_test.record_failure('functional-code-source', 'functional-source');
    IF counted IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'Immediate request during first cooldown should be blocked';
    END IF;

    SELECT failure_count, cooldown_until - clock_timestamp()
    INTO v_count, v_remaining
    FROM rl_test.rate_limit_buckets
    WHERE bucket_type = 'code_source'
      AND bucket_fingerprint = 'functional-code-source';

    IF v_count <> 6 OR v_remaining <= interval '0 seconds'
       OR v_remaining > interval '30 seconds' THEN
        RAISE EXCEPTION 'Unexpected first cooldown: count %, remaining %',
            v_count, v_remaining;
    END IF;

    -- Simulate expiry without sleeping; preserve the same five-minute window.
    UPDATE rl_test.rate_limit_buckets
    SET cooldown_until = clock_timestamp() - interval '1 second'
    WHERE bucket_fingerprint IN ('functional-code-source', 'functional-source');

    counted := rl_test.record_failure('functional-code-source', 'functional-source');
    IF counted IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Seventh failure should be counted after cooldown expiry';
    END IF;

    SELECT failure_count, cooldown_until - clock_timestamp()
    INTO v_count, v_remaining
    FROM rl_test.rate_limit_buckets
    WHERE bucket_type = 'code_source'
      AND bucket_fingerprint = 'functional-code-source';

    IF v_count <> 7 OR v_remaining <= interval '0 seconds'
       OR v_remaining > interval '1 minute' THEN
        RAISE EXCEPTION 'Unexpected second cooldown: count %, remaining %',
            v_count, v_remaining;
    END IF;

    UPDATE rl_test.rate_limit_buckets
    SET cooldown_until = clock_timestamp() - interval '1 second'
    WHERE bucket_fingerprint IN ('functional-code-source', 'functional-source');

    counted := rl_test.record_failure('functional-code-source', 'functional-source');
    IF counted IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Eighth failure should be counted after cooldown expiry';
    END IF;

    SELECT failure_count, cooldown_until - clock_timestamp()
    INTO v_count, v_remaining
    FROM rl_test.rate_limit_buckets
    WHERE bucket_type = 'code_source'
      AND bucket_fingerprint = 'functional-code-source';

    IF v_count <> 8 OR v_remaining <= interval '0 seconds'
       OR v_remaining > interval '5 minutes' THEN
        RAISE EXCEPTION 'Unexpected third cooldown: count %, remaining %',
            v_count, v_remaining;
    END IF;

    UPDATE rl_test.rate_limit_buckets
    SET cooldown_until = clock_timestamp() - interval '1 second'
    WHERE bucket_fingerprint IN ('functional-code-source', 'functional-source');

    counted := rl_test.record_failure('functional-code-source', 'functional-source');
    IF counted IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Ninth failure should be counted after cooldown expiry';
    END IF;

    SELECT failure_count, cooldown_until - clock_timestamp()
    INTO v_count, v_remaining
    FROM rl_test.rate_limit_buckets
    WHERE bucket_type = 'code_source'
      AND bucket_fingerprint = 'functional-code-source';

    IF v_count <> 9 OR v_remaining <= interval '0 seconds'
       OR v_remaining > interval '15 minutes' THEN
        RAISE EXCEPTION 'Unexpected fourth cooldown: count %, remaining %',
            v_count, v_remaining;
    END IF;

    -- Expire the five-minute failure window and cooldown; next failure starts at one.
    UPDATE rl_test.rate_limit_buckets
    SET window_started_at = clock_timestamp() - interval '6 minutes',
        cooldown_until = clock_timestamp() - interval '1 second'
    WHERE bucket_fingerprint IN ('functional-code-source', 'functional-source');

    counted := rl_test.record_failure('functional-code-source', 'functional-source');
    IF counted IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Failure after window expiry should be counted';
    END IF;

    SELECT failure_count, cooldown_until
    INTO v_count, v_cooldown
    FROM rl_test.rate_limit_buckets
    WHERE bucket_type = 'code_source'
      AND bucket_fingerprint = 'functional-code-source';

    IF v_count <> 1 OR v_cooldown IS NOT NULL THEN
        RAISE EXCEPTION 'Five-minute window did not reset: count %, cooldown %',
            v_count, v_cooldown;
    END IF;

    RAISE NOTICE 'PASS: threshold escalation, active cooldown blocking, and window reset';
END
$tests$;
