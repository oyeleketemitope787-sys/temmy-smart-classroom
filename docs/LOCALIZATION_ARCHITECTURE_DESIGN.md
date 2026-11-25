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



## 13. Translation-resource architecture — recommended design (25 November 2026)

This section records an implementation recommendation, not a separately user-approved product constraint.

### 13.1 Resource format and ownership

Use source-controlled UTF-8 JSON translation resources, separated by language and functional namespace. Keep the English resource set as the canonical source for keys and fallback text.

Recommended layout when the localization layer is extracted from the current monolithic `index.html`:

```text
/locales/
  /en/
    common.json
    teacher.json
    student.json
    activities.json
    games.json
    reports.json
    settings.json
  /ar/
    common.json
    teacher.json
    student.json
    activities.json
    games.json
    reports.json
    settings.json
  /fr/
    ...
```

The initial namespaces are a practical starting point and may be split as the application grows. A namespace should represent a functional area, not an individual page or component. Keep shared navigation, buttons, generic validation and common status labels in `common`.

Do not create one enormous translation file per language. Load only the namespaces required by the active workflow, while ensuring the English fallback namespace is available whenever a translated namespace is loaded.

### 13.2 Stable key conventions

Use semantic, language-neutral keys grouped by namespace and purpose. Example JSON keys:

```json
{
  "dashboard": {
    "title": "Dashboard",
    "welcome": "Welcome, {name}"
  },
  "actions": {
    "save": "Save",
    "cancel": "Cancel"
  },
  "status": {
    "draft": "Draft",
    "live": "Live",
    "closed": "Closed"
  }
}
```

Conventions:
- Keys describe meaning and context, not the current English wording.
- Use consistent lower-camel-case segments.
- Keep persisted status/type codes independent of translation keys; map stable codes to display labels in the UI.
- Do not use English sentences as keys, concatenate translated fragments, or reuse a key where the meaning/context differs.
- Renaming/removing a key is a resource-contract change: update all callers and all language resources together.
- Dynamic values use named placeholders; translators must be able to reorder sentence elements.
- Plural/select messages must use a documented message format (prefer ICU MessageFormat-compatible syntax) rather than manually concatenated singular/plural strings. Select and pin a compatible parser/runtime during implementation; do not hand-roll a partial ICU parser.

### 13.3 Resource metadata, direction and fallback

The central language registry should own each language's BCP 47 tag, native display name, direction (`ltr`/`rtl`), enabled state and resource coverage metadata. Do not duplicate direction decisions in individual screens.

Each resource bundle should carry or be associated with:
- its language tag;
- a resource/schema version;
- the namespace name;
- the application/resource release identifier.

Resolution for a requested key:
1. Look in the active language's requested namespace.
2. If absent, look in the matching English namespace.
3. If still absent, emit a development diagnostic and use a safe non-empty diagnostic fallback in development; production must never render `undefined`, `null` or a raw missing-key token to the learner.

Missing translations should be measurable by language, namespace and key. A language must not be described as fully translated merely because it is present in the registry.

### 13.4 Coverage and quality checks

Add automated checks before expanding translations:
- Every key in each non-English namespace is valid JSON and has a matching English key.
- Every English key is reported as translated, intentionally deferred, or missing for each enabled language.
- Placeholder names and plural/select variables match the English source.
- No duplicate keys, invalid Unicode, accidental empty values or unsupported message syntax.
- All new UI text is sourced through the localization API; review new/changed UI code for hard-coded user-facing strings.
- RTL smoke tests cover navigation, forms, dialogs, tables, question tiles, mixed-script content and mathematical expressions.

Track coverage by namespace and key count. Do not block the whole application from using a language solely because some namespaces remain incomplete; show English fallback for missing keys and make coverage status visible to developers/administrators.

### 13.5 Translation workflow and versioning

- English is the canonical source language for resource keys and fallback text.
- Translation resources are reviewed source files committed with the application, not mutable strings stored in user profile rows.
- Changes to keys and English source text are reviewed with the relevant feature change.
- Translators receive context, placeholders and notes for ambiguous educational/assessment terminology.
- Keep resource schema versioning separate from the user's language preference and from database schema versioning.
- Do not send classroom content, student data or user-authored material to an external translation service as part of runtime UI localization.
- A resource bundle mismatch should fail safely to the English bundle and produce a developer diagnostic.

