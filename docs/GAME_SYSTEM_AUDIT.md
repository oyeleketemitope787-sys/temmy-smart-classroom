# Temmy Smart Classroom — Existing Games System Audit

**Audit date:** 25 November 2026  
**Status:** Read-only inspection completed for the objects listed below; remediation deferred  
**Repository:** `oyeleketemitope787-sys/temmy-smart-classroom`  
**Working branch:** `cloud-test`  
**Production branch:** `main` — do not modify  
**Database inspected:** `temmy-smart-classroom-test`  
**Sequencing decision:** Complete and verify Live Activity before modifying the Games system.

## 1. Purpose and boundary

This document preserves the findings from the read-only inspection of the existing Games database workflow. It is a baseline for a later Games hardening and Aggregate/Spendable Points integration phase.

No Games frontend code, game catalogue, session table, function, RLS policy, permission, or historical record was changed as part of this inspection. The findings below describe only the objects and outputs actually inspected. They are not a claim that every Games component has been audited.

Do not begin Games remediation while Live Activity is still being implemented, unless a separate critical incident requires it and the user approves the scope.

## 2. Existing game-session table

Inspected table: `public.student_game_sessions`

### 2.1 Columns

| Column | Type | Nullable | Default |
|---|---|---:|---|
| `id` | uuid | No | `gen_random_uuid()` |
| `student_id` | uuid | No | — |
| `class_id` | uuid | No | — |
| `game_id` | text | No | — |
| `session_token` | uuid | No | `gen_random_uuid()` |
| `created_at` | timestamptz | No | `now()` |
| `expires_at` | timestamptz | No | `now() + interval '30 minutes'` |
| `used_at` | timestamptz | Yes | — |

### 2.2 Constraints and indexes

Confirmed:
- Primary key: `student_game_sessions_pkey` on `id`.
- Unique constraint/index: `student_game_sessions_session_token_key` on `session_token`.

The foreign-key inspection returned **zero rows**. Therefore, the inspected table currently has no declared foreign keys for `student_id` or `class_id`. The columns are NOT NULL, but referential integrity to `students` and `classes` is not enforced by foreign-key constraints in the inspected schema.

### 2.3 RLS

- Row Level Security is enabled.
- RLS is not forced.
- The policy inspection returned no policies for `student_game_sessions`.

The student session workflows therefore rely on the controlled SECURITY DEFINER functions described below, rather than direct student table policies.

## 3. Existing game-session functions

All four function definitions below were retrieved from the database.

### 3.1 `start_student_game_session(p_access_code text, p_game_id text)`

Observed behaviour:
- Calls `verify_student_access_code` and returns no row if the code does not resolve to an active student.
- Checks that the student's class exists and is active.
- Generates a UUID session token.
- Sets expiry to 30 minutes after creation.
- Inserts student, class, supplied game ID, token and expiry into `student_game_sessions`.
- Returns session token, student/class identifiers, class name, student names and expiry.

Security/validation observations:
- SECURITY DEFINER, owned by `postgres`.
- Uses `search_path=public`.
- Effective EXECUTE permission: `anon=true`, `authenticated=true`.
- It checks class activity but does not visibly validate `p_game_id` against an approved/registered game catalogue.
- The student identity is established by access-code verification.

### 3.2 `get_student_game_sessions(p_access_code text)`

Observed behaviour:
- Verifies the supplied student access code.
- Returns that student's sessions where `expires_at > now()` and `used_at IS NULL`.
- Returns session token, game ID, creation time and expiry, newest first.

Security/validation observations:
- SECURITY DEFINER, owned by `postgres`.
- Uses `search_path=public`.
- Effective EXECUTE permission: `anon=true`, `authenticated=true`.
- Anyone able to use the student's access code can request the student's active unused session tokens. Treat access codes and returned tokens as credentials.

### 3.3 `start_teacher_game_session(p_student_id uuid, p_game_id text)`

Observed behaviour:
- Requires `auth.uid()`; raises if teacher authentication is absent.
- Requires a non-empty game ID.
- Verifies that the student is active and belongs to an active class owned by the signed-in teacher.
- Generates a UUID token and a 30-minute expiry.
- Inserts the session and returns session/student/class details.

Security/validation observations:
- SECURITY DEFINER, owned by `postgres`.
- Uses `search_path=public`.
- Effective EXECUTE permission: `anon=false`, `authenticated=true`.
- Teacher ownership validation is stronger than the student session creator's visible game-ID validation.

