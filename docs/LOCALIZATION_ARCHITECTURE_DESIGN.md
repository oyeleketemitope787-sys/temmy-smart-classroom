# Temmy Smart Classroom — Localization and Language Preference Architecture

**Date:** 25 November 2026  
**Status:** Design proposal approved for continued design; no schema migration or UI implementation  
**Repository:** `oyeleketemitope787-sys/temmy-smart-classroom`  
**Branch:** `cloud-test` only  
**Production:** GitHub `main` and production Supabase must remain untouched

## 1. Approved product direction

Temmy Smart Classroom is a global, all-subject, multilingual classroom platform. Localization is a shared platform capability, not a cosmetic feature added separately to individual modules.

Approved principles:
- Teacher and student interface language is independent of educational content language.
- Each teacher and each student can have an individual interface-language preference.
- A class can define a default interface language for learners who have not selected one.
- A platform-level fallback is used when no applicable preference exists or a translation is unavailable.
- Individual preference takes priority over class default.
- The design must allow a future school/organisation default without requiring a redesign of teacher, student or class identity.
- Language preferences must not be stored against student access codes or other replaceable credentials.
- Persist stable language tags/codes, not translated display labels.
- Unicode, mixed-language content, RTL scripts, locale-aware date/time/number formatting and accessible translated UI are platform-wide requirements.

The user approved the recommended scope: implement teacher, student and class preferences first; defer school/organisation accounts and defaults while preserving a clean extension path.

## 2. Verified existing architecture

Read-only inspection of the `cloud-test` application and isolated test database found:

### Identity and relationships
- `teacher_profiles.id` is aligned with `auth.uid()` by its existing RLS policies for teacher profile insert, select and update.
- `classes.teacher_id` references `teacher_profiles.id`.
- `students.class_id` references `classes.id`.
- `groups.class_id` references `classes.id`; `group_members` links groups and students.
- `student_access.student_id` references `students.id` and has a UNIQUE constraint. Student access uses a hashed access code, while `students.id` is the stable learner identity.
- No dedicated school/organisation account or settings table was found in the public table inventory.
- No language/locale/preference columns or matching public routines were found in the inspected schema.
- No relevant triggers were found on `teacher_profiles`, `students` or `classes`.
- The `student_access` policy inspection returned no policies. Student access must continue through carefully constrained RPCs; do not expose access-code hashes to clients.

### Existing frontend
- The app is currently a monolithic `index.html`.
- Teacher profile load/save reads/writes `teacher_profiles`.
- Student portal login calls `student_portal_login(p_access_code)` and receives a permanent `student_id`.
- The current student session holds access-code and student identity in client-side JavaScript state.
- No translation framework, language selector, locale preference storage or RTL document-direction handling was found in the inspected file.
- `now()` uses `Date.toLocaleString()` without an explicit selected locale. Two name-sort paths use `localeCompare()`.
- Existing `localStorage` use inspected was for legacy classroom application data; no language preference storage was identified.

These are inspection findings, not permission to alter legacy authentication or storage behaviour without a separate compatibility review.

## 3. Proposed preference storage

Use additive nullable language-tag fields on the existing identity/context rows, subject to final schema, naming, length and validation review:

| Owner | Proposed field | Meaning |
|---|---|---|
| `teacher_profiles` | `preferred_interface_language` | Teacher's individual UI language |
| `students` | `preferred_interface_language` | Student's individual UI language |
| `classes` | `default_interface_language` | Class default when a student has no individual choice |

Use BCP 47 language tags (for example, language plus optional script/region subtags) as stable values. The examples are illustrative, not an approved initial language list.

A NULL value means no explicit preference and allows inheritance. Do not store translated language names as canonical values. Do not use a PostgreSQL enum for language choices; the supported language registry and display names belong to shared localization configuration.

Why this model:
- It follows existing ownership relationships and avoids introducing a polymorphic owner table with weak or unenforceable foreign-key relationships.
- Teacher preferences remain attached to the authenticated teacher profile.
- Student preferences remain attached to the permanent student row even if an access code is regenerated.
- Class defaults naturally belong to the existing class record.
- Future organisation defaults can be added when a real organisation/tenant model exists, as a higher-level fallback layer, without changing these identity keys.

