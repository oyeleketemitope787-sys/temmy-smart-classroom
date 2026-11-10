# Temmy Smart Classroom — Phase A Live Database Security Verification

**Verification date:** 2026-11-10  
**Status:** Read-only verification snapshot; not a security certification  
**Repository:** `oyeleketemitope787-sys/temmy-smart-classroom`  
**Branch for this report:** `security-review/student-login-hardening`  
**Supabase project reviewed:** `temmy-smart-classroom-test`  
**Dashboard environment label observed:** `main` / `PRODUCTION`  
**Protected branches:** `main` and `cloud-test` — no repository changes to either  
**Hosted changes:** None. No SQL writes, grants/revokes, migrations, function replacements, deployments, or test data changes were performed.

This report records read-only observations supplied from the live Supabase project on 2026-11-09 and 2026-11-10. It supplements, and does not replace, the approved business and architecture decisions in `CONSOLIDATED_SECURITY_DECISION_AND_READINESS_REVIEW_2026-11-09.md`.

## 1. Executive outcome

**Release decision: NOT READY for production implementation, SQL execution, or deployment.**

The Phase A review has now examined the visible public schema inventory, column information (with a noted truncation), constraints, indexes, RLS policies, table grants, effective table privileges, function privileges and definitions, table triggers, event triggers, API dashboard settings, GraphQL availability, default privileges, table ownership, and database role attributes.

The strongest confirmed risks concern:
- trust of browser-supplied game scores;
- missing marketplace stock validation/decrement and incompatible batch semantics;
- direct authenticated write access to the point ledger;
- broad authenticated updates to student activity records;
- access-code entropy and missing controls against repeated guessing;
- punctuality awards/deductions that do not implement the approved cap and balance rules;
- privileged `SECURITY DEFINER` functions running as the table owner, which bypasses ordinary RLS because that owner has `BYPASSRLS`;
- unresolved Data API dashboard-versus-grant discrepancy.

Positive controls exist, including RLS enabled on all 16 inventoried public tables, no ordinary table triggers, no anon CRUD grants on the inventoried tables, teacher/student ownership checks in several functions, bcrypt-hashed student codes, and session expiry/single-use checks.

**No finding in this report is a claim that exploitation has occurred.** Findings describe observed implementation behaviour and risk.

## 2. Scope and verification limitations

### Verified in the live project

- 16 ordinary/partitioned tables were inventoried in `public`.
- All 16 had RLS enabled; none had FORCE RLS enabled.
- All 16 were owned by `postgres`.
- Constraints and indexes were inventoried.
- RLS policies and effective data privileges for `anon`, `authenticated`, and `service_role` were inspected.
- 20 `public` function catalog rows were inventoried; each was owned by `postgres` and marked `SECURITY DEFINER`. One, `rls_auto_enable`, is an event-trigger function rather than a normal application RPC.
- Security-sensitive function definitions were individually reviewed, including access-code creation/verification, student login, student and teacher game sessions, game result recording, student activities, point history, messaging, marketplace purchases, and punctuality.
- No non-internal table triggers were returned for `public`.
- PostgreSQL event triggers, API dashboard settings, GraphQL placeholder, default privileges, table owners and role attributes were inspected.
- The Edge Functions dashboard showed no deployed Edge Functions in the selected project/branch view at the time of inspection.

### Incomplete or not established

- The supplied column-inventory export ended partway through `student_game_sessions`; the complete live column inventory for that table was not visible in the captured result.
- The Data API dashboard showed 0 of 16 tables and 0 of 20 functions as exposed, while database ACL checks showed existing grants to API roles. The actual HTTP/PostgREST reachability of individual tables and functions was not smoke-tested.
- `current_setting('pgrst.db_schemas')`, `pgrst.db_extra_search_path`, and `pgrst.db_pre_request` returned NULL in the SQL Editor session. No corresponding `pgrst.*` settings were found in the inspected `authenticator` role-level configuration. This does not establish the complete runtime PostgREST configuration, which may be supplied outside that session/role configuration.
- The Data API setting `Automatically expose new tables` was observed Off. The dashboard showed the exposed schemas `public` and `graphql_public`.
- An actual HTTP request using the project API URL and a non-sensitive test call has not yet been performed.
- Complete application caller mapping for every direct table/RPC operation remains an implementation gate.
- No live penetration test, exploit test, concurrency test, failure-injection test, or load test was performed.

