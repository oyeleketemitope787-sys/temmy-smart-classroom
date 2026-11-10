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


## 13. Follow-up verification — global and schema-specific default privileges (2026-11-10)

A complete `pg_default_acl` inventory was subsequently run, including both global and schema-specific rows. The result contained **no global (`defaclnamespace = 0`) default-privilege rows**. All returned rows were schema-specific.

PostgreSQL's built-in default for newly created functions grants EXECUTE to `PUBLIC`. PostgreSQL documents that per-schema default privileges are additive to global defaults and cannot revoke privileges granted globally. Therefore, the absence of a global default-privilege override means the built-in PUBLIC EXECUTE default remains in effect for future functions, subject to the effective current role and creation context.

Specific implications from the returned rows:

- For functions created by `postgres` in `public`, the schema-specific default ACL shown grants EXECUTE to the owner. It does not remove the built-in global PUBLIC EXECUTE default.
- For functions created by `supabase_admin` in `public`, the schema-specific default ACL additionally grants EXECUTE to `anon`, `authenticated`, and `service_role`; the global PUBLIC EXECUTE default also remains.
- For tables created by `supabase_admin` in `public`, the schema-specific defaults grant broad table privileges to `anon`, `authenticated`, and `service_role`.
- For tables created by `postgres` in `public`, the schema-specific defaults shown do not grant SELECT/INSERT/UPDATE/DELETE to `anon` or `authenticated`; they do include REFERENCES/TRIGGER/MAINTAIN for those roles and TRUNCATE/REFERENCES/TRIGGER/MAINTAIN for `service_role`.
- Additional broad defaults were observed for selected Supabase-managed schemas (including `storage`, `graphql`, and `graphql_public`). These are schema-specific and should be treated in the context of each schema's purpose and actual exposure.

These defaults affect future objects created by the relevant owner; they do not retroactively change existing classroom object grants. Existing routine ACLs still require per-function inspection to distinguish explicitly granted roles from PUBLIC. The existing Data API dashboard/ACL reachability discrepancy remains open.

**Risk update:** Treat future routine creation in `public` by `postgres` or `supabase_admin` as requiring explicit privilege review. Before creating a privileged function, ensure the intended EXECUTE audience is explicitly established and unwanted PUBLIC access is removed as part of the same controlled creation transaction or approved migration. For future tables created by `supabase_admin` in `public`, broad default grants require particular caution.

This is a read-only finding. No default privileges were altered.