### 13.6 Initial rollout recommendation

Implement the resource loader and key conventions first, then complete the shared `common` namespace in English and Arabic as the first RTL validation pair. Add the remaining approved languages incrementally, with coverage reported per namespace. This is a sequencing recommendation, not a claim that Arabic or any other language is already translated.

No translation files, parser dependency, application code or UI have been added by this design section.

## 14. Time-zone resolution and display contract — recommended implementation detail (25 November 2026)

This section translates the approved IANA time-zone policy into deterministic display rules. It does not change the authoritative server-time policy.

### 14.1 Resolve by purpose, not by one global time zone

Use the following rules consistently:

| Display context | Time-zone resolution |
|---|---|
| Teacher's personal dashboard, account history and personal activity timestamps | Teacher's explicit time-zone preference; otherwise the relevant class default when the item is class-scoped; otherwise the device zone as an unpersisted display suggestion |
| Student's personal dashboard, personal history and personal activity timestamps | Student's explicit time-zone preference; otherwise the relevant class default; otherwise the device zone as an unpersisted display suggestion |
| Class timetable, class event, class session and class-wide schedule | Class default time zone; if none exists, the viewing user's explicit preference; otherwise the device zone as an unpersisted display suggestion |
| Activity deadline and countdown | The immutable server deadline instant is authoritative. Display it in the student's personal time zone, and identify the class time zone as contextual metadata where useful. Countdown is calculated from server time/deadline, never by converting or recalculating the deadline. |
| Audit events and points ledger | Preserve the server timestamp as an instant; display in the viewer's personal preference, with an explicit time-zone label when ambiguity matters. |

A user's explicit preference controls personal presentation. A class default controls the interpretation and presentation of class-wide schedules. Do not silently replace one with the other: when a class schedule is shown in a personal view, label the class time zone (for example, “Class time — Asia/Muscat”) or offer a clearly labelled personal-time equivalent.

### 14.2 Missing preferences and device suggestions

- A valid explicit IANA preference is used first according to the context table.
- If a class-scoped view has no class time zone, use the viewer's explicit preference.
- If no explicit preference applies, the browser/device IANA zone may be used for initial display and suggested in settings; do not persist it until the user confirms.
- If device-zone detection fails or returns an unsupported value, use UTC as the deterministic safe display fallback and show the zone label. UTC fallback is a presentation fallback only; it does not change stored instants.
- Never store a numeric offset such as UTC+4 as the preference. Validate identifiers against the runtime/server IANA time-zone database.

### 14.3 Scheduling and daylight-saving safety

- A scheduled local wall-clock time must be stored with its IANA time-zone identifier and the resolved UTC instant.
- For recurring schedules, retain the intended local time, recurrence rule and IANA zone so daylight-saving transitions do not shift the intended local schedule.
- For one-off deadlines, persist the resolved instant; a later preference or time-zone database change must not move it.
- When a local time is ambiguous or nonexistent during a daylight-saving transition, the scheduling workflow must explicitly resolve the ambiguity (or reject and request another time); do not silently guess.
- Server timestamps, activity start/deadline/expiry, submission cutoffs, grading and points events remain authoritative.

### 14.4 Locale and time zone are separate

BCP 47 interface language/locale and IANA time zone are separate preferences. Do not infer a time zone from a language, country, IP address or curriculum. Date/number formatting uses the selected interface locale; date/time conversion uses the resolved time zone.

No time-zone columns, UI, scheduling changes or database functions have been implemented by this design section.

## 15. Preference storage and RPC contract — design specification (25 November 2026)

This section consolidates the approved language-preference API boundary and the approved time-zone preference scope into a concrete, reviewable design. It is a design specification only. It does not create columns, tables, functions, migrations or application code.

### 15.1 Proposed additive preference fields

