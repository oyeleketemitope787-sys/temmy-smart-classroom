# Student Login Rate-Limiting Decision Note

Status: review-only proposal. Nothing in this document has been deployed or executed.

## Decision

Do not make IP-header trust a prerequisite for the first protection layer. Treat source-IP throttling as an optional secondary control only after gateway behavior has been verified in the actual project.

Supabase's current Edge Functions documentation describes the gateway as routing requests and handling auth/routing rules. A Supabase maintainer has historically described `X-Forwarded-For` as populated with the client IP, but this is not enough to prove current overwrite/append behavior or spoofing resistance in this project's configuration. The diagnostic draft can only observe header presence; it cannot establish trust without a controlled test.

## Current architecture risk

The browser calls `student_portal_login(p_access_code)` directly. Other anonymous RPCs also accept `p_access_code` and verify the same access code (student messages, point history, game sessions, live activities, and activity submission). Protecting only the login RPC or routing only the login screen through an Edge Function would leave bypass paths.

## Recommended implementation shape for later approval

1. Inventory all anonymous RPCs that accept student access codes and map their call graph to `verify_student_access_code`.
2. Design one atomic attempt-control mechanism that is enforced by the shared verification path or by a trusted server-side layer covering every relevant endpoint. Do not rely on a frontend timer or button-disable state for security.
3. Avoid storing raw access codes, raw IPs, or an unkeyed hash of the short access code. If a stable code fingerprint is needed, use a server-held keyed HMAC with a documented rotation plan.
4. Avoid long code/student-specific lockouts that let an attacker deny a student access. Prefer a short progressive delay, broad source-level signals where trustworthy, generic failures, and operationally safe recovery.
5. Ensure counters update atomically under concurrent requests and expire old records.
6. Preserve teacher ownership checks and first-time access-code generation. Review the current eight-hex-character code format (32 bits of randomness) before finalizing thresholds or long-term design.
7. Only after the complete design is reviewed should a migration, secret, function change, or frontend routing change be proposed. Those are separate approvals; no changes are authorized by this note.

## Required test gates

- Valid active student code returns the current expected fields.
- Invalid, inactive, malformed, and oversized requests fail safely with generic messages.
- Simultaneous attempts cannot exceed limits through race conditions.
- Every code-consuming RPC is covered; no direct anonymous path bypasses the controls.
- A normal student can still access dashboard, messages, history, games, and activities.
- Teacher-created first codes and permitted code regeneration continue to work.
- Old attempt records expire without unbounded table growth.
- Any IP-based control is tested with a normal request and a client-supplied spoofed forwarding header in a non-production isolated project. Because the available Supabase project shares the live database, do not run that test by deploying to the shared project.

## Current project constraints

- Only known Supabase project: `temmy-smart-classroom-test`, whose database is shared with the live Classroom.
- Do not deploy the diagnostic function to that shared project.
- Do not execute SQL, create Vault secrets, deploy Edge Functions, or change frontend calls without separate explicit approval.
- Keep this work on `security-review/student-login-hardening`; leave `cloud-test` and `main` untouched.
