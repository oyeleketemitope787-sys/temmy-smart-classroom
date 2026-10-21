# Game-Result Caller Audit — SQL Output Review

**Status:** Read-only SQL output reviewed; caller inventory remains incomplete  
**Branch:** `security-review/student-login-hardening`  
**Evidence source:** User-supplied output from a read-only database-function-definition query on 2026-10-21  
**Scope:** Documentation only. No database objects, permissions, data, secrets, frontend files, or deployments changed.

## Findings

### 1. One direct game-reward writer was present in the returned candidate set

The output includes `public.record_student_game_result(uuid, text, text, integer, integer)`, marked `SECURITY DEFINER` and `VOLATILE`. Its definition:

- Looks up a `student_game_sessions` row by the supplied session token and locks that row with `FOR UPDATE`.
- Rejects missing, already-used, expired, or game-ID-mismatched sessions by returning no result.
- Derives the credited student from the stored session, and the teacher from the session's class.
- Inserts a `point_transactions` row with `action_type = 'activity_score'` and `source = 'game'`.
- Marks the session as used and returns points, submitted score/max score, action name, and timestamp.

This is evidence of a database-side game-reward writer in the inspected definitions. It does not identify the browser or server caller.

### 2. Session-start functions create reward-capable bearer sessions

The output also includes:

- `public.start_student_game_session(p_access_code text, p_game_id text)`
- `public.start_teacher_game_session(p_student_id uuid, p_game_id text)`
- `public.get_student_game_sessions(p_access_code text)`

The student-start function verifies the access code and stores the caller-supplied game ID. The teacher-start function verifies teacher authentication and student/class ownership, then stores the supplied game ID. The retrieval function returns active, unused sessions for the student associated with the access code.

The returned definitions do not show an approved-game allowlist check in either session-start function. This remains a separate validation concern; do not change it as part of rate limiting without a scoped decision.

### 3. Score and display fields require further validation review

The result RPC checks `p_score < 0` and `p_max_score <= 0`, then calculates `least(p_score, p_max_score)`. The definition does not reject `p_score > p_max_score` and does not impose an upper bound on `p_max_score`. It also accepts `p_game_name` from the caller for transaction display fields. The session's stored game ID is checked against the caller's game ID, but the function does not derive the display name or maximum score from a server-controlled game catalogue in this definition.

These are code-review findings, not proof of exploitation. A trusted server must not treat client-submitted score fields as independently verified evidence of gameplay. The intended scoring policy needs an explicit product decision.

### 4. Other matches are not necessarily game-reward writers

The candidate query also returned student readers and unrelated point writers, including `get_student_point_history`, `get_student_live_activities`, `purchase_marketplace_reward`, and `record_student_punctuality`. These matches occur because the query searches broadly for point transactions, sessions, or related fields. They should not be misclassified as callers of `record_student_game_result` without direct evidence.

### 5. What this output does not establish

This output does **not** contain effective EXECUTE grants or ACL results. It therefore cannot establish whether anonymous callers can execute any listed function; use the separate read-only ACL audit for that determination.

It also cannot enumerate browser call sites or deployed external callers. Repository source inspection still has not located a visible result-submission call, and the live deployed game source remains unverified.

## Required next actions

1. Obtain the current effective ACL output for `record_student_game_result`, both session-start functions, and `get_student_game_sessions`.
2. Continue read-only search for the deployed result-submission caller, including any external page or artifact not represented in the inspected repository source.
3. Decide how the server will validate game eligibility, score bounds, maximum score, and display name before changing the result RPC.
4. Keep public gameplay separate from student reward recording; rewards must be tied to a valid session and the session's stored student/game identity.
5. Do not revoke EXECUTE, deploy the gateway, run point-award tests, or modify the shared database based on this output alone.

## Safety status

No SQL migration, grant/revoke, Edge Function deployment, secret creation, frontend change, or production deployment was performed as part of this review.