| Table | Field | Type | NULL meaning |
|---|---|---|---|
| `teacher_profiles` | `preferred_interface_language` | `text` | Use platform fallback |
| `students` | `preferred_interface_language` | `text` | Inherit class default, then platform fallback |
| `classes` | `default_interface_language` | `text` | Use platform fallback for students without an individual choice |
| `teacher_profiles` | `preferred_time_zone` | `text` | No explicit personal zone |
| `students` | `preferred_time_zone` | `text` | No explicit personal zone |
| `classes` | `default_time_zone` | `text` | No explicit class scheduling zone |

All six fields are nullable and additive. Language values are BCP 47 tags; time-zone values are IANA identifiers. Do not use enums, translated labels, numeric UTC offsets, or a credential/access-code field as the preference owner. Do not add default values that make an inherited preference look explicitly selected.

The three language fields and three time-zone fields are separate concerns. The approved first-stage RPC boundary below is specifically for language preferences. Time-zone persistence must use a separately reviewed API contract; do not silently expand the approved language RPCs to write time zones.

### 15.2 Language registry and server validation

Use a non-enum registry as the authoritative server-side allowlist. Recommended table: `public.interface_languages`, with:
- `language_tag text PRIMARY KEY` (BCP 47 tag);
- `native_name text NOT NULL`;
- `text_direction text NOT NULL CHECK (text_direction IN ('ltr','rtl'))`;
- `enabled boolean NOT NULL DEFAULT true`;
- optional resource-coverage metadata kept distinct from user preferences.

Seed the initially approved tags: `en`, `ar`, `fr`, `es`, `pt`, `hi`, `ur`, `sw`, `zh-Hans`. English remains the platform fallback (`en`). Arabic and Urdu are RTL; the other initial languages are LTR. Registry changes are data/configuration changes, not schema enum changes. A tag must be enabled before a preference RPC accepts it. A missing translation for an individual key still falls back to English; registry membership is not a claim of full translation coverage.

A setter accepts either NULL (clear the explicit preference) or an exact enabled registry tag. Reject empty strings, whitespace-padded tags, unsupported tags and disabled tags; do not silently normalize a malformed tag into another language.

### 15.3 Language RPC surface

Use six narrow RPCs, all `SECURITY DEFINER`, with `SET search_path = ''`, schema-qualified references, minimal results, and explicit EXECUTE grants:

| RPC | Parameters | Result / behaviour | Caller |
|---|---|---|---|
| `get_teacher_interface_language()` | none | Teacher's stored nullable individual language | `authenticated` |
| `set_teacher_interface_language(text)` | `p_language_tag` nullable | Set/clear caller's own preference; return stored nullable tag | `authenticated` |
| `get_class_default_interface_language(uuid)` | `p_class_id` | Class's stored nullable default; verify caller owns class | `authenticated` |
| `set_class_default_interface_language(uuid,text)` | `p_class_id`, nullable `p_language_tag` | Set/clear class default only after ownership check; return stored nullable tag | `authenticated` |
| `get_student_interface_language(text)` | `p_access_code` | Return only individual tag, class-default tag, effective tag and source code | `anon`, `authenticated` |
| `set_student_interface_language(text,text)` | `p_access_code`, nullable `p_language_tag` | Set/clear verified student's individual preference; return stored nullable tag | `anon`, `authenticated` |

Student getter result is a single row with four values: `individual_language`, `class_default_language`, `effective_language`, and `preference_source` (`individual`, `class`, or `platform`). Effective resolution is individual -> class -> `en`. The student setter changes only the individual field; setting NULL restores inheritance. Do not return student IDs, access-code hashes, class membership details, profile fields or any unrelated data.

The student RPCs must call the existing `verify_student_access_code(text)` helper internally, derive the permanent student ID and class from its verified result, and reject invalid/inactive access. Never accept a browser-supplied student ID. Do not change the existing login/verification function definitions or grants as part of this work.

Teacher RPC identity comes only from `auth.uid()`; require the matching `teacher_profiles` row. Class RPCs must verify `classes.teacher_id = auth.uid()` and return no information for a class not owned by the caller. The class ID is a lookup key, not proof of authority.