## 3. Schema, integrity constraints, and indexes

### 3.1 Public tables

The 16 inventoried tables are:

`audit_log`, `class_activities`, `classes`, `group_members`, `groups`, `marketplace_purchase_requests`, `marketplace_rewards`, `messages`, `point_transactions`, `punctuality_records`, `purchases`, `student_access`, `student_activity_records`, `student_game_sessions`, `students`, and `teacher_profiles`.

All are owned by `postgres`, have RLS enabled, and have FORCE RLS disabled.

### 3.2 Important constraint observations

- `point_transactions`: primary key and student/teacher foreign keys were found; no CHECK constraint was found for point sign or action classification.
- `student_activity_records`: primary key and foreign keys were found; `activity_id` is nullable; no unique constraint on `(activity_id, student_id)` was found. The approved design continues to preserve existing duplicate-submission semantics until those are verified; do not add this unique constraint as an assumed fix.
- `marketplace_rewards`: price is an integer and stock is nullable; no CHECK constraint for positive price or nonnegative finite stock was found.
- `marketplace_purchase_requests`: primary key is `(teacher_id, request_id)`; no foreign keys were shown for `reward_id` or UUIDs inside `student_ids`.
- `student_game_sessions`: the returned constraints included primary key and unique `session_token`; no foreign keys for student/class were shown in the returned inventory.
- `student_access`: unique constraint on `student_id`, supporting one access row per student.
- `punctuality_records`: checks enforce nonnegative points and permitted status strings; unique constraint on `(student_id, class_id, punctuality_date)`.
- `group_members`: unique constraint on `(group_id, student_id)`.
- `classes` and `groups`: unique name constraints scoped to teacher/class respectively.

These are declared-constraint observations only. They do not establish that all business relationships are enforced.

### 3.3 Index inventory

The index query returned 22 indexes, all primary-key or unique indexes. No ordinary non-unique lookup indexes appeared in the result.

Columns worth a query-plan/performance review include student/teacher/time lookup columns on point transactions, student/activity/teacher columns on activity records, student/expiry/used columns on game sessions, `code_hash` on student access, and student/teacher/reward/time columns on purchases, messages and audit records.

Do not create indexes solely from this list; inspect real query patterns, cardinality, table sizes and query plans first.

## 4. RLS policy and direct privilege findings

### 4.1 RLS policies

RLS is enabled on all 16 tables, but FORCE RLS is disabled on all of them.

High-priority policy observations:
- `point_transactions` INSERT policy checks that the teacher ID equals `auth.uid()` and that the student belongs to a class owned by that teacher. It does not limit the points amount, action type, or source.
- `student_activity_records` UPDATE policy checks `teacher_id = auth.uid()` in USING and WITH CHECK, without revalidating the student's class or activity relationship in the replacement row.
- `class_activities` UPDATE policy checks teacher ID but does not repeat the class ownership EXISTS check present in the INSERT policy.
- `audit_log` has teacher INSERT/SELECT policies, but the effective table privilege query showed no SELECT or INSERT grant to `authenticated`; the policy alone does not grant access.
- `messages` has teacher policies, but the effective privilege query showed no direct CRUD privileges to `authenticated`; the inspected SECURITY DEFINER messaging functions are the visible access path.
- `groups` has duplicate permissive policies for several operations. Duplicate permissive policies do not add a stricter condition; PostgreSQL combines permissive policies using OR.
- Several sensitive tables (including `student_access`, `student_game_sessions`, and `marketplace_purchase_requests`) had no direct authenticated CRUD privileges in the effective privilege results. Their intended access path must be validated through the relevant trusted functions.

### 4.2 Effective table privileges

The effective privilege query showed:

