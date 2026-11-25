# Temmy Smart Classroom — Live Activity Database and API Design

**Date:** 25 November 2026  
**Status:** Design proposal for review; no migration has been applied  
**Repository:** `oyeleketemitope787-sys/temmy-smart-classroom`  
**Branch:** `cloud-test` only  
**Database:** isolated `temmy-smart-classroom-test` only  
**Production:** GitHub `main` and production Supabase must remain untouched

## 1. Purpose and design principles

This document translates the approved Live Activity requirements and the read-only legacy-system inspection into an additive database/API design. It is a blueprint, not executable migration SQL.

Core principles:
- Temmy Smart Classroom is a global, all-subject platform. It is not Mathematics-only and is not limited to one country, curriculum or language.
- Teachers choose their preferred interface language. Interface language and educational content language are independent.
- New UI strings use localization keys/resources. User-authored questions, instructions, options and feedback remain Unicode content and may be in any language or mixed languages.
- Support right-to-left scripts and locale-aware formatting in the client. Persist stable language-neutral codes in the database.
- Preserve existing activity tables, legacy RPCs, historical records and points transactions.
- Server is authoritative for eligibility, timing, autosave acceptance, submission cutoff, grading and points.
- Use controlled RPCs for student operations. Do not grant students direct access to answer keys or sensitive tables.
- Every consequential operation must be auditable and safe to retry.

## 2. Existing schema and compatibility baseline

Existing tables:
- `class_activities`: activity identity, teacher, class, title, description, points, active flag, status and creation time.
- `student_activity_records`: legacy one-text-answer submissions, status, points_awarded, notes and completion time.

Existing student RPCs:
- `get_student_live_activities(text)`
- `submit_student_activity(text, uuid, text)`

The current legacy student modal accepts one text answer. Teacher scoring currently updates `student_activity_records` and calls `record_student_point_transactions` separately, with browser-side compensation if the second operation fails. This is not atomic.

Compatibility rules:
1. Do not rename, drop or repurpose existing columns or legacy RPCs in the initial Live Activity migration.
2. Do not convert historical `live_task` activities or existing `student_activity_records` into the new model.
3. Preserve `student_activity_records.answer` for legacy data.
4. New-format activities link to an existing `class_activities.id`, but use new version, question, attempt and answer records.
5. Legacy activities continue through their existing path until an explicit compatibility rollout is implemented and tested.
6. Do not backfill or re-award historical activity points.

## 3. Proposed data model

The following tables are proposed. Exact SQL types, FK delete behaviours, indexes, RLS and grants must be encoded in the reviewed migration after checking naming conflicts and current schema.

### 3.1 `class_activity_versions`

Immutable published snapshot of an activity's content/configuration.

| Column | Purpose |
|---|---|
| `id` uuid PK | Version identity |
| `activity_id` uuid FK -> `class_activities.id` | Parent activity |
| `version_number` integer | Monotonic version per activity |
| `duration_seconds` integer | Teacher-configured duration |
| `content_language` text nullable | Optional BCP-47 language tag for primary content language |
| `settings` jsonb | Approved non-secret presentation/assessment settings |
| `published_at` timestamptz nullable | Null while draft; set when published |
| `created_by` uuid FK -> teacher | Author |
| `created_at` timestamptz | Audit timestamp |

Constraints:
- Unique `(activity_id, version_number)`.
- Duration must be positive and within a product-defined safe maximum.
- Published versions are immutable. Editing a published activity creates a new version.
- A live activity points to one published version for new attempts; already-started attempts remain bound to their original version.

### 3.2 `class_activity_questions`

Question content and marking configuration belonging to a version.

| Column | Purpose |
|---|---|
| `id` uuid PK | Stable question identity |
| `version_id` uuid FK -> `class_activity_versions.id` | Version |
| `position` integer | Display order |
| `question_type` text | Stable code: `multiple_choice`, `fill_gaps`, `true_false`, `matching`, `short_answer`, `extended_response` |
| `prompt` jsonb | Structured Unicode content; supports text and future media references |
| `response_config` jsonb | Public response UI configuration, e.g. choices, gaps or matching pairs |
| `answer_key` jsonb nullable | Server-only grading data; never returned by student RPCs |
| `marking_config` jsonb | Max marks, accepted variants, tolerance/rubric and grading mode |
| `max_marks` numeric | Maximum marks for this question |
| `is_required` boolean | Whether teacher marks it as required; unanswered still receives zero |
| `created_at` timestamptz | Creation time |

