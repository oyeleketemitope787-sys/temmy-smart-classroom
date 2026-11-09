/*
CLASSROOM TRANSACTION TEST FIXTURE — SYNTHETIC / DISPOSABLE ONLY
Version: 0.1 design draft
Related:
  security-review/student-login-hardening/CLASSROOM_TRANSACTION_TEST_SPECIFICATION_V1.0.md
  security-review/student-login-hardening/CLASSROOM_TRANSACTION_SQL_DESIGN_REVIEW_ONLY.sql.txt

WARNING:
- This file is for a fresh, disposable PostgreSQL database used by local/CI tests.
- NEVER execute against Supabase, production, cloud-test, or any shared database.
- NOT a Supabase migration. Do not place under supabase/migrations.
- Every table and column here is synthetic test design, not a verified copy of
  the hosted Classroom schema.
- It deliberately does not add UNIQUE(activity_id, student_id).
- It does not contain real student data, secrets, API keys, or hosted URLs.
*/

-- Test roles are intentionally isolated to this disposable database.
-- The CI job should create a fresh database for each run.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'temmy_gateway') THEN
    CREATE ROLE temmy_gateway NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'temmy_data_owner') THEN
    CREATE ROLE temmy_data_owner NOLOGIN;
  END IF;
END
$$;

CREATE SCHEMA classroom_test AUTHORIZATION temmy_data_owner;
REVOKE ALL ON SCHEMA classroom_test FROM PUBLIC;
GRANT USAGE ON SCHEMA classroom_test TO authenticated, temmy_gateway;

SET search_path = pg_catalog, classroom_test;

CREATE TABLE classroom_test.teacher_profiles (
  id uuid PRIMARY KEY,
  display_name text NOT NULL
);

CREATE TABLE classroom_test.classes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id uuid NOT NULL REFERENCES classroom_test.teacher_profiles(id),
  name text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  UNIQUE (teacher_id, name)
);

CREATE TABLE classroom_test.students (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES classroom_test.classes(id),
  first_name text NOT NULL,
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE classroom_test.class_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES classroom_test.classes(id),
  title text NOT NULL,
  max_score integer NOT NULL CHECK (max_score >= 0),
  active boolean NOT NULL DEFAULT true
);

-- Intentionally no UNIQUE(activity_id, student_id):
-- duplicate submission semantics are unresolved and must be tested separately.
CREATE TABLE classroom_test.student_activity_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id uuid REFERENCES classroom_test.class_activities(id),
  student_id uuid NOT NULL REFERENCES classroom_test.students(id),
  teacher_id uuid NOT NULL REFERENCES classroom_test.teacher_profiles(id),
  status text NOT NULL DEFAULT 'completed',
  points_awarded integer NOT NULL DEFAULT 0 CHECK (points_awarded >= 0),
  completed_at timestamptz,
  notes text,
  answer text
);

-- Signed ledger: positive credits, negative debits/reversals.
-- Reversal linkage is synthetic and enforces at most one reversal per original.
CREATE TABLE classroom_test.point_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES classroom_test.students(id),
  teacher_id uuid NOT NULL REFERENCES classroom_test.teacher_profiles(id),
  points integer NOT NULL CHECK (points <> 0),
  action_name text NOT NULL,
  action_type text NOT NULL,
  reason text,
  source text NOT NULL,
  reverses_transaction_id uuid UNIQUE
    REFERENCES classroom_test.point_transactions(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE classroom_test.marketplace_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id uuid NOT NULL REFERENCES classroom_test.teacher_profiles(id),
  name text NOT NULL,
  description text,
  price integer NOT NULL CHECK (price > 0),
  active boolean NOT NULL DEFAULT true,
  -- NULL = unlimited; otherwise finite non-negative remaining stock.
  stock integer CHECK (stock IS NULL OR stock >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Purchase snapshots preserve historical names even if a reward is later
-- renamed/deactivated. Do not cascade-delete purchase history with rewards.
CREATE TABLE classroom_test.purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE,
  student_id uuid NOT NULL REFERENCES classroom_test.students(id),
  teacher_id uuid NOT NULL REFERENCES classroom_test.teacher_profiles(id),
  reward_id uuid NOT NULL REFERENCES classroom_test.marketplace_rewards(id),
  reward_name_snapshot text NOT NULL,
  points_spent integer NOT NULL CHECK (points_spent > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- One request row per idempotency key. The function layer binds key to
-- actor + operation + canonical payload hash.
CREATE TABLE classroom_test.transaction_requests (
  request_id uuid PRIMARY KEY,
  actor_teacher_id uuid NOT NULL REFERENCES classroom_test.teacher_profiles(id),
  operation text NOT NULL,
  payload_hash text NOT NULL,
  status text NOT NULL CHECK (status IN ('processing', 'completed', 'rejected')),
  result_payload jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE TABLE classroom_test.transaction_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid REFERENCES classroom_test.transaction_requests(request_id),
  actor_teacher_id uuid NOT NULL REFERENCES classroom_test.teacher_profiles(id),
  operation text NOT NULL,
  target_student_id uuid REFERENCES classroom_test.students(id),
  outcome text NOT NULL,
  safe_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Server-side configurable award limit. The fixture seeds a test value only;
-- production value/authority remain undecided.
CREATE TABLE classroom_test.transaction_config (
  config_key text PRIMARY KEY,
  integer_value integer NOT NULL CHECK (integer_value > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO classroom_test.transaction_config(config_key, integer_value)
VALUES ('maximum_teacher_award', 100);

-- Data owner owns the synthetic tables. No browser role receives direct write
-- privileges here. Function grants are intentionally deferred to the separate
-- transaction-function design and ACL tests.
ALTER TABLE classroom_test.teacher_profiles OWNER TO temmy_data_owner;
ALTER TABLE classroom_test.classes OWNER TO temmy_data_owner;
ALTER TABLE classroom_test.students OWNER TO temmy_data_owner;
ALTER TABLE classroom_test.class_activities OWNER TO temmy_data_owner;
ALTER TABLE classroom_test.student_activity_records OWNER TO temmy_data_owner;
ALTER TABLE classroom_test.point_transactions OWNER TO temmy_data_owner;
ALTER TABLE classroom_test.marketplace_rewards OWNER TO temmy_data_owner;
ALTER TABLE classroom_test.purchases OWNER TO temmy_data_owner;
ALTER TABLE classroom_test.transaction_requests OWNER TO temmy_data_owner;
ALTER TABLE classroom_test.transaction_audit OWNER TO temmy_data_owner;
ALTER TABLE classroom_test.transaction_config OWNER TO temmy_data_owner;

REVOKE ALL ON ALL TABLES IN SCHEMA classroom_test FROM PUBLIC, anon, authenticated;
GRANT SELECT ON classroom_test.teacher_profiles,
                classroom_test.classes,
                classroom_test.students
TO authenticated;

-- Do not grant temmy_gateway direct table access yet. The function design must
-- decide whether SECURITY DEFINER owner access or narrowly scoped invoker
-- privileges best express the trust boundary.
