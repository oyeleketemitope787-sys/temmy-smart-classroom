-- TEST-ONLY fixture for a disposable PostgreSQL 16 database.
-- Synthetic records only. Never apply this file to a hosted Supabase project.

CREATE SCHEMA rl_test;

CREATE TABLE rl_test.rate_limit_buckets (
    bucket_type text NOT NULL
        CHECK (bucket_type IN ('code_source', 'source')),
    bucket_fingerprint text NOT NULL,
    failure_count integer NOT NULL DEFAULT 0 CHECK (failure_count >= 0),
    window_started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    cooldown_until timestamptz,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (bucket_type, bucket_fingerprint)
);

CREATE TABLE rl_test.students (
    student_id uuid PRIMARY KEY,
    active boolean NOT NULL DEFAULT true
);

CREATE TABLE rl_test.portal_sessions (
    session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES rl_test.students(student_id),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL DEFAULT 'infinity'::timestamptz,
    revoked_at timestamptz
);

CREATE INDEX portal_sessions_student_active_idx
    ON rl_test.portal_sessions (student_id, created_at, session_id)
    WHERE revoked_at IS NULL;