Rules:
- Stable language-neutral question type codes; localized labels belong in the client.
- Prompt/options may contain arbitrary Unicode and mixed languages.
- Never put answer keys in a JSON object returned to student clients.
- Validate each question type's JSON structure in server-side functions before publishing.
- Use exact decimal/numeric rules for marks; define rounding policy centrally before implementation.
- Multiple choice supports the approved single/multiple selection behaviour only as configured by the approved editor design; do not invent a different student interface.
- Fill-in-the-gaps stores ordered gap identifiers and accepted-answer rules.
- True/false stores the canonical boolean answer.
- Matching stores left/right item identifiers and correct pair mapping.
- Short answer may use objective accepted-answer matching or teacher marking; if judgement is required, mark as teacher-graded.
- Extended response is teacher-graded and supports partial marks and rubric feedback.

### 3.3 `student_activity_attempts`

One attempt for a student on a specific activity publication.

| Column | Purpose |
|---|---|
| `id` uuid PK | Attempt identity |
| `activity_id` uuid FK -> `class_activities.id` | Activity |
| `version_id` uuid FK -> `class_activity_versions.id` | Immutable content snapshot |
| `student_id` uuid FK -> `students.id` | Student |
| `class_id` uuid FK -> `classes.id` | Class at attempt creation |
| `teacher_id` uuid FK -> teacher | Responsible teacher |
| `attempt_number` integer | 1 initially; increments only on authorised reopening |
| `status` text | Stable codes: `in_progress`, `submitted`, `expired_pending_finalize`, `pending_marking`, `graded`, `reopened`, `voided` |
| `started_at` timestamptz | Server start time |
| `deadline_at` timestamptz | Server-calculated fixed deadline |
| `submitted_at` timestamptz nullable | Immutable cutoff time |
| `finalized_at` timestamptz nullable | Server finalization time |
| `objective_marks` numeric nullable | Automatically awarded marks |
| `teacher_marks` numeric nullable | Teacher-awarded marks |
| `total_marks` numeric nullable | Final total when grading complete |
| `max_marks` numeric | Maximum for bound version |
| `submission_reason` text nullable | `student_submit`, `time_expiry`, `teacher_recovery` |
| `reopened_from_attempt_id` uuid nullable | Previous attempt reference |
| `created_at`, `updated_at` timestamptz | Audit timestamps |

Constraints and invariants:
- At most one current non-voided attempt per `(activity_id, student_id)`; implement with a partial unique index after verifying supported statuses and reopen model.
- A new attempt starts only when the student is eligible, activity is live, and no current attempt exists.
- `started_at` and `deadline_at` are server-set. Client clocks never extend time.
- Reconnect/resume returns the original deadline; it never resets the timer.
- Once submitted/expired, response rows are immutable except through a separately authorised and audited recovery workflow.
- Reopening must preserve the old attempt and answers. The precise policy for whether the old attempt is marked `reopened` or `voided` and how the new attempt links to it will be enforced in the RPC.
- Teacher-authorised reopening requires authenticated teacher ownership of the activity/class, a reason, and an audit event.

### 3.4 `student_activity_answers`

One current saved response per question per attempt.

| Column | Purpose |
|---|---|
| `id` uuid PK | Answer row |
| `attempt_id` uuid FK -> `student_activity_attempts.id` | Attempt |
| `question_id` uuid FK -> `class_activity_questions.id` | Question |
| `response` jsonb | Student response; type-specific shape |
| `revision` bigint | Monotonically increasing server revision |
| `saved_at` timestamptz | Server save time |
| `objective_marks` numeric nullable | Auto-marked marks after submission |
| `teacher_marks` numeric nullable | Teacher marks |
| `awarded_marks` numeric nullable | Effective marks |
| `marking_status` text | Stable code such as `unmarked`, `auto_marked`, `pending_teacher`, `teacher_marked` |
| `feedback` jsonb nullable | Teacher-authored Unicode feedback |