- `anon`: no SELECT, INSERT, UPDATE, DELETE, or TRUNCATE on the 16 inventoried public tables.
- `authenticated`: CRUD on classes, students, class activities, groups, group members, and marketplace rewards; SELECT/INSERT on point transactions; SELECT/INSERT/UPDATE on student activity records; SELECT/INSERT/UPDATE/DELETE on purchases; SELECT/INSERT/UPDATE on teacher profiles.
- `authenticated`: no direct CRUD on audit_log, messages, punctuality_records, student_access, student_game_sessions, or marketplace_purchase_requests in the returned effective privilege results.
- `service_role`: BYPASSRLS is true. Effective table privileges were narrower than a full CRUD grant on every table; the query did show TRUNCATE on all 16 tables and CRUD on classes, marketplace rewards and purchases.

The direct point-ledger INSERT grant and activity-record UPDATE grant are significant because RLS policies permit authenticated teachers to perform those operations under the conditions described above.

### 4.3 Implication

RLS and SQL grants are separate controls. An RLS policy does not confer a table privilege, and a table privilege does not bypass RLS. The effective API access question must consider exposed schema, grants, RLS and the actual API runtime.

## 5. Function inventory and privileged execution

The catalog query returned 20 rows in `public`. Every returned function was owned by `postgres` and marked `SECURITY DEFINER`. The function list included `rls_auto_enable`, which is used as an event-trigger function and is not an ordinary application RPC.

The `postgres` role has `BYPASSRLS = true`; all 16 tables are owned by `postgres`; FORCE RLS is disabled. Therefore, these owner-executed SECURITY DEFINER functions do not receive ordinary RLS protection from the table policies. Their own internal authorization and validation checks are critical.

### 5.1 Student access codes

- `generate_student_access_code` authenticates the teacher with `auth.uid()`, checks the student is active and belongs to a class owned by that teacher, stores a bcrypt hash, and replaces the existing student access row on conflict.
- It generates six random bytes but keeps only the first eight hexadecimal characters: effective code space is 16^8 = 4,294,967,296 possibilities (32 bits).
- No visible rate limit, failed-attempt counter, lockout or expiry check was found in the inspected generation/verification functions or table columns shown.
- `verify_student_access_code` uses `extensions.crypt(p_access_code, sa.code_hash) = sa.code_hash` and checks the access row and student are active. It does not explicitly validate NULL/blank input or check class active status. It has anonymous EXECUTE permission in the catalog result.
- `student_portal_login` performs an active-class check before returning details and updates last-login timestamps, but does not verify that the UPDATE affected a row after verification.
- Code rotation is implemented, but overlapping generation requests can cause a previously returned code to be invalidated by a later concurrent request.

### 5.2 Student/game sessions and game scoring

- `start_student_game_session` verifies the access code and active class, then creates a UUID token expiring after 30 minutes. It does not enforce a game allowlist, explicit game-ID format validation, a session-creation rate limit, or the approved class/student lock order.
- `start_teacher_game_session` checks teacher identity and student/class ownership, accepts any non-empty game ID, and creates a 30-minute session without rate limiting or locking/revalidating the class and student.
- `get_student_game_sessions` returns a student's unexpired, unused session tokens to a caller with a valid access code. It has no result limit or class-active check; it is executable by `anon`.
- `record_student_game_result` locks the session row, checks single use, expiry, and game-ID match, and checks the class is active. However, it trusts browser-supplied score, max score and game name, does not independently verify answers, and lacks robust NULL/input validation. It uses `LEAST(p_score, p_max_score)` for awarded points. It does not revalidate current student active/class membership. This is a critical trust-boundary weakness.
- Future game platform must not use this function as its trusted scoring authority. Trusted server-side scoring and a new Gateway contract are required.

### 5.3 Student activities

- `get_student_live_activities` filters to the verified student's class and activities with `status = 'live'` and `active = true`; it returns the student's own answer, awarded points and notes. It does not separately check class active status and has no pagination. Duplicate activity records can duplicate output rows.
- `submit_student_activity` validates nonblank answer, access code, activity existence, class match and `status = 'live'`. It does not check the activity's `active` flag or active class state, and it checks for duplicates before inserting without a unique constraint or concurrency-safe lock. Concurrent duplicate submissions can race. It accepts no explicit maximum answer length and awards zero points at submission.
- Preserve the currently intended duplicate behaviour until callers and actual deployment behaviour are reconciled; do not add a unique constraint by assumption.