### 3.4 `record_student_game_result(p_session_token uuid, p_game_id text, p_game_name text, p_score integer, p_max_score integer)`

Observed behaviour:
- Returns no result when score is negative or maximum score is not positive.
- Selects the matching session by token and locks it `FOR UPDATE`.
- Rejects a missing, used, expired or game-ID-mismatched session.
- Resolves the teacher from the session's active class.
- Calculates awarded points as `least(p_score, p_max_score)`.
- Inserts a row directly into `public.point_transactions` with source `game`, action type `activity_score`, supplied game name, and a reason containing the supplied score/maximum.
- Marks the session used.
- Returns awarded points, supplied score/maximum, action name and recording time.

Security/validation observations:
- SECURITY DEFINER, owned by `postgres`.
- Uses `search_path=public`.
- The function ACL was NULL; effective permission checks confirmed `anon=true`, `authenticated=true`, `service_role=true`.
- The session row lock and `used_at` check provide protection against reusing the same session token in concurrent submissions.
- It checks the supplied game ID against the session's game ID.
- It does not visibly validate `p_game_name` against a trusted game catalogue.
- It does not visibly establish the authoritative maximum score from a server-controlled game definition. The score is capped by the caller-supplied `p_max_score`, not by a maximum independently loaded from a trusted game configuration.
- The definition checks numeric bounds but does not visibly check that the student is still active.
- It writes directly to the points ledger instead of using the atomic Aggregate/Spendable points RPC.

## 4. Access-code verification dependency

Inspected function: `verify_student_access_code(p_access_code text)`.

Observed behaviour:
- Joins `student_access` to `students`.
- Verifies the submitted code with `extensions.crypt(p_access_code, sa.code_hash) = sa.code_hash`.
- Requires `sa.active = true` and `s.active = true`.
- Returns student ID, class ID and student names.

Security observations:
- SECURITY DEFINER, owned by `postgres`.
- Uses `search_path=public`.
- Effective EXECUTE permission: `anon=false`, `authenticated=true`.
- Student-facing session functions call this function internally. The fact that a caller can execute those outer functions anonymously does not require direct anonymous EXECUTE on this helper.

## 5. Effective function permissions observed

The following are results of `has_function_privilege` checks in the inspected database:

| Function | anon | authenticated | service_role |
|---|---:|---:|---:|
| `get_student_game_sessions(text)` | Yes | Yes | Not checked in the returned session-permission query |
| `start_student_game_session(text, text)` | Yes | Yes | Not checked in the returned session-permission query |
| `start_teacher_game_session(uuid, text)` | No | Yes | Not checked in the returned session-permission query |
| `record_student_game_result(uuid, text, text, integer, integer)` | Yes | Yes | Yes |
| `verify_student_access_code(text)` | No | Yes | No |

All five inspected functions are SECURITY DEFINER and owned by `postgres`. All five inspected definitions use `search_path=public`. These settings should be revisited during the later Games hardening phase; security-definer functions should use a deliberately constrained search path and explicitly qualified object names.

## 6. RLS and grants inspected around Games and points

### 6.1 RLS state

RLS is enabled on:
- `student_game_sessions`
- `students`
- `classes`
- `point_transactions`
- `student_point_accounts`
- `student_access`
- `class_activities`
- `student_activity_records`

None of the inspected tables had RLS forced.

### 6.2 Relevant policy findings

The policy query returned no policies for:
- `student_game_sessions`
- `student_access`
- `student_point_accounts`

The inspected `students` and `classes` policies are teacher-scoped. `point_transactions` has authenticated teacher insert and select policies; its insert policy checks that the transaction teacher matches `auth.uid()` and that the student belongs to a class owned by that teacher.

### 6.3 Table grants relevant to the points risk

The table-grant inspection showed:
- `point_transactions`: authenticated has INSERT and SELECT, among other non-data privileges; no authenticated UPDATE or DELETE was listed.
- `student_point_accounts`: no authenticated direct table grants were listed.
- `student_game_sessions`: direct table access is intended to be mediated by SECURITY DEFINER workflows, with RLS enabled and no policies returned.

RLS and grants are separate controls. The effective security of a SECURITY DEFINER function depends on its validation logic, ownership, search path and callable roles.

## 7. Aggregate/Spendable Points integration risk

The two-balance account foundation now exists in the isolated test project. The approved accounting model is:
- Valid non-marketplace awards/adjustments update both Aggregate Points and Spendable Points.
- Marketplace purchases reduce Spendable Points only.
- Aggregate Points are used for achievement/ranking; Spendable Points are used for marketplace affordability.

