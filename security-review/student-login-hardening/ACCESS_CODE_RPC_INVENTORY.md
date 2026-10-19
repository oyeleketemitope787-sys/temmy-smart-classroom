# Student Access-Code RPC Inventory

Status: source review only. No SQL was executed and no application or database changes were made.

## Scope inspected

Frontend file: `index.html` on branch `cloud-test` (blob SHA `9fc70a0ae617472904e0b96910940adab4553df9`).

The file contains these calls that use a student's access code:

| RPC | Frontend use | Security implication |
|---|---|---|
| `student_portal_login(p_access_code)` | Student login form | Primary login path; currently called directly from the browser. |
| `get_student_messages(p_access_code)` | Load student messages | Must be covered by any access-code attempt controls. |
| `mark_student_messages_read(p_access_code)` | Mark messages read | Must be covered consistently. |
| `send_student_message(p_access_code, p_message)` | Student sends a message | Must be covered consistently; also validate message input and authorization. |
| `get_student_point_history(p_access_code)` | Load point history | Must be covered consistently. |
| `get_student_game_sessions(p_access_code)` | Load game-session history | Must be covered consistently. |
| `get_student_live_activities(p_access_code)` | Load live activities | Must be covered consistently. |
| `submit_student_activity(p_access_code, p_activity_id, p_answer)` | Submit activity answer | Must be covered consistently; activity ownership and input validation also matter. |

The teacher-side code-generation calls are `generate_student_access_code(p_student_id)`. They use teacher-side context and should retain their current authentication, active-class, and ownership checks. Do not accidentally apply student login throttling to legitimate teacher code generation.

## What this inventory does and does not prove

This inventory confirms the browser call sites in the inspected `cloud-test/index.html`. It does not by itself prove the database function definitions, grants, all other callers, or whether every listed RPC invokes `verify_student_access_code`. Those details must be checked against the actual database function definitions and privileges before choosing an enforcement design.

The earlier database review identified the following functions as SECURITY DEFINER and accepting `p_access_code`: `student_portal_login`, `verify_student_access_code`, `get_student_game_sessions`, `get_student_live_activities`, `get_student_messages`, `get_student_point_history`, `mark_student_messages_read`, `send_student_message`, `start_student_game_session`, and `submit_student_activity`. This list includes `start_student_game_session`, which is not called in the inspected student portal snippet; it should be included in the database-wide inventory. Reconfirm current grants and definitions before implementation.

## Required next review

1. Obtain read-only definitions and EXECUTE grants for all public functions that accept `p_access_code), plus any helpers they call.
2. Confirm each function's code-verification path and ensure failed attempts cannot be bypassed through another RPC.
3. Choose one shared, atomic enforcement point that covers all code-consuming endpoints.
4. Review authorization and input validation independently of rate limiting.
5. Keep all SQL as a proposed migration until separately approved; do not execute it against the shared project.

## Safety constraints

- The known TEST Supabase project shares its database with the live Classroom.
- Do not deploy the diagnostic function to that shared project.
- Do not run invalid-code bursts or spoofed-header tests against the shared project.
- Keep this work on `security-review/student-login-hardening`; leave `cloud-test` and `main` untouched.