### 5.4 Point history and punctuality

- `get_student_point_history` filters history to the student verified by access code and schema-qualifies objects with an empty search path. It returns all history without pagination; it is executable by `anon` and does not independently check class active status.
- `record_student_punctuality` validates teacher, class ownership, student membership, status and nonnegative points, and adjusts points by delta. However, it does not enforce the approved 20-point system-wide per-student cap, does not clamp negative deltas to available balance, does not require class active, and does not follow the approved global class-before-student lock order. It has a unique student/class/date constraint but concurrent first-time insert attempts can still produce a unique-constraint error. Array/NULL/duplicate/size validation is incomplete.

### 5.5 Messaging

The reviewed messaging functions generally derive teacher identity from `auth.uid()` or student identity from a verified access code, filter messages by student/teacher, validate non-empty message text and enforce a 2,000-character maximum.
- `get_student_messages` and `mark_student_messages_read` check the current class is active and limit actions to the verified student/current teacher.
- `get_teacher_messages`, `mark_teacher_messages_read`, and `send_teacher_message` derive teacher identity from `auth.uid()` and verify the student is in an active class owned by the teacher.
- `send_student_message` verifies the access code and associates the message with the current active class teacher.
- No visible rate limiting or idempotency protection was found for message sends. Ownership checks are not protected by the approved class/student locking rule, so concurrent student transfers/class changes need consideration.
- Student message retrieval exposes only the student's own messages but returns teacher first/last names; historical message visibility after a transfer is tied to current teacher in the student view.

### 5.6 Marketplace purchases

`purchase_marketplace_reward` has positive teacher identity, reward ownership, active-state, student ownership and positive price checks. It canonicalises the student ID array by sorting, stores a teacher-scoped request ID, locks a request row, checks balances, writes point debits and purchase history, then stores a successful result in the same transaction.

Critical discrepancies against the approved marketplace rules:
1. It never checks or decrements finite stock; out-of-stock and overselling protections are missing.
2. It processes a batch all-or-nothing. One insufficient balance aborts all students, rather than independent per-student outcomes.
3. Its lock order is request → reward → students and it does not lock relevant class rows. This conflicts with the approved order: request → sorted class rows → student → reward/operation rows → writes.
4. Expected rejections raise exceptions. Those exceptions roll back the request row, so durable expected-rejection idempotency/outcome storage is not implemented.
5. No explicit success or rejection audit write appears in the function body. Trigger inspection returned no ordinary public table triggers.
6. Request ID reuse with different reward/student IDs raises an exception, but a canonical payload hash is not stored in the current request table/function.
7. There is no explicit maximum batch-size validation.

This function is not compliant with the approved purchase design and must be redesigned, not patched piecemeal.

## 6. Triggers and event triggers

- The ordinary table-trigger query returned no non-internal triggers attached to tables in `public`.
- An enabled event trigger `ensure_rls` runs at `ddl_command_end` for `CREATE TABLE`, `CREATE TABLE AS`, and `SELECT INTO`. It calls `public.rls_auto_enable()`, a SECURITY DEFINER function owned by postgres with `search_path=pg_catalog`. It attempts to enable RLS on new public tables.
- The event-trigger function catches all exceptions and logs rather than rethrowing. Therefore, table creation may succeed even if RLS enabling fails.
- It does not enable FORCE RLS or create policies. It does not repair existing tables.
- Other observed event triggers are Supabase platform hooks for GraphQL placeholder maintenance, pg_cron, pg_net, and PostgREST schema reloads.

## 7. Roles, owners, and default privileges

### 7.1 Role attributes

- `anon`: not superuser, no login, no BYPASSRLS.
- `authenticated`: not superuser, no login, no BYPASSRLS.
- `authenticator`: LOGIN, NOINHERIT, no BYPASSRLS; role-level settings included Supabase preload libraries and 8-second statement/lock timeouts. No `pgrst.*` override appeared in the inspected role config.
- `postgres`: not superuser, LOGIN, can create roles/databases, BYPASSRLS.
- `service_role`: no login, BYPASSRLS; its effective table privileges were inspected separately.
- `supabase_admin`: superuser, LOGIN, can create roles/databases, BYPASSRLS. It is a privileged platform role, not an application identity.