The inspected `record_student_game_result` function inserts directly into `point_transactions`. It does **not** call `record_student_point_transactions` or update `student_point_accounts` in its inspected definition.

Consequently, after the two-balance account foundation is installed, this legacy game-result path can add a ledger transaction without updating the corresponding Aggregate/Spendable account balances. Game awards must be routed through an approved atomic points operation before the new account summaries can be treated as authoritative for Games.

This is a concrete integration issue to address in the later Games phase. Do not repair it by manually editing balances or replaying historical game awards.

## 8. Historical game scoring observations

For the inspected student `0cf1c3fc-dbe9-48f6-ac1a-5c5b6888b9b4`, the game-source transaction audit returned three `Temmy Number Challenge` transactions:

| Transaction | Points | Recorded reason | Source |
|---|---:|---|---|
| `c529f5f4-f1f1-473a-8c9e-b4080cb10f3d` | +10 | Game completed — 10/15 | game |
| `951bc263-ea3e-4f2d-9792-d0ac4b870599` | +24 | Game completed — 24/15 | game |
| `7acc8ab8-7868-4a98-a8b9-f9f4a121600d` | +15 | Game completed — 29/15 | game |

Net game-source points in this group: **+49**.

The currently inspected function uses `least(p_score, p_max_score)`, so a supplied score of 24 with maximum 15 would award at most 15 under that exact current definition. The historical +24 transaction may have been created by an earlier function version or a different call/input. The available inspection does not establish which explanation is correct.

Actions:
- Preserve all historical transactions.
- Do not infer that the historical transactions are invalid solely from the reason text.
- Later inspect game frontend scoring, the historical function/version timeline if available, and the exact game result RPC call payload.
- Define an authoritative server-side game maximum and score validation for future submissions.
- Reconcile historical ledger entries to account balances without re-awarding them.

## 9. Known gaps and deferred remediation checklist

When the Games phase begins, review and resolve these items:

1. **Game catalogue validation:** Define an authoritative list/configuration of valid game IDs and server-owned maximum scores.
2. **Result payload trust:** Do not trust client-supplied game name or maximum score; derive them from trusted configuration.
3. **Scoring validation:** Validate score range and game-specific scoring rules server-side.
4. **Atomic points integration:** Replace direct ledger insertion with a trusted, idempotent operation that updates both Aggregate and Spendable balances in the same transaction.
5. **Exactly-once result processing:** Preserve session locking/single-use semantics and add explicit request/result idempotency as appropriate.
6. **Session ownership/integrity:** Consider foreign keys for student/class relationships after checking existing rows for orphans and migration impact.
7. **Active-state validation:** Decide and enforce expected student/class eligibility at result submission.
8. **Function hardening:** Review EXECUTE grants; remove unintended PUBLIC/anonymous access only where compatible with the intended access-code student experience; set a constrained search path (preferably empty with schema-qualified references).
9. **Access-code handling:** Preserve the current secure hash verification; review rate limiting, code entropy, error behaviour and exposure of active session tokens.
10. **RLS/grants:** Reassess table grants and policies alongside SECURITY DEFINER function boundaries; do not assume RLS protects table access performed by a privileged function owner.
11. **Frontend dependencies:** Find all game-session creation, session lookup and result-submission call sites before changing function signatures or behaviour.
12. **Regression tests:** Cover student and teacher session creation, invalid/inactive code, wrong game ID, expired token, duplicate/concurrent result submission, invalid scores, trusted maximum, cross-student isolation, points balances and rollback.
13. **Historical reconciliation:** Preserve historical game transactions and verify account-to-ledger reconciliation without re-awarding past results.

## 10. Deferred implementation sequence

Games remediation starts only after Live Activity is fully implemented and verified.

Suggested later sequence:
1. Inspect the full Games frontend and all RPC call sites.
2. Inspect game catalogue/configuration and scoring rules.
3. Reconcile historical game transactions with Aggregate/Spendable accounts.
4. Approve a compatibility-preserving server-side Games scoring design.
5. Implement reviewed additive migrations/functions on the isolated test project.
6. Test student and teacher game flows, security boundaries, scoring, idempotency and two-balance accounting.
7. Update this audit with actual changes, test evidence and commit identifiers.
8. Only consider production deployment after separate explicit approval.

## 11. Current disposition

**Games system: inspected and documented; remediation deferred.**

**Live Activity: remains the active implementation priority.**

No Games schema, function, permission, frontend code or historical transaction was modified during this audit. GitHub `main` and production Supabase remain untouched.
