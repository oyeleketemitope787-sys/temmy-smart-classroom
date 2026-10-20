# How to Capture and Share the Read-Only Access-Code Audit

This is a user guide for collecting evidence. It does not change the database.

## Before running
1. Open the Supabase project used by Temmy Smart Classroom.
2. Open SQL Editor.
3. Open the review-branch file `READ_ONLY_ACCESS_CODE_CALLGRAPH_AUDIT.sql` in GitHub.
4. Copy the entire SQL into the editor and inspect that it contains only the read-only `WITH ... SELECT` query. Do not add GRANT, REVOKE, INSERT, UPDATE, DELETE, CREATE, ALTER, or DROP statements.
5. Run it once. It is an inventory query, not a security test.

## What to share
Please copy the result rows, including these columns when displayed:
- `schema_name`
- `function_name`
- `identity_arguments`
- `result_type`
- `volatility`
- `security_definer`
- `proconfig`
- `execute_grants`
- `function_definition`

If the result is long, send it in multiple messages or share a screenshot with the column names visible. Avoid including unrelated secrets or credentials. Function definitions and ACL rows are needed for accurate review; do not replace them with a summary alone.

## If the query fails
Send the exact error message and note whether it occurred when pasting or running the query. Do not try a write query as a workaround. We can adjust the audit query based on the error.

## How we will use the output
We will:
1. Classify the candidate functions by purpose and caller.
2. Compare actual ACLs with the previous findings and default privileges.
3. Identify exact functions that are reachable by `anon`, `authenticated`, or `PUBLIC`.
4. Keep teacher-side code generation separate.
5. Draft a narrowly scoped proposed permission plan for review only.

## Safety
- Do not execute any migration or permission change from this review.
- Do not deploy the gateway scaffold.
- Do not test brute-force, concurrency, spoofed headers, or lockouts against the shared database.
- The audit output alone does not prove all client call sites have been found.
- No access-code rate-limiting protection is active from this work yet.
