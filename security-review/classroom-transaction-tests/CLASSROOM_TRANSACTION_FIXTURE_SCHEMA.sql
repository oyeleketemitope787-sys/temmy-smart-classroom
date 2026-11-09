/*
CLASSROOM TRANSACTION TEST FIXTURE — SYNTHETIC / DISPOSABLE ONLY
Version: 0.2 role-isolated draft

Related:
  security-review/student-login-hardening/CLASSROOM_TRANSACTION_TEST_SPECIFICATION_V1.0.md
  security-review/student-login-hardening/CLASSROOM_TRANSACTION_SQL_DESIGN_REVIEW_ONLY.sql.txt
  security-review/classroom-transaction-tests/TRUSTED_ACTOR_IDENTITY_DESIGN.md

WARNING:
- Fresh disposable PostgreSQL database only. Never run against Supabase,
  production, cloud-test, or any shared database.
- NOT a Supabase migration. Do not place under supabase/migrations.
- Every table/column is synthetic test design, not verified hosted schema.
- No UNIQUE(activity_id, student_id) constraint is added.
- No real student data, credentials, or hosted URLs are included.
- Run as PostgreSQL superuser against a fresh disposable cluster/database.
  This script creates cluster-wide roles and switches to the non-login owner.
  It refuses to reuse pre-existing test role names.
*/

-- Role names are deliberately namespaced to avoid collision with Supabase's
-- standard anon/authenticated roles or other local projects.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname IN (
    'temmy_ctest_anon',
    'temmy_ctest_authenticated',
    'temmy_ctest_gateway',
    'temmy_ctest_data_owner'
  )) THEN
    RAISE EXCEPTION
      'A temmy_ctest role already exists in this PostgreSQL cluster. Stop and use a fresh disposable cluster; do not reuse or alter existing roles.';
  END IF;
END
$$;

CREATE ROLE temmy_ctest_anon
  NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT
  NOREPLICATION NOBYPASSRLS;
CREATE ROLE temmy_ctest_authenticated
  NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT
  NOREPLICATION NOBYPASSRLS;
CREATE ROLE temmy_ctest_gateway
  NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT
  NOREPLICATION NOBYPASSRLS;
CREATE ROLE temmy_ctest_data_owner
  NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT
  NOREPLICATION NOBYPASSRLS;

-- No membership is granted to either client role. In particular, neither
-- client role can SET ROLE to temmy_ctest_gateway.
CREATE SCHEMA classroom_test AUTHORIZATION temmy_ctest_data_owner;
REVOKE ALL ON SCHEMA classroom_test FROM PUBLIC;
GRANT USAGE ON SCHEMA classroom_test
  TO temmy_ctest_authenticated, temmy_ctest_gateway;

-- Create objects while acting as their non-login owner. The privileged
-- disposable test runner must be allowed to SET ROLE to this role.
SET ROLE temmy_ctest_data_owner;
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
-- duplicate submission semantics remain unresolved and must be tested.
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

-- Snapshot preserves purchase history after reward rename/deactivation.
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

-- A request key is bound by the function layer to actor, operation and payload.
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

CREATE TABLE classroom_test.transaction_config (
  config_key text PRIMARY KEY,
  integer_value integer NOT NULL CHECK (integer_value > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Test-only cap value; not a production recommendation.
INSERT INTO classroom_test.transaction_config(config_key, integer_value)
VALUES ('maximum_teacher_award', 100);

RESET ROLE;

-- No direct client writes. Table ownership remains temmy_ctest_data_owner.
REVOKE ALL ON ALL TABLES IN SCHEMA classroom_test
  FROM PUBLIC, temmy_ctest_anon, temmy_ctest_authenticated,
       temmy_ctest_gateway;

GRANT SELECT ON classroom_test.teacher_profiles,
                classroom_test.classes,
                classroom_test.students
TO temmy_ctest_authenticated;

-- No direct table privileges for the gateway role. Approved business
-- functions will be SECURITY DEFINER, owned by the non-login data owner,
-- and executable only by temmy_ctest_gateway after separate ACL tests.