Revoke default `PUBLIC` execution. Grant teacher/class functions only to `authenticated`; grant student access-code functions only to the portal roles actually required (`anon` and `authenticated`). Do not grant direct browser table access to the registry or preference columns merely to support these RPCs. Review function ownership, helper execution rights, RLS bypass behaviour and exact role grants before SQL is drafted.

### 15.4 Time-zone validation and separate API boundary

The three proposed time-zone fields store IANA names such as `Asia/Muscat`, `Europe/London` and `Africa/Lagos`. Validate a submitted value against the PostgreSQL IANA time-zone catalog (for example, `pg_timezone_names`) and reject abbreviations, fixed offsets and unknown names. NULL clears an explicit preference. The application may suggest the device's detected IANA zone, but persistence requires user confirmation.

The approved policy requires individual teacher/student preferences and a class default. The precise read/write RPC names, student access-code handling and whether time-zone preferences are exposed through dedicated RPCs or a carefully reviewed combined settings API are not yet approved. Keep them out of the language RPC signatures above until that separate contract is agreed. Any eventual student time-zone RPC must derive identity from the verified access code, and any class time-zone write must enforce teacher ownership.

### 15.5 Resolution and consistency invariants

- Teacher interface language: individual -> platform fallback. A class default never overrides the teacher's choice.
- Student interface language: individual -> class default -> platform fallback.
- Teacher/student personal time display: explicit individual IANA preference; if absent, apply the documented class-context rule where applicable, then device suggestion without persisting it.
- Class-wide schedule display: class IANA default; otherwise viewer's explicit zone; otherwise device suggestion. Label class time when showing a class schedule in a personal-time view.
- Language and time zone are independent; never infer one from the other, country, IP address or curriculum.
- Changing either display preference must not alter server timestamps, deadlines, expiry instants, grading, points, or an already-running countdown.
- A missing/disabled stored language is ignored safely and resolution continues through the fallback chain. Invalid stored time-zone data must fall back safely and be surfaced for repair; it must never shift the underlying instant.

### 15.6 Pre-migration verification checklist

Before preparing or applying SQL, re-inspect the exact test project's schema and verify:
1. Exact columns, types, nullability, constraints, FKs and existing indexes on `teacher_profiles`, `students` and `classes`.
2. Current table grants and RLS policies, including column-level privileges.
3. Exact definitions, owners, SECURITY DEFINER status, search paths and ACLs of `verify_student_access_code(text)` and any helper it invokes.
4. Whether `interface_languages` or an equivalent registry already exists; do not create a duplicate.
5. Existing function names/signatures to avoid collisions.
6. PostgreSQL role availability and the actual Supabase API roles used by the portals.
7. Test-project identity before any write; production project and GitHub `main` remain out of scope.

Only after these checks should an additive migration be drafted. The migration must be reviewed as a complete unit, and the user must explicitly approve applying it to the isolated test project. No migration is authorised by this design document.


## 16. Direct-write guard and migration review — 2026-11-25

The user approved a narrowly scoped database safeguard: browser-role writes must not change localization preference columns directly; the six approved language RPCs remain the browser-facing write boundary. Existing unrelated profile, class and student writes, existing RLS policies and legacy login functions must remain unchanged.

A draft migration is now present at `supabase/migrations/20261125000300_add_localization_preferences.sql` on `cloud-test`. It proposes:
- The extensible `interface_languages` registry and the nine approved language tags.
- Nullable language and IANA time-zone preference columns on teacher, student and class rows.
- Foreign keys from language preference fields to the registry.
- An invoker trigger guard on each owner table. For direct `anon`/`authenticated` writes, it rejects only INSERT/UPDATE attempts that set or change preference fields; unrelated columns remain unaffected. The intended SECURITY DEFINER RPCs run under their owner role and can update the fields.
- The six approved language RPCs, with teacher identity from `auth.uid()`, class ownership checks, student identity derived through the existing access-code verifier, empty search paths, and explicit grants.

