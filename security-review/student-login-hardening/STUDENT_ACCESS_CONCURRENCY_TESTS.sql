-- Assertions after twenty concurrent calls against one code/source pair.
DO $tests$
DECLARE
    v_code_count integer;
    v_source_count integer;
    v_code_cooldown timestamptz;
    v_source_cooldown timestamptz;
BEGIN
    SELECT failure_count, cooldown_until
    INTO v_code_count, v_code_cooldown
    FROM rl_test.rate_limit_buckets
    WHERE bucket_type = 'code_source'
      AND bucket_fingerprint = 'same-code-source';

    SELECT failure_count, cooldown_until
    INTO v_source_count, v_source_cooldown
    FROM rl_test.rate_limit_buckets
    WHERE bucket_type = 'source'
      AND bucket_fingerprint = 'same-source';

    IF v_code_count <> 6 OR v_source_count <> 6 THEN
        RAISE EXCEPTION 'Lost/extra concurrent increments: code %, source %',
            v_code_count, v_source_count;
    END IF;

    IF v_code_cooldown <= clock_timestamp()
       OR v_source_cooldown <= clock_timestamp() THEN
        RAISE EXCEPTION 'Expected both buckets to be cooling down';
    END IF;

    RAISE NOTICE 'PASS: same-code/source concurrency produced exactly six counted failures';
END
$tests$;
