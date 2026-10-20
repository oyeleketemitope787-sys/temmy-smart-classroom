# Student Gateway Response Contract Map

**Status:** review-only. Based on the inspected `cloud-test/index.html` and user-supplied SQL definitions. No frontend changes were made.

## Required action-to-RPC mapping

| Gateway action | RPC | Expected browser-side shape observed |
| --- | --- | --- |
| `login` | `student_portal_login` | Array of rows; browser reads first row and expects `student_id`, `class_id`, `class_name`, `first_name`, `last_name`. Empty array means code/class not accepted. |
| `point_history` | `get_student_point_history` | Array of rows; stored as student history and rendered into the portal. |
| `live_activities` | `get_student_live_activities` | Array of rows; rendered as activities. |
| `game_sessions` | `get_student_game_sessions` | Array of rows; rendered as available sessions. |
| `messages` | `get_student_messages` | Array of rows; message UI then calls mark-read. |
| `mark_messages_read` | `mark_student_messages_read` | Scalar integer result; current caller checks only the error. |
| `send_message` | `send_student_message` | Array of rows with `message_id` and `sent_at`; caller checks non-empty result. |
| `submit_activity` | `submit_student_activity` | Array of rows with `record_id`, `activity_id`, `status`; caller checks error then reloads activities. |
| `start_game_session` | `start_student_game_session` | Database function exists, but was not found in the inspected `cloud-test/index.html` snippet/call-site search. Find other game-launch callers before migrating or enabling this action. |

## Important response-envelope decision

Supabase RPC results are returned as `{ data, error }`. The gateway should not blindly wrap data in a new shape unless the frontend adapter is deliberately updated. Choose one contract and test it end-to-end:

- **Compatibility option:** gateway returns the RPC's data in the exact shape the frontend adapter expects, and frontend adapter converts errors into a Supabase-like `{data,error}` result; or
- **Explicit API option:** gateway returns a documented JSON envelope and the frontend changes to consume it.

Do not mix these options. In particular, login must continue to handle a row array and history/activity/message views must continue to handle arrays. The `mark_student_messages_read` scalar should not accidentally become an array.

## Migration safety checklist

- [ ] Search every frontend file and game launcher, not only `index.html`, for direct RPC calls.
- [ ] Identify whether student game launch is handled by a separate game repository/site.
- [ ] Replace every student access-code RPC call before revoking anonymous EXECUTE.
- [ ] Preserve teacher-side `generate_student_access_code(p_student_id)` and teacher authorization paths.
- [ ] Verify generic error behavior without leaking whether a student/code exists.
- [ ] Keep all edits on `security-review/student-login-hardening` until separately approved.

## Current status

This is a contract map only. The gateway scaffold still fails closed and is not deployable. No database migration, secret, deployment, or frontend update has occurred.