No field or table has been added yet.

## 4. Resolution and fallback rules

### Student interface
1. Student's own `preferred_interface_language`, when set and supported.
2. Class's `default_interface_language`, when set and supported.
3. Centrally configured platform fallback language.

### Teacher interface
1. Teacher's own `preferred_interface_language`, when set and supported.
2. Centrally configured platform fallback language.

A teacher's current class default must not silently override the teacher's own interface preference. Class default is primarily a learner/context default, not a forced teacher setting.

If a stored language tag is no longer supported, ignore it safely and continue through the fallback chain. If an individual language is supported but a particular translation key is missing, use the configured per-key fallback and record missing translation coverage during development/testing.

The initial supported-language registry and platform fallback were approved on 2026-11-25; see Section 11 for the exact registry and fallback.

Future organisation default insertion point:
- Student: individual -> class -> organisation -> platform.
- Teacher: individual -> organisation (if later explicitly adopted for teacher UI) -> platform.
The future organisation layer is not part of the first implementation.

## 5. Localization application architecture

Create a shared client-side localization layer before translating module screens. It should provide:
- A language registry containing supported BCP 47 tags, native display names, text direction and translation-resource availability.
- A translation lookup function with interpolation/plural support and a deterministic fallback chain.
- A single way to change active language and refresh visible UI without losing unsaved work.
- A safe missing-key development diagnostic; never show raw undefined values to end users.
- Shared formatting helpers for dates, times, numbers, decimals and percentages using the selected locale and explicit time-zone policy.
- Direction management at document/application level (`dir=ltr` or `dir=rtl`) and direction isolation for mixed-script text, identifiers, numbers and mathematical expressions.
- Accessible labels, validation errors, notifications, empty states, dialogs, menus and dynamic status text in translation resources.
- A clear separation between UI translation resources and user-authored educational content.

Do not implement translations by replacing arbitrary English text in the DOM. Do not embed new hard-coded English UI strings in new workflows. All new UI strings must use stable localization keys.

## 6. Database and API security

- Teacher preference reads/writes must be scoped to `auth.uid()` and the existing teacher profile ownership model.
- Student preference reads/writes must derive the student from a verified access code through controlled RPCs; never accept a client-supplied `student_id` as authoritative.
- Do not grant direct client access to `student_access.code_hash` or expose its contents through preference RPCs.
- Class-default changes must require an authenticated teacher who owns the class.
- Validate language tags against the supported registry on the server or a trusted shared validation source. Do not rely solely on client-side validation.
- Keep preference RPC responses minimal and never return unrelated student or teacher data.
- Preserve existing RLS/grants and legacy login behaviour; review exact policies, function ACLs and call sites before drafting migration SQL.
- If direct authenticated updates to teacher profile/class/student rows are considered, verify the existing RLS and column-level grant posture first. Prefer narrow RPCs where necessary to avoid broadening access.

## 7. Rollout sequence

1. Finish read-only inspection of relevant RLS policies, grants, function ACLs and frontend load/render lifecycle.
2. Agree the initial language registry, platform fallback and time-zone policy with the user.
3. Design the localization resource format and translation-key conventions.
4. Finalize additive preference columns and narrowly scoped read/write operations.
5. Implement the shared localization/formatting/direction layer in an isolated feature branch derived from `cloud-test`; do not touch `main`.
6. Add teacher language selection and persistence.
7. Add student language selection and persistence through the access-code RPC boundary.
8. Add class default selection and resolution for students.
9. Localize one representative workflow end-to-end, test LTR and RTL, then expand to teacher/student portals, Live Activity, games, reports and settings.
10. Verify fallback, unsupported stored values, missing translation keys, mixed-language content, access-control boundaries and session changes before release.

## 8. Outstanding decisions and blockers

