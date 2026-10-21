# Searchable Game Assignment — UX and Product Design Proposal

**Status:** Design proposal only — not implemented  
**Target branch:** `security-review/student-login-hardening`  
**Scope:** Teacher assignment discovery, class-aware game availability, and related student-facing navigation.  
**Explicit exclusions:** No edits to `cloud-test` or `main`; no frontend implementation, database migration, RPC/ACL change, secret creation, deployment, or live/shared-database test.

## 1. Goals

1. Let teachers find a game quickly even when the library contains many games.
2. Show games relevant to the selected class without requiring teachers to scroll a long dropdown.
3. Separate a game being available to a class from a teacher assigning it to particular students.
4. Keep the student dashboard focused on current work while preserving previous assignments and results in Game History.
5. Preserve one-time scoring and prevent expired play sessions from making unfinished assignments disappear.

## 2. Teacher assignment flow

### Proposed modal layout

1. **Class** — select an existing class. Keep the selected class visible while searching.
2. **Search games** — a prominent text search with placeholder: “Search by game, grade, unit, topic or skill…”.
3. **Filters** — Grade, Unit/Topic, and Availability. Filters should be optional and easy to clear.
4. **Results list** — compact rows/cards displaying:
   - Game title
   - Grade and topic/unit
   - Brief learning objective or skill
   - Availability/assignment status when known
   - Select control
5. **Student selection** — searchable student list with Select All and Clear All scoped to the selected class.
6. **Review and assign** — show selected game and student count before the teacher confirms.

Search should be case-insensitive and match title and indexed metadata. Empty search should show the most relevant games for the selected class, not an unfiltered list of every game in the entire platform. Include a clear “No games match” state with a clear-filters action.

### Search behaviour

- Search-as-you-type; avoid requiring a separate submit button.
- Keep the selected class and student selection when the teacher refines the search.
- Make keyboard navigation, visible focus, and screen-reader labels part of the design.
- Do not show a game as assignable if its metadata is incomplete or it is disabled; explain why where appropriate.
- Never silently assign all games when a class is created.

## 3. Class-to-game relationship

Use a two-stage concept:

- **Class game availability:** a game is discoverable for a class based on explicit supported grade/curriculum/topic metadata and any future teacher/admin configuration.
- **Student assignment:** a teacher deliberately selects a game and one or more students; the system creates the actual assignment/session records.

Creating a class should make matching games available automatically where the class grade/curriculum and game metadata support a reliable match. It must not automatically create assignments, launch sessions, or award points.

If a class does not have enough metadata to determine matching games, show a clear fallback such as “Choose a grade or browse all available games” rather than guessing.

## 4. Suggested game catalogue metadata

This is a conceptual metadata contract, not a proposal to create tables before schema review.

Required or strongly recommended fields:
- Stable game ID/slug
- Display title
- Grade(s)
- Subject
- Unit/topic and searchable skill keywords
- Learning objective/short description
- Availability status (enabled/disabled)
- Game URL or registered launch target
- Supported play mode(s), including public practice versus assigned play

Do not use display titles as identifiers. The catalogue should use stable IDs and validate launch targets against an approved registry. Existing games should not be renamed or changed merely to fit this proposal.

## 5. Student dashboard and Game History

### Current Games
Keep the dashboard compact. Show assignments requiring action, plus a concise completed summary if useful. Each assignment should have a clear state, for example:
- Ready
- In progress (only if the system can reliably establish this state)
- Completed
- Needs teacher attention / unavailable

Do not infer completion solely from a missing or expired session.

### Game History
Provide a separate tab/link with:
- Search by game title
- Filters for date and status
- Recorded score and maximum score
- Completion date
- A result-detail view where available

History is read-only. Opening history, refreshing it, or revisiting a result must never award points.

## 6. Assignment, session expiry, and one-time scoring

Treat these as separate records/concepts:

- **Assignment** persists until completed, cancelled by an authorized teacher, or otherwise deliberately closed.
- **Play session** is a temporary credential with a defined expiry.
- **Result/award** is a one-time, server-enforced state transition tied to the assignment/session.

Expected behaviour:
1. An unfinished assignment must remain visible after its play session expires.
2. When allowed by policy, launching an unfinished assignment may create a replacement session for the same assignment; it must not create a duplicate assignment.
3. Once a result is accepted, the assignment becomes Completed and cannot start another scored attempt unless a future explicit retake policy is introduced.
4. A duplicate or replayed result submission must not award points again.
5. Public practice remains open but must not create or submit a student reward result.
6. Server-side checks enforce completion and one-time awards; hiding a button or removing a card is not a security control.

The current database/session model must be inspected before deciding whether an assignment entity already exists or needs a future migration. No schema is prescribed by this design document.

## 7. Error and empty states

- No matching games: “No games match your search. Try another keyword or clear filters.”
- No games available for class: explain that grade/topic details may be missing and offer a safe browse option.
- Expired session, unfinished assignment: preserve the assignment and offer “Start again” only if server-side policy allows a fresh session.
- Completed assignment: show the result and disable scored replay.
- Game temporarily unavailable: preserve assignment history and provide a safe status message.
- Failed search/load: show a retry action without displaying raw backend errors or secrets.

## 8. Security and privacy constraints

- Do not expose service-role credentials or privileged database keys to the browser.
- Do not treat client-provided student IDs, assignment IDs, session state, scores, or forwarding headers as trusted.
- Validate class ownership/teacher authority and student-to-class membership server-side.
- Enforce assignment completion and one-time awards atomically on the server.
- Keep raw student access codes and session tokens out of logs, analytics, URLs where feasible, and history search indexes.
- Do not revoke the current result RPC or change ACLs until all legitimate submission callers are identified and a compatible server-side replacement is ready.
- Avoid lockout, brute-force, spoofed-header, concurrency, or mutation testing against the shared Supabase project.

## 9. Acceptance criteria for a future implementation

- Teacher can locate a game by title, grade, unit/topic, or skill without scrolling a long dropdown.
- Results are relevant to the selected class; class creation does not assign games automatically.
- Search and filters can be cleared and used with keyboard navigation.
- Teacher can select students and review the assignment before confirming.
- An expired session does not make an unfinished assignment disappear.
- A completed assignment remains accessible in Game History but cannot be replayed for another award.
- Duplicate result submissions award zero additional points.
- Public practice never affects student balances.
- Existing teacher assignment, student login, activity workflows, and historical points remain intact.
- Tests and rollout occur only after a safe isolated verification environment and all release gates are satisfied.

## 10. Dependencies and next review steps

1. Inventory the current class, game catalogue, assignment, session, and result schema/functions.
2. Confirm whether assignments have a durable ID independent of a 30-minute session.
3. Trace the deployed game result-submission caller and all legitimate RPC call sites.
4. Map the proposal to the existing gateway action contract and response shapes.
5. Review this UX proposal alongside the one-time scoring and session-expiry design.
6. Only after the owner approves a concrete implementation plan, implement on a non-production branch and test safely.

**Current decision:** Design only. No implementation or deployment is authorized by this document.