Constraints:
- Unique `(attempt_id, question_id)`.
- Question must belong to the attempt's immutable version.
- Each save includes expected revision; server rejects stale writes and returns current revision/state.
- The server validates that the attempt is still editable and before deadline.
- Autosave responses must not contain or expose answer keys.
- At submission, unanswered questions have no response and receive zero marks.

### 3.5 `student_activity_events`

Append-only audit trail for significant lifecycle events.

| Column | Purpose |
|---|---|
| `id` uuid PK | Event identity |
| `attempt_id` uuid FK -> attempt | Related attempt |
| `actor_type` text | `student`, `teacher`, `system` |
| `actor_id` uuid nullable | Authenticated actor where applicable |
| `event_type` text | Stable event code |
| `event_data` jsonb | Minimal structured details; never store access codes/secrets |
| `request_id` uuid nullable | Idempotency/correlation |
| `created_at` timestamptz | Server timestamp |

Events include attempt started, answer saved, submitted, expiry finalized, teacher marked, result corrected, reopened and recovery completed. Avoid logging full answer text in event data; the answer table is the source of response content.

## 4. Lifecycle and server-side RPC design

All student-facing RPCs accept the access code only where required to establish identity, call the existing verification helper internally, and derive student identity from the verified result. They must never accept a client-supplied student ID as authoritative.

### 4.1 Teacher authoring and publication

Proposed RPC responsibilities:
- Create/update activity draft and question content.
- Validate all question types, marks, answer keys and content.
- Publish immutable version; ensure total question marks and configured activity points are consistent with the chosen scoring rule.
- Launch activity against a specific published version.
- Close activity and prevent new attempts while preserving active attempts according to explicit close policy.

Teacher calls require `auth.uid()`, ownership checks against activity/class, and explicit function EXECUTE grants only to `authenticated`.

### 4.2 Student start/resume

Proposed `start_or_resume_student_activity(p_access_code, p_activity_id)`:
1. Verify active student access code.
2. Lock activity row and validate active/live state and class membership.
3. Find existing current attempt; if found, return it with its original server deadline.
4. Otherwise create one attempt bound to the current published version.
5. Return only student-safe question content and saved responses; never return `answer_key`.
6. Log attempt start once.

Concurrent duplicate starts must resolve to one attempt through database uniqueness/locking, not browser logic.

### 4.3 Student autosave

Proposed `save_student_activity_answer(p_access_code, p_attempt_id, p_question_id, p_response, p_expected_revision, p_request_id)`:
- Derive student identity from access code and verify attempt ownership.
- Lock attempt row.
- If deadline has passed, refuse edits and trigger/queue safe expiry finalization.
- Verify attempt is still in progress and question belongs to the attempt's version.
- Validate response shape for the question type.
- Enforce expected revision and request idempotency.
- Upsert response and increment revision atomically.
- Return confirmed saved revision and server timestamp.
- Log save metadata without copying sensitive response content into event payload.

### 4.4 Student submission and expiry

Proposed `submit_student_activity_attempt(p_access_code, p_attempt_id, p_request_id)` and internal expiry finalizer:
- Lock attempt row.
- Verify ownership and state.
- Use server time as cutoff; if student submits before deadline, record submission time at server acceptance.
- If deadline has passed, set cutoff to the server deadline and mark expiry submission.
- Prevent any subsequent answer save.
- Auto-grade objective questions using server-only answer keys.
- Leave judgement-based written answers pending teacher marking.
- Record one submission event and an idempotent result.
- Return safe summary: submission status, saved/answered count, objective score if policy permits, pending-marking count.
- Repeated identical requests return the existing result; they never create another attempt or award.