- Translation-resource packaging/versioning and translation coverage/rollout order.
- Translation-resource packaging/versioning and translation coverage/rollout targets.
- Exact language registry source and translation-resource packaging/versioning.
- Final decision on whether teacher class context should ever influence teacher UI language; current recommendation is no.
- Full RLS/grants/function-ACL review for `classes`, `students` and `teacher_profiles` before choosing direct updates versus narrow RPCs.
- Safe behaviour when the active language changes while a form contains unsaved content.

## 9. Safety and implementation boundary

This document records design only. No SQL migration, schema modification, application code change, translation resource, preference value or live data update has been made as part of this design decision.

All repository documentation work is limited to `cloud-test`. The Supabase project identity/header ambiguity must be resolved before any database write. GitHub `main` and production Supabase must remain untouched.

## 10. Approved preference API boundary — 2026-11-25

The user approved dedicated database RPCs for all three first-stage preference owners:
- Teacher preference read/write, derived from the authenticated teacher identity (auth.uid()).
- Class default read/write, with authenticated teacher ownership validation for the target class.
- Student preference read/write, with the student derived from a verified access code; a browser-supplied student ID must never be authoritative.

These RPCs are limited to language-preference operations. Existing direct Supabase workflows for other teacher profile, class and student data remain unchanged unless a separate reviewed change is approved.

Read-only review of the existing student login boundary confirmed:
- student_portal_login(text) is SECURITY DEFINER and returns student ID, class ID, class name and student name; it does not return the access-code hash.
- verify_student_access_code(text) is SECURITY DEFINER and returns only student ID, class ID and student name after checking the submitted code against the stored hash and requiring active access/student records.
- Both currently use search_path=public; do not silently alter these legacy functions as part of localization. New SECURITY DEFINER preference RPCs should use a restricted search path (prefer an empty search_path), fully qualified object references, minimal return data, and explicit EXECUTE grants.
- Existing student login and verification function ACLs were inspected. The preference API must not broaden direct access to student_access or credential fields.

The user also approved using dedicated RPCs for all three preference operations while retaining existing direct workflows for unrelated profile/class/student information. This is an approved architecture decision; no migration, function, UI or data change has yet been made.


## 11. Initial language registry and platform fallback approved — 2026-11-25

The user approved the recommended initial interface-language registry and the platform fallback:

| Language | BCP 47 tag |
|---|---|
| English | `en` |
| Arabic | `ar` |
| French | `fr` |
| Spanish | `es` |
| Portuguese | `pt` |
| Hindi | `hi` |
| Urdu | `ur` |
| Swahili | `sw` |
| Chinese (Simplified) | `zh-Hans` |

**Platform fallback:** English (`en`).

The registry is extensible; adding a language later must not require a schema enum change. Registering a language does not imply that every screen or translation key is already translated. Track translation-resource coverage explicitly. If a selected language lacks a particular key, resolve that key through the English fallback and record the missing translation during development/testing. Keep language selection separate from educational content language.

This approval settles the initial registry and platform fallback only. It does not settle the time-zone preference policy, translation-resource packaging/versioning, or translation rollout/coverage targets. No SQL migration, application code, translation file or preference data has been changed by this decision.


## 12. Time-zone preference policy approved — 2026-11-25

The user approved the recommended time-zone arrangement:

- Persist time zones as IANA identifiers (for example, `Asia/Muscat`, `Europe/London`, and `Africa/Lagos`), never as fixed UTC offsets.
- Support individual time-zone preferences for teachers and students.
- Support a class default time zone for class scheduling and context.
- Use an individual's selected time zone for that person's date/time presentation; class defaults provide context where an individual has no preference, subject to the final display-resolution implementation.
- Keep authoritative timestamps, activity deadlines, expiry instants, grading and points operations server-controlled. Changing a display time zone must never move an already-established deadline, reset a countdown, or alter the underlying instant.
- Use a device/browser time zone only as a possible initial suggestion, not as an authoritative persisted choice without user confirmation.

This decision approves the preference scope and storage standard. The precise resolution rules for class-context displays versus individual displays must be implemented consistently and documented in the API/UI design. No schema migration, app code or preference data has been changed by this approval.