Official PostgreSQL references:
- [ALTER DEFAULT PRIVILEGES — PostgreSQL current documentation](https://www.postgresql.org/docs/current/sql-alterdefaultprivileges.html)
- [Privileges — PostgreSQL current documentation](https://www.postgresql.org/docs/current/ddl-priv.html)

## 14. Revised remaining Phase A tasks

The global and schema-specific default-privilege inventory is now complete. The following items remain:

1. Reconcile Data API dashboard counts against actual PostgREST route behaviour using a harmless invalid-code, read-only RPC test.
2. Complete the truncated column inventory for `student_game_sessions` and any other missing column output.
3. Complete the browser/application caller map on the review branch, including every direct `.from()` and `.rpc()` operation and every writer of point ledger and activity score fields.
4. Recheck the Edge Functions dashboard immediately before implementation planning.
5. Inspect effective per-function ACLs for all 20 function inventory entries, explicitly identifying `PUBLIC` grants separately from grants to `anon`, `authenticated`, and `service_role`.
6. Record the final table/function privilege evidence in a per-object matrix.

No production SQL execution, migrations, grants/revokes, code deployment, Edge Function deployment, or application changes are authorized by this report.


## 15. Follow-up verification — effective per-function EXECUTE ACLs (2026-11-10)

The `aclexplode(COALESCE(proacl, acldefault(...)))` inventory was run for the 20 public function catalog rows. It confirms the following explicit PUBLIC EXECUTE grants:

- `get_student_game_sessions(text)`
- `get_student_live_activities(text)`
- `record_student_game_result(uuid,text,text,integer,integer)`
- `start_student_game_session(text,text)`
- `rls_auto_enable()`

The first four are ordinary application functions and have effective EXECUTE for `anon`, `authenticated`, and `service_role` as reflected by `has_function_privilege`. Of these, the game-result function directly accepts client-supplied score, maximum score and game name; this compounds the previously identified score-trust weakness.

The following student-facing functions show explicit EXECUTE grants to `anon` and `authenticated` (not a separate PUBLIC grant in the returned expanded ACL rows): `get_student_messages(text)`, `get_student_point_history(text)`, `mark_student_messages_read(text)`, `send_student_message(text,text)`, `student_portal_login(text)`, and `submit_student_activity(text,uuid,text)`.

Other listed teacher functions show EXECUTE for `authenticated`, with no anonymous EXECUTE in the effective privilege columns: `generate_student_access_code(uuid)`, `get_teacher_messages()`, `get_teacher_student_code_status(uuid)`, `mark_teacher_messages_read(uuid)`, `purchase_marketplace_reward(uuid,uuid,uuid[])`, `record_student_punctuality(uuid,uuid[],text,integer,date)`, `send_teacher_message(uuid,text)`, `start_teacher_game_session(uuid,text)`, and `verify_student_access_code(text)`.

**Important event-trigger distinction:** `rls_auto_enable()` is a PostgreSQL event-trigger function returning `event_trigger`, attached to the enabled `ensure_rls` DDL event trigger. Its PUBLIC EXECUTE ACL must not be described as an ordinary PostgREST-callable application RPC. PostgreSQL restricts invocation of event-trigger functions to the event-trigger mechanism. Keep it in the database privilege inventory, but classify it separately from callable application functions.

The ACL output includes owner EXECUTE entries and non-grantable grantee entries. The explicit PUBLIC grants on the four ordinary functions above are material. In addition, the functions with explicit `anon` grants are anonymously executable irrespective of whether an additional PUBLIC ACL row is present.

**Security implication:** PUBLIC EXECUTE is broader than granting only `anon` and `authenticated` and should not be used as the default for future privileged application functions. The ordinary SECURITY DEFINER functions with PUBLIC or anon EXECUTE are particularly sensitive because they run as `postgres`, a role with BYPASSRLS. Actual HTTP/PostgREST route exposure remains to be independently verified because the dashboard exposure counts and runtime route configuration have not yet been reconciled.

This is a catalog-only verification. No function ACLs were altered.


## 16. Follow-up verification — complete student_game_sessions columns (2026-11-10)

The previously truncated column inventory was rerun specifically for `public.student_game_sessions`. All eight columns were returned:

- `id uuid NOT NULL DEFAULT gen_random_uuid()`
- `student_id uuid NOT NULL`
- `class_id uuid NOT NULL`
- `game_id text NOT NULL`
- `session_token uuid NOT NULL DEFAULT gen_random_uuid()`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `expires_at timestamptz NOT NULL DEFAULT now() + interval '30 minutes'`
- `used_at timestamptz NULL`

This confirms the 30-minute default lifetime at the table level, in addition to the 30-minute assignment present in both inspected session-creation functions. The earlier constraint inventory showed a primary key on `id` and a unique constraint on `session_token`, but no foreign keys for `student_id` or `class_id`, and no CHECK constraint for expiry ordering. The earlier index inventory showed no non-unique lookup indexes for `student_id`, `expires_at`, or `used_at`.

Security implications and design considerations:
- Required student, class, game, and token columns prevent NULL values, but do not by themselves prove the referenced student/class relationship is valid.
- The unique session-token constraint is a useful collision/replay safeguard, but session issuance/consumption still depends on the function logic.
- No expiry-after-creation CHECK constraint was observed; creation functions set 30 minutes, but direct privileged writes or future code paths would not be constrained by this invariant at the table level.
- No rate-limit/attempt-count fields are present in this table. Rate limiting could exist elsewhere; it was not established by this schema review.
- Add indexes only after query-plan and workload review.

This completes the outstanding truncated column inventory for `student_game_sessions`. No data or schema changes were made.


## 17. Follow-up verification — browser caller inventory in review-branch index.html (2026-11-10)

A full source scan was performed on `index.html` at review branch `security-review/student-login-hardening` (blob SHA `9fc70a0ae617472904e0b96910940adab4553df9`, header version V8.9.2). The scan covered the complete file and searched for Supabase `.rpc()`, `.from()` data operations, writes (`.insert()`, `.update()`, `.delete()`, `.upsert()`), Edge Function invocation patterns, and direct fetch/function endpoint patterns.

**Source-scope caveat:** this is the review-branch browser source, not proof of the exact deployed `main` HTML bundle. The dashboard view previously showed `main` / `PRODUCTION`. Do not assume this caller map is identical to the deployed production artifact until the deployed source/build is independently matched.

### 17.1 Direct browser table reads

The review-branch `index.html` reads these tables directly through the Supabase client:

- `classes` — teacher's active classes.
- `students` — students for each class.
- `point_transactions` — teacher point totals/history and per-student transaction history.
- `groups` and `group_members` — groups and memberships.
- `class_activities` — teacher's activities.
- `student_activity_records` — activity submissions and grading details.
- `marketplace_rewards` — active teacher rewards.
- `purchases` — purchase history.
- `teacher_profiles` — teacher profile read.

### 17.2 Direct browser table writes

The review-branch browser code directly performs the following table writes:

- `students`: INSERT when adding a student; UPDATE first/last name; UPDATE `active=false` when deactivating a student.
- `classes`: INSERT when creating a class.
- `groups`: INSERT, UPDATE, DELETE for group management.
- `group_members`: DELETE current group membership, then INSERT selected membership rows.
- `class_activities`: INSERT draft; UPDATE status to live/closed; DELETE activity.
- `student_activity_records`: UPDATE status, score/points_awarded, completed_at and notes during grading; a second UPDATE attempts to restore previous score fields if the subsequent point transaction INSERT fails.
- `point_transactions`: direct INSERT for teacher award/deduction batch operations; direct INSERT for undo rows; direct INSERT for activity score deltas.
- `marketplace_rewards`: INSERT reward; DELETE reward.
- `teacher_profiles`: UPSERT teacher profile.

The direct point-ledger INSERT paths are particularly important. The teacher award/deduction UI constructs ledger rows in the browser and inserts them directly. Undo also constructs reversal-like ledger rows in the browser and inserts them directly. These paths do not use the approved full reversal linkage/idempotency workflow.

The activity grading workflow performs the protected activity-record UPDATE first and then separately INSERTs the corresponding point transaction. If the ledger insert fails, it attempts a compensating UPDATE to restore the record. This is not atomic: the compensating UPDATE can itself fail, and there is an interval in which the activity record has changed without its ledger delta. This confirms the need to replace both operations with one trusted atomic transaction function.

### 17.3 RPC callers found in review-branch index.html

Teacher-facing RPC calls:
- `get_teacher_messages()`
- `mark_teacher_messages_read(p_student_id)`
- `send_teacher_message(p_student_id, p_message)`
- `generate_student_access_code(p_student_id)`
- `record_student_punctuality(p_class_id, p_student_ids, p_status, p_points, p_punctuality_date)`
- `start_teacher_game_session(p_student_id, p_game_id)`
- `purchase_marketplace_reward(p_request_id, p_reward_id, p_student_ids)`

Student-facing RPC calls:
- `student_portal_login(p_access_code)`
- `get_student_live_activities(p_access_code)`
- `submit_student_activity(p_access_code, p_activity_id, p_answer)`
- `get_student_messages(p_access_code)`
- `mark_student_messages_read(p_access_code)`
- `send_student_message(p_access_code, p_message)`
- `get_student_point_history(p_access_code)`
- `get_student_game_sessions(p_access_code)`

### 17.4 Functions in the database inventory with no direct call found in index.html

The following functions were not found as direct `.rpc()` calls in this reviewed HTML file:
- `get_teacher_student_code_status`
- `verify_student_access_code` (used internally by other database functions)
- `start_student_game_session` (may be called by a separate game/client artifact)
- `record_student_game_result` (may be called by a separate game/client artifact)
- `rls_auto_enable` (DDL event-trigger function, not an ordinary client RPC)

Absence from this one browser file does not establish that no other client, external game application, Edge Function, scheduled process, or administrative tool invokes these functions. Complete repository-wide and deployed-caller inventory remains required.

### 17.5 Edge Function and raw endpoint search

No `supabaseClient.functions.invoke()`, `/functions/v1/` endpoint, or direct `fetch()`-based Edge Function call was found in this reviewed `index.html`. This is consistent with the earlier Edge Functions dashboard screenshot showing no deployed functions in the selected project/branch view, but it does not establish that no other deployed client or endpoint exists.

### 17.6 Required caller-migration implications

Before any grant changes, the following direct browser write paths must be mapped to approved trusted replacements:
1. Point awards/deductions → trusted award/deduction transaction operation enforcing the system-wide 20-point cap, deduction clamp, idempotency, and audit.
2. Undo → linked full compensating reversal, at most once, with no partial reversal or negative balance.
3. Activity grading → one atomic operation updating activity score and ledger delta with the approved clamp/zero-delta policy.
4. Punctuality → trusted operation enforcing the 20-point cap, balance-safe adjustment, approved locking and idempotency.
5. Marketplace → per-student independent purchase outcomes, atomic purchase/debit/finite-stock decrement, and durable outcome/audit semantics.
6. Other mutable classroom tables → preserve legitimate teacher workflows while narrowing direct grants/column updates as appropriate.
7. Teacher profile/group/class/activity/student management → inventory and preserve intended CRUD capabilities while strengthening ownership and transition validation.

This scan is a review-only source analysis. No browser code, grants, RLS policies, database functions, or deployments were changed.


## 18. Follow-up static review — review-only Gateway scaffolds (2026-11-10)

The following review-branch source files were inspected without deployment or execution:

- `supabase/functions/student-access-gateway/index.ts` (blob SHA `d53728bc43c20e3dd84b883b2953baae52ccc7fb`)
- `supabase/functions/game-result-gateway/index.ts` (blob SHA `0f0a354494ee89f9dbd8b1b316b3f3d6c0766dca`)
- `supabase/functions/game-result-gateway/validation.ts`
- `supabase/functions/game-result-gateway/scoring-contract.ts`
- `supabase/functions/game-result-gateway/question-generator.ts`
- Supporting static review notes, action/response contract drafts, central scoring schema/function proposals, and Deno unit-test sources.

Both Gateway files are scaffolds only. They are not deployed. No secrets or feature flags were configured.

### 18.1 Student-access Gateway scaffold

Positive controls:
- Fixed action-to-RPC mapping; caller cannot supply arbitrary RPC names.
- POST/OPTIONS handling, JSON content type check, body size limit, and field-shape validation.
- Access-code shape matches the observed live generator format of eight hexadecimal characters.
- Message and answer lengths are bounded at the Gateway.
- Origin allowlist and `Cache-Control: no-store`.
- The service-role client and RPC execution block are not active.
- The handler returns HTTP 503 if `STUDENT_ACCESS_GATEWAY_READY` is not `true`; even if true, a second unconditional HTTP 503 prevents RPC execution.

Unresolved requirements before any enablement:
1. No atomic/shared rate limiter is implemented.
2. No trusted-source metadata policy, HMAC derivation/rotation, or reliable network-source semantics are finalized.
3. `start_game_session` only validates game ID shape (regex), then maps to the existing `start_student_game_session` function. That live function accepts any non-empty game ID and has no authoritative allowlist. Keep this action disabled until caller identity and authoritative game authorization are resolved.
4. The request validator ignores unexpected extra properties instead of rejecting them. They are not currently forwarded, but strict exact-key contracts should be implemented and tested.
5. The proposed `{data}` response envelope does not match all existing frontend expectations without an adapter. In particular, mark-read expects a scalar integer; other calls expect arrays/rows. The frontend adapter and response contract must be designed and tested together.
6. CORS origin checks are not authentication and do not block non-browser clients.
7. No dedicated unit/contract tests were found for this student-access Gateway scaffold.
8. The exact RPC permission set, response error taxonomy, and direct-RPC bypass migration are still unresolved.
9. Existing anonymous direct RPC privileges must not be revoked until every active client caller (including separate game sites) has been found and migrated. Conversely, a new Gateway must not be considered effective while an old direct route can bypass its controls.

**Decision:** keep the student-access Gateway permanently fail-closed until the rate limiter, trust-source approach, exact request/response contracts, action allowlist, narrow database execution path, complete caller map, direct-RPC migration plan, and isolated end-to-end tests are complete.

### 18.2 Game-result Gateway scaffold

Positive controls:
- Requires POST JSON (plus OPTIONS preflight), enforces a 16 KiB body limit, and checks actual body bytes in addition to Content-Length.
- Uses a fixed server-side game scoring catalogue; unknown game IDs fail closed.
- Request validation rejects unknown and missing top-level keys for both actions.
- Does not accept score, max score, teacher ID, student ID, points, or correctness from the browser.
- Generates Number Challenge questions on the server with Web Crypto and stores the correct-choice index only through the proposed backend function contract.
- Service-role key is read only from Edge Function environment variables; it is not returned to the browser.
- Requires both `GAME_RESULT_GATEWAY_READY=true` and `GAME_RESULT_WRITE_ENABLED=true` before creating the service-role client or calling a database RPC.
- The proposed scoring contract uses game-specific maximum scores and scoring-rule versions; Number Challenge v1 is catalogued at 41 including bonuses.
- Identical answer retry and single-use behavior are designed into the proposed SQL functions.

Unresolved requirements before any enablement:
1. The live public function inventory did not contain `begin_game_attempt` or `record_game_attempt_answer`. The proposal SQL is draft-only and the gateway would not work until those functions and tables are separately approved, implemented and tested in an isolated database.
2. The game-result handler does not itself require a teacher JWT or another Authorization header. The intended request credential is the session token; its security therefore depends on high-entropy, short-lived, single-use session state, database-side validation, rate limiting and careful token secrecy. CORS is not authentication.
3. The code accepts requests with no Origin header; this is not itself a CORS defect for non-browser clients, but confirms Origin cannot be treated as a security credential.
4. No rate limiter is implemented in the handler. The separate rate-limit design correctly states that in-memory limits and untrusted `X-Forwarded-For` headers are insufficient.
5. The handler maps every RPC error to HTTP 400. Transient infrastructure/database failures may need a distinct retryable 5xx response and safe error taxonomy; raw database errors must remain private.
6. After response validation, the handler spreads the entire raw database JSON object into the browser response (`...result`). The validator checks required fields and the nested question object's exact keys, but does not reject all unexpected top-level database response keys. Replace this with an explicit response projection/allowlist before any activation so accidental internal fields cannot be exposed.
7. The proposed SQL functions currently lock the game session row, then attempt/question rows, but do not lock the relevant class and student rows in the approved global order. They also read active/class-membership state without locking and revalidating it. Reconcile this game-specific protocol with the approved class-before-student lock order and transfer/deactivation concurrency rules before execution.
8. The Edge Function uses a service-role client. It must remain server-only, and the actual RPC/table ACLs must be tested to prove the function path has only the intended authority. Service-role bypasses RLS; it is not a least-privilege application role.
9. The two new scoring RPCs do not yet exist in the live function inventory. Their SQL schema/function drafts are wrapped in block comments and outside the migrations directory; they are not approved migrations.
10. No end-to-end test has been run against a deployed Edge Function or database implementation.

**Decision:** keep both readiness flags unset. Do not deploy or enable this scaffold until schema/functions, response projection, locking order, limiter, abuse response, role permissions, game client integration, and isolated tests are approved and complete.

### 18.3 Question generator and scoring-contract observations

The Number Challenge question generator:
- Uses Web Crypto for production randomness and permits deterministic random injection for tests.
- Produces 15 questions with four distinct options and a server-held correct-choice index.
- Includes semantic tests for the generated question types and 200 deterministic seeds.
- The scoring contract derives the max score from a server-owned catalogue, with Number Challenge v1 at 41 and no global fallback.
- The game-specific score validation rejects non-integer, unsafe, negative and over-maximum scores rather than clamping.
- The SQL proposal mirrors the Number Challenge streak/final bonus logic and the one-point-per-correct rule, but those SQL routines remain unexecuted and unverified.

The pure Deno test files exist for request validation, scoring contract, and question generation. Their presence is not proof that the current local checkout has run them or that the SQL/database behavior has passed integration, concurrency or failure tests. Previous CI evidence documented in the integration proposal must be checked against its exact commit before relying on it.

### 18.4 Implementation gates added by this review

Before any Gateway deployment:
1. Keep both scaffolds fail-closed.
2. Implement and test durable rate limits and abuse handling.
3. Settle the session-token threat model and ensure token secrecy/no logging.
4. Project only explicit safe response fields; never spread unfiltered database JSON into public responses.
5. Align game session/attempt/class/student locking with the approved global lock order and prove race behavior.
6. Create the scoring schema and functions only in an approved disposable database first; verify grants, function owners, RLS, and answer-key secrecy.
7. Add dedicated student-access Gateway unit/contract tests and end-to-end response compatibility tests.
8. Find and migrate every caller in classroom, game-site and other client repositories before revoking direct RPC access.
9. Reconcile current API Data API exposure and actual route reachability.
10. Obtain separate approval before any hosted function, database, secret, frontend or deployment change.

This static Gateway review changed no code, SQL, grants, secrets, feature flags, or deployment settings.


## 19. Local Deno unit-test result (user-run, 2026-11-10)

The user ran the following command from the Ubuntu WSL checkout on `security-review/student-login-hardening`:

```bash
deno test \
  supabase/functions/game-result-gateway/validation_test.ts \
  supabase/functions/game-result-gateway/scoring-contract_test.ts \
  supabase/functions/game-result-gateway/question-generator_test.ts
```

**Observed result:** `ok | 34 passed | 0 failed (206ms)`

Breakdown:
- Request validation: 15 passed.
- Scoring contract and scoring arithmetic: 16 passed.
- Question generation: 3 passed, including semantic validation across 200 deterministic runs.

This is local pure-function/unit-test evidence only. It does not test the Edge Function runtime handler, HTTP/CORS behaviour, Supabase RPC reachability, SQL function implementation, RLS/ACL effectiveness, rate limiting, locking/concurrency, replay behaviour in PostgreSQL, or deployed configuration. The student-access Gateway has no dedicated test suite in the reviewed tree.

No database, Git checkout or hosted configuration was modified by this test command.


## 20. Local Deno type-check result (user-run, 2026-11-10)

The user ran:

```bash
deno check \
  supabase/functions/game-result-gateway/index.ts \
  supabase/functions/student-access-gateway/index.ts
```

**Observed result:** Deno reported `Check` for both entrypoints and returned to the shell prompt with no diagnostics or errors.

This confirms local Deno type/module checking completed for the two Gateway entrypoints. It is not a live Edge Function deployment or runtime test and does not verify database connectivity, RPC grants, CORS behaviour, HTTP status contracts, rate limiting, or transaction safety.

No source files, database objects, secrets, or hosted configuration were modified by this check.


## 21. Local Deno lint result (user-run, 2026-11-10)

The user ran:

```bash
deno lint \
  supabase/functions/game-result-gateway \
  supabase/functions/student-access-gateway
```

**Observed result:** 8 files checked; 3 `no-unused-vars` findings.

1. `student-access-gateway/index.ts:14` — `createClient` import unused.
2. `student-access-gateway/index.ts:142` — `RPC_BY_ACTION` mapping unused.
3. `game-result-gateway/scoring-contract.ts:123` — local `questionCount` unused.

Assessment:
- Findings 1 and 2 are expected in the current student-access scaffold: the service-client import and fixed RPC map are future implementation pieces, while the active handler intentionally has an unconditional 503 hard stop and executes no RPC. Do not enable the path merely to silence lint. Keep the hard stop.
- Finding 3 is a redundant unused local variable and can be removed in a separately approved review-branch cleanup. It does not presently change execution because the contract validates the question count through the existing direct field checks.
- The lint command exited with findings; lint is not clean at this checkpoint.

No source changes were made in response to this lint output. Any lint cleanup must preserve the student Gateway's fail-closed behaviour. No deployment, SQL, grants, secrets, or hosted configuration changed.


## 22. Local Deno formatting check (user-run, 2026-11-10)

The user ran:

```bash
deno fmt --check \
  supabase/functions/game-result-gateway \
  supabase/functions/student-access-gateway
```

**Observed result:** Deno reported `Found 8 not formatted files in 8 files`.

The formatter displayed style-only diffs across:
- `game-result-gateway/validation.ts`
- `game-result-gateway/validation_test.ts`
- `game-result-gateway/question-generator.ts`
- `game-result-gateway/scoring-contract_test.ts`
- `game-result-gateway/question-generator_test.ts`
- `student-access-gateway/index.ts`
- `game-result-gateway/scoring-contract.ts`
- `game-result-gateway/index.ts`

The shown differences are formatting changes such as line wrapping, indentation and import layout. The command used `--check`, so it did not write changes.

**Checkpoint outcome:** formatting check did not pass; 8 files need formatting. No source file was modified. Before a future formatting write, sync the local review branch with the newer report commits on origin and reconfirm branch/status. Any formatter write must remain on `security-review/student-login-hardening` and must preserve both Gateway fail-closed stops. No deployment, SQL, grants, secrets, or hosted configuration changed.


## 23. Post-format verification (user-run, 2026-11-10)

After Deno formatted the eight files identified in Checkpoint 22, the user reran all 34 pure unit tests and type-checked both Gateway entrypoints.

Command:

```bash
deno test \
  supabase/functions/game-result-gateway/validation_test.ts \
  supabase/functions/game-result-gateway/scoring-contract_test.ts \
  supabase/functions/game-result-gateway/question-generator_test.ts && \
deno check \
  supabase/functions/game-result-gateway/index.ts \
  supabase/functions/student-access-gateway/index.ts
```

**Observed results:**
- Unit tests: `ok | 34 passed | 0 failed (178ms)`.
- Deno check: both `game-result-gateway/index.ts` and `student-access-gateway/index.ts` checked with no diagnostics/errors.

This confirms that formatting preserved the existing tested pure-function behavior and both entrypoints still type-check. It does not provide database/HTTP/Edge runtime/concurrency or deployed-configuration evidence.

The formatting changes remain local and uncommitted at this point. No database, secret, deployment or hosted configuration was changed.


## 24. Post-format lint recheck (user-run, 2026-11-10)

The user reran Deno lint after formatting all eight Gateway files.

**Observed result:** 8 files checked; the same 3 `no-unused-vars` findings remain, and no new lint findings were introduced.

1. `game-result-gateway/scoring-contract.ts:130` — unused local `questionCount` initialized from `value.question_count`. The validation already checks `value.question_count` directly, so this local is redundant and may be removed as a narrow cleanup.
2. `student-access-gateway/index.ts:14` — unused `createClient` import. Intentionally retained as part of the planned but inactive RPC implementation; the handler must remain fail-closed.
3. `student-access-gateway/index.ts:157` — unused `RPC_BY_ACTION` map. Intentionally retained with the same inactive scaffold; do not activate RPC execution to silence lint.

The two student Gateway findings are expected scaffolding artifacts and should remain until a complete, separately reviewed implementation is ready. The only proposed code cleanup at this stage is deletion of the redundant `questionCount` local; no code has yet been changed in response to this lint run.


## 25. Narrow lint cleanup result (user-run, 2026-11-10)

The user removed only the redundant local declaration `const questionCount = value.question_count;` from `game-result-gateway/scoring-contract.ts`. The complete diff was inspected. All other differences in that file were the previously approved Deno formatting output; validation still compares `value.question_count` directly with `rule.questionCount`.

The user reran Deno lint across both Gateway folders.

**Observed result:** 8 files checked; findings reduced from 3 to 2.

Remaining expected scaffold-only findings:
1. `student-access-gateway/index.ts` — unused `createClient` import.
2. `student-access-gateway/index.ts` — unused `RPC_BY_ACTION` map.

Both are intentionally retained while the student-access Gateway has no active RPC path and returns 503 even if its first readiness flag is set. Do not remove the hard stop or add active use of the import/map merely to silence lint.

The redundant-variable cleanup is a verified narrow nonfunctional change. The two remaining lint warnings are documented intentional scaffold artifacts; lint is not fully clean. Final post-cleanup unit tests, type-check, formatting check, and diff review remain to be run before any local commit.


## 26. Final post-cleanup verification (user-run, 2026-11-10)

Following the narrow deletion of the unused `questionCount` local, the user ran the combined final checks:

```bash
deno test \
  supabase/functions/game-result-gateway/validation_test.ts \
  supabase/functions/game-result-gateway/scoring-contract_test.ts \
  supabase/functions/game-result-gateway/question-generator_test.ts && \
deno check \
  supabase/functions/game-result-gateway/index.ts \
  supabase/functions/student-access-gateway/index.ts && \
deno fmt --check \
  supabase/functions/game-result-gateway \
  supabase/functions/student-access-gateway
```

**Observed results:**
- Unit tests: `ok | 34 passed | 0 failed (183ms)`.
- Deno check: both Gateway entrypoints checked without diagnostics/errors.
- Deno formatting check: `Checked 8 files` without formatting diffs.

Lint was rerun after the cleanup and has exactly two remaining findings, both intentionally unused artifacts in the fail-closed student-access scaffold: `createClient` and `RPC_BY_ACTION`. No new lint findings remain in game-result-gateway.

At this checkpoint, the local source edits consist of Deno formatting across the eight Gateway files and removal of the redundant `questionCount` local. The complete diff still requires a final review with whitespace ignored, plus a final status check, before any decision to commit. Both Gateway safety stops remain unchanged. No SQL/database changes, secrets, deployments, or hosted configuration changes have occurred.
