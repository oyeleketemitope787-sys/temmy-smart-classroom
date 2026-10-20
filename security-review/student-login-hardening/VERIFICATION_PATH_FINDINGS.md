# Verification Path Findings — Student Access-Code RPCs

**Status:** review-only findings from function definitions supplied on 2026-10-20. No database or frontend changes were made.

## Confirmed common path

The inspected functions all call `public.verify_student_access_code(p_access_code)` before returning student-specific data or performing student actions:

- `student_portal_login(text)`
- `get_student_game_sessions(text)`
- `get_student_live_activities(text)`
- `get_student_messages(text)`
- `get_student_point_history(text)`
- `mark_student_messages_read(text)`
- `send_student_message(text,text)`
- `start_student_game_session(text,text)`
- `submit_student_activity(text,uuid,text)`

The verifier matches `extensions.crypt(p_access_code, sa.code_hash) = sa.code_hash` and requires both `student_access.active` and `students.active`. The login function additionally requires an active class and updates `last_login_at`/ `updated_at`.

## Important implementation implications

1. **Common verifier is a shared authorization path, but not automatically a safe place for write-based throttling.** `get_student_point_history` is declared `LANGUAGE sql STABLE SECURITY DEFINER` and invokes the verifier. PostgreSQL restricts data modification from a function running in a non-volatile context. Therefore, do not simply add counter writes inside the verifier without resolving this caller's volatility and validating the full call graph. A blanket verifier edit could break point-history loading.
2. **Failed-code attempts currently are not recorded in these definitions.** The verifier returns no rows for an invalid/inactive code; it does not update an attempt counter. Several wrappers return no rows, while message-related and activity-submission wrappers raise exceptions. Error shapes differ and must be preserved or normalized deliberately.
3. **Direct RPC access remains an enforcement concern.** Since the student portal is currently browser-to-RPC and nine student functions have anonymous EXECUTE, a gateway-only limiter can be bypassed until all relevant browser calls are migrated and direct anonymous execution is revoked in a coordinated, tested rollout.
4. **The game-session function accepts a caller-supplied `p_game_id` and inserts it after verifying the code.** The definition does not itself check a known game allowlist. Review this as a separate input/authorization issue; do not change it as part of rate limiting without an explicit scope decision.
5. **Authorization checks vary by action.** `submit_student_activity` checks the activity belongs to the student's class and is live; message functions check the active class/teacher; read/list functions scope results to the verified student. Preserve these checks in any gateway rollout.

## Recommended direction

Continue with the gateway architecture, but do not deploy the current scaffold. First complete:
- the full frontend call-site inventory and action response contract map;
- a private, atomic limiter design with keyed fingerprints that never store raw codes or unkeyed hashes of short codes;
- a trusted-secret strategy and narrow server-side database grants;
- a reviewed plan to migrate all student-code calls before revoking anonymous execution;
- a safe solution for the `STABLE` point-history caller (or a design that keeps limiter writes outside that call path);
- isolated test coverage and a rollback script.

The available TEST project shares its database with the live Classroom. Do not run brute-force, concurrency, spoofed-header, or lockout tests there.

## Current state

This document is analysis only. No SQL has been executed, no Vault secret has been created, no Edge Function has been deployed, and no frontend or database permission has been changed in this phase.