This is a draft, not an approved or executed migration. It still requires complete SQL review and execution-based verification, particularly:
1. Confirm the migration is executed by the intended database owner so the SECURITY DEFINER functions and invoker trigger behave as designed.
2. Test direct preference writes under real `anon` and `authenticated` roles, and verify unrelated column updates still work.
3. Test teacher ownership, cross-teacher class denial, valid/invalid student access codes, NULL inheritance and all fallback paths.
4. Inspect installed function owners, configurations, ACLs and trigger definitions after application in the isolated test project.
5. Confirm the Supabase dashboard is on `temmy-smart-classroom-test` immediately before any eventual execution. The SQL file itself cannot reliably distinguish two Supabase projects that both use the default database name.

The three time-zone columns are included as nullable storage only. No time-zone RPC is included; that API remains separate. No migration has been run, no preference data has been written, and production Supabase/GitHub `main` remain untouched.


### 16.1 Static SQL review notes

A first static review found and corrected two migration preflight omissions:
- The preflight now rejects collisions with the internal trigger-guard and language-validation helper function signatures, in addition to the six public RPC signatures.
- The preflight now requires `current_user = 'postgres'`. This makes the intended owner of the newly created SECURITY DEFINER functions and the trusted trigger execution context explicit, rather than relying on an assumption about the migration runner.

Remaining verification gates before any execution:
- Confirm the dashboard is connected to the isolated test project immediately before running SQL. The migration cannot distinguish Supabase projects that share the default database name.
- Confirm the current Supabase SQL Editor role is `postgres` and the preflight succeeds.
- Execute behavioural tests under actual `anon` and `authenticated` roles to prove the invoker trigger blocks preference-column changes but does not block unrelated-column changes.
- Test student access-code failure/success behaviour and consider rate limiting/abuse controls for anonymous access-code RPC calls. The draft does not add a new rate limiter.
- Verify SECURITY DEFINER function owners, empty search paths, ACLs and helper execution after application.
- Verify teacher identity, cross-teacher class denial, NULL inheritance and all three student resolution sources.

The migration remains a draft. No Supabase SQL has been executed.


## 17. Student language RPC exposure decision — 2026-11-25

Inspection of the existing test database found:
- `student_portal_login(text)` is owned by `postgres`, SECURITY DEFINER, and executable by `anon`, `authenticated`, and `postgres`.
- `verify_student_access_code(text)` is owned by `postgres`, SECURITY DEFINER, and executable by `authenticated` and `postgres`; it is not executable by `anon`.
- `student_access` has RLS enabled, no explicit RLS policies, and no ordinary SELECT/INSERT/UPDATE/DELETE grants to browser roles.
- The `student_access` table has a unique constraint on `student_id`, but no visible failed-attempt counter or lockout columns.
- No matching database triggers for access/login/rate limiting were found. The current browser login source calls `student_portal_login`; no rate-limit logic was found in that inspected login path. This does not rule out gateway/hosting-level controls.

Decision: do not expose the new student language RPCs to `anon` or `authenticated`. The draft migration now revokes browser execution and grants those two RPCs only to `service_role`; each function also checks `auth.role() = 'service_role'`. The service-role key must remain server-side and must never enter `index.html` or other browser bundles.

Required next component: a dedicated Supabase Edge Function (or equivalent trusted server endpoint) for student language get/set. It must validate request shape, apply persistent/distributed rate limiting before attempting code verification, avoid logging access codes, call the service-role-only RPCs, return only the minimal language preference payload, and use generic authentication failures. A process-local in-memory limiter alone is insufficient for a horizontally scaled/serverless deployment. The exact persistent limiter design and Edge Function deployment/configuration remain to be designed and reviewed before implementation.

The existing `student_portal_login` and `verify_student_access_code` functions are not modified by this localization work. The existing login flow remains unchanged until a separately tested integration change is approved.


## 18. Student Edge Function design record

A proposed request/response contract, security requirements, rollout sequence and rate-limiter decision are recorded in `docs/ADR_STUDENT_LOCALIZATION_EDGE_FUNCTION.md`. The design proposes a single `student-language-preference` Edge Function and a shared atomic rate limiter. Upstash Redis is the preferred option only if the user approves the external dependency; a Postgres-backed atomic limiter remains an alternative. Initial thresholds are illustrative and are not approved configuration.

No Edge Function source has been written or deployed. No Redis account or secret has been configured. No database migration has been applied.