**Offline expiry limitation:** A browser disconnected at 00:00 cannot communicate a submission at that instant. The database can preserve the last confirmed saves and finalize when the client reconnects. To finalize attempts even when nobody reconnects, the system needs a trusted scheduled server-side worker (e.g. Supabase Cron invoking a restricted expiry RPC). The worker mechanism and availability must be verified before claiming unattended immediate expiry. The deadline remains authoritative regardless of worker delay.

### 4.5 Teacher monitoring

Proposed teacher RPC returns only:
- Student identity/display name permitted to that teacher.
- Attempt status.
- Server deadline and remaining-time calculation.
- Answered/unanswered counts and progress.
- Submission/finalization status.
- Objective/pending marking status when available.

It must not return active response content or answer keys before submission/expiry. RLS/ownership checks must prevent cross-class access.

### 4.6 Teacher marking and points

Proposed `mark_student_activity_attempt(p_attempt_id, p_marks, p_feedback, p_request_id)`:
1. Require authenticated teacher and validate ownership of activity/class.
2. Lock attempt and answer rows.
3. Validate all marks against each question's maximum; allow partial marks.
4. Require all judgement-based questions to be marked before final grading, unless teacher explicitly saves a draft marking state.
5. Calculate final total server-side; never trust a client total.
6. Calculate the eligible points delta according to the approved points conversion rule.
7. In the same PostgreSQL transaction, update marking state and call `record_student_point_transactions` with a stable request ID/payload.
8. Persist operation result and event so identical retries cannot duplicate marks or points.
9. If points operation fails, the entire grading transaction rolls back.

**Scoring conversion decision still required before implementation:** Existing `class_activities.points` is an integer reward value, while the new model introduces question marks and partial marks. The exact conversion from academic marks to points (for example, proportional conversion versus direct points) must be established from the existing teacher workflow and approved rules before implementing the marking RPC. Do not assume the conversion.

A score correction must be an explicit audited operation that computes a delta and uses the same atomic points pathway; never silently overwrite the prior result or re-award the full score.

## 5. Timing and expiry model

- Store duration in seconds on the immutable activity version.
- On first start, calculate `deadline_at = started_at + duration_seconds` using database server time.
- Every response save, resume and submit operation compares against server time.
- Client displays a countdown derived from server deadline and a server-time reference; browser timer is presentation only.
- Refresh/resume returns the original deadline.
- At expiry, no new response is accepted.
- A scheduled worker is needed for unattended finalization while all clients are offline. Design and test this separately; do not make the UI claim server-side finalization has happened until confirmed.
- Store timestamps as `timestamptz`; display in the user's selected locale/time zone without changing the stored instant.

## 6. Localization and global education support

This feature must align with the global Temmy Smart Classroom direction:
- No Mathematics-only assumptions in table names, question structures, activity configuration or RPC contracts.
- Subject, topic, curriculum/standard and grade/stage references should be optional, extensible metadata or relations, not hard-coded enumerations tied to one country.
- Teacher interface language is a user preference, independent of activity content language.
- Activity content fields accept Unicode and mixed-language content. Optional BCP-47 content-language metadata may describe the primary language, but must not prohibit mixed-language questions.
- Interface strings are translation keys in a shared localization system; database status/type codes remain language-neutral.
- Client supports RTL direction and mixed-direction text. Use direction isolation for embedded LTR numbers/expressions where needed.
- Use locale-aware formatting for dates, times, marks and decimal values. Do not store formatted strings as canonical numeric values.
- Do not hard-code a language list or assume English is always the fallback; establish language registry/fallback policy as part of shared platform localization architecture.
- Keep curriculum and academic stage structures configurable by school/country. Do not make a Live Activity migration depend on a single national curriculum model.

## 7. Security, RLS and grants

