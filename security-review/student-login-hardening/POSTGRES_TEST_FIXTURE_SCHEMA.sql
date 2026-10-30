-- TEST-ONLY disposable PostgreSQL fixture. Synthetic schema/data only.
-- This file is used exclusively by the review-branch CI workflow.
-- It is not a Supabase migration and must never be applied to a hosted project.

CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;

CREATE TABLE public.teacher_profiles (
  id uuid PRIMARY KEY
);

CREATE TABLE public.classes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id uuid NOT NULL REFERENCES public.teacher_profiles(id),
  name text NOT NULL,
  description text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (teacher_id, name)
);

CREATE TABLE public.students (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES public.classes(id),
  first_name text NOT NULL,
  last_name text,
  student_code_hash text,
  student_code_hint text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.student_game_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id),
  class_id uuid NOT NULL REFERENCES public.classes(id),
  game_id text NOT NULL,
  session_token uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '30 minutes',
  used_at timestamptz
);

CREATE TABLE public.point_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id),
  teacher_id uuid NOT NULL REFERENCES public.teacher_profiles(id),
  points integer NOT NULL,
  action_name text NOT NULL,
  action_type text NOT NULL DEFAULT 'positive',
  reason text,
  source text NOT NULL DEFAULT 'teacher',
  created_at timestamptz NOT NULL DEFAULT now()
);