### 7.2 Table ownership and RLS bypass

All 16 existing public tables are owned by `postgres`, and `postgres` has BYPASSRLS. FORCE RLS is disabled. All 20 inventoried functions were owned by `postgres` and marked SECURITY DEFINER. This is a material trust boundary: each privileged function must perform complete authorization and validation itself.

### 7.3 Default privileges

The inspected schema-level defaults for objects created by `postgres` in `public` were:
- Tables: owner gets full privileges; `anon` and `authenticated` retain REFERENCES/TRIGGER/MAINTAIN, while `service_role` has TRUNCATE/REFERENCES/TRIGGER/MAINTAIN; CRUD grants were not included in that schema-specific default ACL.
- Functions: schema-specific ACL showed owner EXECUTE.
- Sequences: owner privileges only.

For objects created by `supabase_admin` in `public`, schema-specific defaults were broad:
- Tables: `anon`, `authenticated` and `service_role` receive broad table privileges.
- Functions: EXECUTE is granted to those roles.
- Sequences: USAGE/SELECT/UPDATE are granted to those roles.

The query inspected schema-specific `pg_default_acl` rows only; global default ACLs (namespace OID 0), including any global PUBLIC function EXECUTE default, were not inspected in that query. Do not infer the complete default function ACL from the schema-specific rows alone.

The Data API dashboard showed Automatically expose new tables Off. Supabase documents that this setting affects default grants for newly created objects and does not revoke grants already present on existing tables. Consequently, existing ACLs must be assessed individually.

## 8. Data API and GraphQL findings — unresolved discrepancy

Observed dashboard settings:
- Data API enabled.
- Exposed schemas: `public` and `graphql_public`.
- Dashboard displayed 0 of 16 tables and 0 of 20 functions as exposed.
- Automatically expose new tables was Off.

Observed database facts:
- `anon`, `authenticated`, and `service_role` have USAGE on `public`, `graphql_public`, and `extensions`.
- Effective table privilege checks show authenticated table grants on several public tables.
- Function privilege checks show EXECUTE for `anon` and/or `authenticated` on several SECURITY DEFINER functions, including student code, portal, messaging, activity, and game operations.
- The Data API dashboard count and actual effective grants therefore do not yet reconcile.
- Supabase's current documentation states that grants determine whether roles can reach tables/functions through the Data API and RLS determines which rows they can access. It also states that the new default-exposure setting does not remove grants already present on existing tables.
- `current_setting('pgrst.db_schemas')`, `pgrst.db_extra_search_path`, and `pgrst.db_pre_request` returned NULL in SQL Editor. The inspected `authenticator` role-level settings had no `pgrst.*` entries. These observations do not reveal the complete PostgREST runtime configuration.

### GraphQL

- The `pg_graphql` extension is NOT INSTALLED.
- `graphql_public.graphql(text,text,jsonb,jsonb)` exists and is executable by anon/authenticated.
- Its body is a placeholder returning the message that pg_graphql is not enabled. It is not a functioning GraphQL query engine in this state.

### Edge Functions

The Supabase Edge Functions dashboard for the selected project/branch showed “Deploy your first Edge Function” and no deployed functions. The `game-result-gateway` source previously inspected is review-branch code, not a deployed Edge Function. This should be rechecked immediately before implementation planning.

### Required next verification

Perform a harmless, read-only HTTP/PostgREST smoke test using the project’s own API URL and a non-sensitive invalid student code against a read-only verification RPC, without sharing or pasting API keys into chat. Record the HTTP status and response only. This will distinguish a route that is actually callable from a SQL ACL that merely exists in the catalog. Do not test real student codes or invoke write-capable functions.

## 9. Updated risk register

