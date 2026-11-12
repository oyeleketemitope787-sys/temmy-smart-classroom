-- Assertions after three simultaneous session-creation transactions.
DO $tests$
DECLARE
    v_total integer;
    v_active integer;
    v_revoked integer;
BEGIN
    SELECT count(*),
           count(*) FILTER (WHERE revoked_at IS NULL AND expires_at > now()),
           count(*) FILTER (WHERE revoked_at IS NOT NULL)
    INTO v_total, v_active, v_revoked
    FROM rl_test.portal_sessions
    WHERE student_id = '11111111-1111-4111-8111-111111111111';

    IF v_total <> 3 OR v_active <> 2 OR v_revoked <> 1 THEN
        RAISE EXCEPTION 'Two-session limit failed: total %, active %, revoked %',
            v_total, v_active, v_revoked;
    END IF;

    RAISE NOTICE 'PASS: three concurrent logins leave exactly two active sessions';
END
$tests$;
