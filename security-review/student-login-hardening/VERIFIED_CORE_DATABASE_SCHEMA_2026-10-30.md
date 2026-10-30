# Verified Core Database Schema — Central Scoring Review

**Status:** Read-only metadata verified from owner-supplied Supabase SQL Editor output, 2026-10-30.
**Branch:** `security-review/student-login-hardening`
**Scope:** Documentation only. No SQL was executed against Supabase; no database, permissions, secrets, deployment, or production changes were made.

## Authentication

### `public.student_access`

Verified columns:

| Column | Type | Nullable | Default |
|---|---|---:|---|
| id | uuid | no | gen_random_uuid() |
| student_id | uuid | no | — |
| code_hash | text | no | — |
| code_last_generated_at | timestamptz | yes | — |
| last_login_at | timestamptz | yes | — |
| active | boolean | no | true |
| created_at | timestamptz | no | now() |
| updated_at | timestamptz | no | now() |

Verified constraints/indexes:
- Primary key on `id`.
- Foreign key `student_id -> students(id)`.
- Unique `student_id` (one access record per student).

The existing `verify_student_access_code(text)` function reads `student_access.code_hash`, checks `student_access.active` and `students.active`, and verifies the supplied code using `extensions.crypt()`. It is SECURITY DEFINER, owned by postgres, configured with `search_path=public`; direct EXECUTE is denied to anon and allowed to authenticated in the supplied ACL output. Do not expose `code_hash` to client roles.

## Students and classes

### `public.students`

Verified columns:
- `id uuid NOT NULL DEFAULT gen_random_uuid()`
- `class_id uuid NOT NULL`
- `first_name text NOT NULL`
- `last_name text NULL`
- `student_code_hash text NULL`
- `student_code_hint text NULL`
- `active boolean NOT NULL DEFAULT true`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

Verified primary key on `id`; foreign key `class_id -> classes(id)`.

### `public.classes`

Verified columns:
- `id uuid NOT NULL DEFAULT gen_random_uuid()`
- `teacher_id uuid NOT NULL`
- `name text NOT NULL`
- `description text NULL`
- `active boolean NOT NULL DEFAULT true`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

Verified primary key on `id`; foreign key `teacher_id -> teacher_profiles(id)`; unique `(teacher_id, name)`.

## Game sessions

### `public.student_game_sessions`

Verified columns:
- `id uuid NOT NULL DEFAULT gen_random_uuid()`
- `student_id uuid NOT NULL`
- `class_id uuid NOT NULL`
- `game_id text NOT NULL`
- `session_token uuid NOT NULL DEFAULT gen_random_uuid()`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `expires_at timestamptz NOT NULL DEFAULT now() + interval '30 minutes'`
- `used_at timestamptz NULL`

Verified primary key on `id`; unique `session_token`. No trigger was returned by the supplied trigger inventory for this table.

## Rewards

### `public.point_transactions`

Verified columns:
- `id uuid NOT NULL DEFAULT gen_random_uuid()`
- `student_id uuid NOT NULL`
- `teacher_id uuid NOT NULL`
- `points integer NOT NULL`
- `action_name text NOT NULL`
- `action_type text NOT NULL DEFAULT 'positive'`
- `reason text NULL`
- `source text NOT NULL DEFAULT 'teacher'`
- `created_at timestamptz NOT NULL DEFAULT now()`

Verified primary key on `id`; foreign keys to `students(id)` and `teacher_profiles(id)`. No trigger was returned by the supplied trigger inventory for this table. The supplied metadata does not establish a lower bound/check constraint for `points`, nor an attempt-level idempotency key.

## Student activities

### `public.student_activity_records`

Verified columns:
- `id uuid NOT NULL DEFAULT gen_random_uuid()`
- `activity_id uuid NULL`
- `student_id uuid NOT NULL`
- `teacher_id uuid NOT NULL`
- `status text NOT NULL DEFAULT 'completed'`
- `points_awarded integer NOT NULL DEFAULT 0`
- `completed_at timestamptz NOT NULL DEFAULT now()`
- `notes text NULL`
- `answer text NULL`

Verified primary key on `id`; foreign keys to `class_activities(id)`, `students(id)`, and `teacher_profiles(id)`. No trigger was returned by the supplied trigger inventory for this table. No unique constraint on `(activity_id, student_id)` was returned.

## Existing game result function: confirmed behaviour

`public.record_student_game_result(uuid, text, text, integer, integer)` is SECURITY DEFINER and executable by anon/authenticated/service_role in the supplied effective privilege output. Its supplied definition:
- Locks the matching session row with `FOR UPDATE`.
- Checks session used/expiry and game ID.
- Checks that the session class is active and resolves its teacher.
- Calculates reward as `LEAST(p_score, p_max_score)`.
- Inserts into `point_transactions` using browser-supplied game name and score fields.
- Marks the session used.

This is not sufficient for trusted score verification: the function does not verify individual answers against a server-held answer key. Do not simply remove the LEAST cap; replace the trust boundary with server-calculated, game-specific scoring and coordinated caller migration.

## Verified duplicate-protection gaps

- `student_activity_records` has only its primary key plus foreign keys in the supplied constraint output; no unique student/activity constraint was reported.
- `point_transactions` has only its primary key plus student/teacher foreign keys; no attempt-level idempotency key or unique attempt relation was reported.
- `student_game_sessions.session_token` is unique, but that alone does not provide one-reward-per-attempt idempotency.

These are conclusions from the metadata supplied so far, not proof that no application-level protections exist elsewhere.

## Remaining validation before an isolated PostgreSQL fixture is authoritative

The following must still be obtained or explicitly represented as test assumptions:
1. Full foreign-key and constraint metadata for all tables referenced by the fixture, including `teacher_profiles` and any other dependencies.
2. Effective ACLs and full definitions for every function the test fixture invokes.
3. Confirmation of whether zero-point reward transactions are valid business behaviour.
4. Complete caller inventory for legacy game-result and teacher/classroom point-writing paths.
5. Confirmation that the schema snapshot represents the same database environment/version intended for future rollout.

## Next safe implementation

Build a disposable PostgreSQL CI service using synthetic records only. Reproduce only the verified columns/constraints plus explicitly documented minimal dependencies. Run the proposed attempt schema and atomic functions there, then test:
- valid session and active student/class checks;
- answer correctness calculated from server-held answer keys;
- exact duplicate answer retry and conflicting retry;
- out-of-order and invalid answer rejection;
- expired/used session rejection;
- third-incorrect-answer challenge completion;
- final-question completion;
- concurrent duplicate submissions;
- exactly one reward transaction;
- no reward before completion;
- exact score, game-specific maximum, and exact reward points.

The CI job must contain no Supabase credentials and must not connect to any hosted Supabase project.

**Release status remains NO-GO.** This document records verified metadata; it is not a migration or approval to change the shared database.