| Ref | Severity | Finding | Required design response |
|---|---|---|---|
| PA-01 | Critical | Browser-supplied game score/max trusted by live result function | New server-side trusted scoring; do not reuse current function as authority |
| PA-02 | Critical | Marketplace stock is neither checked nor decremented | Atomic finite-stock validation/decrement and concurrency tests |
| PA-03 | High | Marketplace batch is all-or-nothing | Independent per-student outcome model |
| PA-04 | High | Direct authenticated point-ledger INSERT | Inventory callers; remove browser direct write in a separately approved change |
| PA-05 | High | Broad activity-record UPDATE | Narrow column/update boundary and validated trusted scoring workflow |
| PA-06 | High | Student code only 32-bit effective entropy | Increase code entropy and design rate limiting/expiry/lockout |
| PA-07 | High | No visible custom-RPC rate limit for student code endpoints | Abuse-control design and tests |
| PA-08 | High | Punctuality cap and deduction clamp are missing | Enforce approved 20-point cap and nonnegative balance |
| PA-09 | High | SECURITY DEFINER functions owned by BYPASSRLS table owner | Harden each function and define least-privilege execution/owner model |
| PA-10 | High | API dashboard exposure count conflicts with effective grants | Perform harmless HTTP verification and reconcile API surface |
| PA-11 | High | Marketplace/other transaction functions do not follow approved global lock order | Redesign with class-before-student lock protocol |
| PA-12 | Medium/High | Student activity duplicate check can race | Define preserved semantics and race behaviour without assumed uniqueness change |
| PA-13 | Medium | No ordinary public table triggers; no automatic transaction audit found in trigger inventory | Implement explicit atomic audit in trusted transaction functions |
| PA-14 | Medium | No ordinary lookup indexes in 22-index inventory | Review real query plans and add only justified indexes |
| PA-15 | Medium | `ensure_rls` logs and suppresses errors | Operational monitoring and safe migration review; no assumption that RLS always enabled successfully |
| PA-16 | Medium | Student-facing history/session/activity functions have no pagination limits | Add bounded, paginated reads where appropriate |

Severity reflects design risk and intended system use, not observed exploitation.

## 10. Remaining Phase A tasks

1. Reconcile Data API UI count against actual PostgREST route behaviour using a harmless invalid-code, read-only RPC test.
2. Inspect global default ACL rows (not just schema-specific ACLs) and review routine ACLs for the 20 function rows, distinguishing PUBLIC grants from role-specific grants.
3. Complete the truncated column inventory for `student_game_sessions` and any other missing column output.
4. Complete the browser/application caller map on the review branch, including all direct .from() calls and .rpc() calls; identify every writer of point ledger and activity score fields.
5. Recheck the Edge Functions dashboard immediately before implementation planning.
6. Record table/function privilege evidence in a final per-object matrix.
7. Reconcile the live findings against approved transaction business rules and update the review-only SQL drafts. Do not execute them.

## 11. Phase A disposition and next phases

**Phase A is substantially advanced but not fully closed.** The database structure, RLS policies, effective grants, privileged functions and triggers have been examined. The unresolved API-route check, global default ACL check, incomplete column output, and complete browser caller map remain.

Recommended sequence:
- Finish the four remaining read-only items above.
- Update the consolidated security decision document with confirmed findings and the complete Phase A risk register.
- Reconcile all SQL design drafts against approved rules, identity model, audit/rejection model, and global locking order.
- Only after separate explicit approval, provision a fresh disposable PostgreSQL environment and run syntax, ACL, functional, concurrency, failure-injection and idempotency tests.
- Keep classroom launch independent of the future game platform.
- Implement Temmy Gateway and a separate new game project only after the classroom security and launch gates are met.

**No production SQL execution, migrations, grants/revokes, code deployment, Edge Function deployment, or application changes are authorized by this report.**

## 12. Official Supabase references consulted

- [Breaking Change: Tables not exposed to Data and GraphQL API automatically (2026-04-28)](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically) — existing table grants remain; the new default changes exposure of newly created objects.
- [Creating API Routes](https://supabase.com/docs/guides/api/creating-routes) — Postgres grants determine whether objects are accessible through the Data API.
- [Securing your API](https://supabase.com/docs/guides/api/securing-your-api) — grants and RLS are separate access-control layers; default privileges and API pre-request checks.
- [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security) — RLS policies control rows, while grants control access to the object.
