# Query 1 Findings — Access-Code RPC Permissions

Status: findings from user-provided read-only SQL output, 2026-10-19. No database changes were made during this review.

## Confirmed from the output

The query returned 10 public functions.

### Functions where anon_can_execute = true

- `get_student_game_sessions(p_access_code text)`
- `get_student_live_activities(p_access_code text)`
- `get_student_messages(p_access_code text)`
- `get_student_point_history(p_access_code text)`
- `mark_student_messages_read(p_access_code text)`
- `send_student_message(p_access_code text, p_message text)`
- `start_student_game_session(p_access_code text, p_game_id text)`
- `student_portal_login(p_access_code text)`
- `submit_student_activity(p_access_code text, p_activity_id uuid, p_answer text)`

All nine functions above are SECURITY DEFINER, owned by postgres, and have EXECUTE for authenticated as well. Anonymous EXECUTE may be intentional for the student portal, which uses access-code login without Supabase Auth. Permission alone does not prove a vulnerability; each function's validation and authorization must be reviewed.

### Functions where anon_can_execute = false

- `generate_student_access_code(p_student_id uuid)`: authenticated EXECUTE true.
- `verify_student_access_code(p_access_code text)`: authenticated EXECUTE true.

The verifier's anonymous EXECUTE remains revoked as intended. Other SECURITY DEFINER functions can still call it internally as their owner, so we must inspect their definitions and grants as a complete design.

## Other observed details

- All 10 listed functions are SECURITY DEFINER and owned by `postgres`.
- Nine functions show `search_path=public`.
- `get_student_point_history` shows `search_path=""`; inspect its fully qualified object references and definition before judging whether this is intentional or problematic.
- The output labels volatility as `v` for most functions and `s` for `get_student_point_history`; this is not a rate-limit indicator.

## Important caveats

The output only lists functions selected by the query's argument-name or known-name conditions. It is not a proof that no other public or non-public function accepts access codes. We need to inspect the exact definitions, dependencies, and relevant grants before designing changes.

## Next step

Run only Query 2 from `READ_ONLY_FUNCTION_AUDIT.sql` (the `SELECT pg_get_functiondef(...)` query). If the result is too long, run it for one function at a time, starting with:

1. `verify_student_access_code(text)`
2. `student_portal_login(text)`
3. `get_student_messages(text)`
4. `get_student_point_history(text)`
5. `start_student_game_session(text, text)`

Do not paste any student access codes, hashes, or student records. Function definitions are code, but review them before sharing in case they contain sensitive literals.

No migration, permission change, secret, or deployment is authorized by these findings.