- All new tables have RLS enabled.
- Student client receives no direct SELECT/INSERT/UPDATE/DELETE grants on answer keys, attempts or answers unless a specific safe policy is proven necessary. Preferred student access is through controlled RPCs.
- Teacher access is limited to activities/classes owned by `auth.uid()`.
- SECURITY DEFINER functions use `SET search_path = ''` and schema-qualified object references.
- Revoke default PUBLIC EXECUTE where not required; grant student RPC execution to `anon` only where access-code-based student portal requires it, and grant teacher RPCs to `authenticated` only.
- Never grant student RPCs that expose answer keys or arbitrary student identifiers.
- Verify helper function privileges and ownership; SECURITY DEFINER owner is privileged and bypasses ordinary caller RLS in typical configurations, so every function must perform explicit identity and ownership checks.
- Validate JSONB shape, maximum payload sizes, response lengths, request IDs, question membership, deadline and attempt state server-side.
- Use deterministic row lock order and indexes for concurrency.
- Do not log access codes, secrets, full answer payloads or unnecessary personal data.

## 8. Idempotency and concurrency

- Every mutating client request carries a UUID request ID.
- Store request results or a unique operation record so identical retries return the original result and changed-payload reuse is rejected.
- Unique constraints enforce one answer per question per attempt and one current attempt per student/activity.
- Lock the attempt row before validating deadline/state and writing answers.
- Lock assessment rows before grading and points updates.
- Use a deterministic lock order across attempt, answer, student/account and points-operation records to reduce deadlocks.
- Handle network retries as normal; the database is the authority on whether a save/submission/marking operation committed.

## 9. Indexes and integrity checks to include in migration review

Candidate indexes:
- `class_activity_versions(activity_id, version_number)` unique.
- `class_activity_questions(version_id, position)` unique.
- `student_activity_attempts(activity_id, student_id, status)` plus a partial unique current-attempt index once current-state semantics are finalized.
- `student_activity_attempts(deadline_at, status)` for expiry worker.
- `student_activity_answers(attempt_id, question_id)` unique.
- `student_activity_events(attempt_id, created_at)`.
- Index all FK columns used for ownership/joins if not already indexed.

Before adding FK/unique constraints, run read-only checks for orphaned rows, duplicate logical keys and existing names. Do not add cascading deletes that could erase historical attempts/audit records.

## 10. Migration and implementation sequence

1. Confirm exact test project identity before any write operation. The user's latest confirmation says work is on test and `main` is untouched, but the earlier Supabase UI showed a confusing `main — PRODUCTION` indicator; re-verify the active project and branch at the time of migration.
2. Recheck existing names, FKs, roles, grants, RLS defaults and Supabase extensions.
3. Review this design and resolve the scoring conversion rule.
4. Write an additive migration with tables, constraints, indexes, RLS and grants only after review.
5. Write narrowly scoped RPCs for teacher publication, student start/resume, autosave, submit/expiry, teacher monitoring and marking.
6. Static-review every SECURITY DEFINER function and its EXECUTE grants.
7. Run SQL tests inside explicit transactions and roll back fixtures where possible.
8. Test concurrent start/save/submit/marking, duplicate request IDs, stale revisions, deadline races and points rollback.
9. Implement the shared localization foundation before the new Live Activity UI strings are introduced.
10. Implement the approved common student layout and six response controls.
11. Test all formats, mixed scripts, RTL, locale formatting, reconnect, expiry and teacher monitoring.
12. Update progress with evidence and commit only to `cloud-test`.

## 11. Open implementation blockers (do not guess)

1. **Academic marks to points conversion:** confirm from existing rules and current teacher UI whether activity reward points are proportional, direct, or governed by another approved formula.
2. **Expiry worker:** verify available Supabase scheduled execution capability and configure a restricted worker; without it, offline attempts are finalized on reconnect or the next server interaction.
3. **Question editor/content schema:** inspect existing media/storage conventions and mathematical notation support before finalizing prompt/response JSON shape.
4. **Current-attempt/reopening semantics:** finalize exact status transitions and unique-index predicate so exceptional reopening preserves full history without creating two active attempts.
5. **Localization foundation integration:** inspect current user/profile tables and frontend architecture to choose the correct shared locale preference storage; do not add duplicate preference columns blindly.

## 12. Current disposition

**Design blueprint prepared; no migration or code changes are made by this document.**

Live Activity remains the active implementation priority. Games remains deferred under `docs/GAME_SYSTEM_AUDIT.md`. GitHub `main` and production Supabase remain untouched.
