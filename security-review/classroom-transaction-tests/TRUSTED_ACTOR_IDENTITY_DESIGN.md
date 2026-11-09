# Trusted Actor Identity Design — Review Only

**Status:** Design decision for disposable tests; not production implementation  
**Scope:** Classroom point transactions and activity/marketplace mutations  
**Branch:** security-review/student-login-hardening

## 1. Purpose

Transaction functions must know which teacher is authorized to perform an operation. A browser-supplied teacher UUID is not proof of identity and must never be trusted as the authorization source.

This design separates:

1. **Authentication:** proving who the caller is.
2. **Actor derivation:** obtaining the verified teacher UUID from the authenticated identity.
3. **Authorization:** checking that the teacher owns the relevant class and student, activity, or reward.
4. **Mutation:** applying the business operation atomically and recording its audit event.

## 2. Disposable test-harness model

For isolated PostgreSQL tests only:

- Create a NOLOGIN role named `temmy_gateway`.
- Do not grant membership in `temmy_gateway` to `anon` or `authenticated`.
- Grant the test transaction entry points to `temmy_gateway` only.
- The privileged test runner may use `SET ROLE temmy_gateway` and invoke a test operation with a known synthetic teacher UUID.
- The test runner's mapping of that UUID to the test teacher represents an identity that has already been authenticated by a trusted gateway.
- The test runner must also test that `anon` and `authenticated` cannot execute the transaction entry points or assume the gateway role.

A teacher UUID parameter is acceptable in this **test-only** model because execution permission is restricted to the trusted test role. It is not a browser API pattern.

### Important limitation

This harness simulates the authorization boundary after authentication. It does **not** test Supabase JWT verification, Edge Function authentication, token expiry, or the production propagation of identity from Temmy Gateway to PostgreSQL.

## 3. Function ownership and privilege model

The proposed disposable fixture should use separate roles:

- `temmy_data_owner`: NOLOGIN owner of protected tables and SECURITY DEFINER transaction functions; no superuser or BYPASSRLS attribute.
- `temmy_gateway`: NOLOGIN role allowed to execute only the approved transaction entry points.
- `anon` and `authenticated`: untrusted client roles; no membership in `temmy_gateway`, no direct ledger writes, and no direct updates to protected activity score fields.
- Privileged test runner: used only by the isolated test environment to create the fixture, seed synthetic records, switch to the test gateway role, and run negative privilege tests.

SECURITY DEFINER functions must:

- Be owned by the least-privileged suitable owner, not a superuser.
- Use a fixed, minimal search_path and schema-qualified object references.
- Validate the actor's ownership of every referenced class, student, activity, and reward.
- Reject missing, inactive, or mismatched records.
- Never treat a caller-provided actor UUID as proof of identity outside the restricted test harness.
- Expose only narrow business operations, not generic table-write capabilities.

The test fixture must verify effective privileges, not merely inspect intended GRANT statements.

## 4. Production identity boundary — still undecided

The production gateway must authenticate the incoming user request, validate the token, and derive the teacher identity from the verified subject/claims. It must not accept a teacher UUID from the browser as authoritative.

Two broad implementation patterns require a separate threat-model and compatibility review:

### Pattern A — user-context database call

The gateway preserves a verifiable user JWT context when calling PostgreSQL, and database functions derive the actor from trusted JWT claims (for example, the authenticated subject). The database must enforce ownership and narrow function privileges.

### Pattern B — server-only gateway credential

The gateway verifies the user token, derives the teacher UUID server-side, and calls a narrowly privileged database interface using a credential held only by the server. The browser never receives that credential. The database interface must not be callable by ordinary browser roles, and the server must bind the actor to the verified identity rather than trusting a client parameter.

Neither pattern is selected by this document. The actual Supabase Edge Function/runtime constraints, available database roles, JWT propagation, connection method, and effective ACLs must be verified before choosing.

A general-purpose service-role credential must not be placed in browser code. If a server-side service credential is considered, its scope, storage, rotation, and blast radius must be documented.

## 5. Required negative tests

The isolated test suite must prove:

1. `anon` cannot execute any transaction entry point.
2. `authenticated` cannot execute any transaction entry point directly unless a future design explicitly grants a safe user-context operation.
3. Neither client role can `SET ROLE temmy_gateway` or inherit its privileges.
4. Neither client role can insert, update, or delete ledger rows directly.
5. Neither client role can alter protected activity score fields directly.
6. A gateway call for Teacher A cannot mutate Teacher B's class, student, activity, or reward.
7. A teacher cannot target a student outside a class they own, even if the student UUID is valid.
8. An inactive or mismatched teacher/class/student/activity/reward relationship is rejected.
9. A repeated request ID with the same canonical payload returns the stored result without a second mutation.
10. Reuse of the same request ID with a different payload is rejected.
11. Concurrent requests cannot bypass balance, stock, reversal, or idempotency checks.

## 6. Rules for test implementation

- Use synthetic teacher, class, student, activity, and reward IDs only.
- Do not connect the fixture to Supabase or production credentials.
- Do not run the fixture against the existing local database without first creating and explicitly identifying a separate disposable database.
- Do not add this SQL to `supabase/migrations`.
- Do not deploy any test function or gateway scaffold.
- Do not change `main` or the shared `cloud-test` branch.
- The fixture role model is a test simulation, not a declaration that these roles already exist in the hosted Supabase project.

## 7. Open gates before production design approval

- Confirm how the deployed application authenticates teachers and how the verified identity reaches the server.
- Confirm the intended Supabase Edge Function authentication and database-call pattern.
- Inspect the actual deployed role memberships and effective function ACLs in an approved isolated environment.
- Decide whether production functions use user JWT context or a dedicated server-only gateway credential.
- Review the final function owner, search_path, grants, RLS interaction, and service credential scope.
- Complete caller inventory and compatibility testing before removing any legacy write path.

**Decision:** Use the restricted `temmy_gateway` role as a controlled identity simulation in disposable tests. Keep the production identity propagation design open until the runtime and privilege model have been verified.
