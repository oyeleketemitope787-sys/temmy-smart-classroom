# Current Game Assignment UI — Static Review Findings

**Reviewed source:** `index.html` on `cloud-test`  
**Observed source SHA:** `9fc70a0ae617472904e0b96910940adab4553df9`  
**Review date:** 2026-10-21  
**Status:** Static source inspection only. No frontend or database changes made.

## Confirmed in source

1. The teacher assignment modal is titled **Start Temmy Smart Game**.
2. The selected class is shown in a disabled text field.
3. The game selector is a native `<select id="gameSelect">` containing one hard-coded option:
   - `grade3-temmy-number-challenge` — “Temmy Number Challenge”
4. A search input exists for students, not games. It filters the visible student rows by student name.
5. Select All and Clear All controls apply to student checkboxes.
6. The modal states that each selected student receives a secure 30-minute game session.
7. On confirmation, the browser calls `start_teacher_game_session(p_student_id, p_game_id)` for each selected student.
8. The launch URL is hard-coded to `https://games.stgloriousschool.org/games/temmy-number-challenge.html`, with the returned session token added as the `session` query parameter.
9. The current visible game choice and hard-coded launch URL are aligned for the single option, but this design will not scale to many games without a catalogue/registry and launch-target mapping.

## Implications for the proposed searchable interface

- Replace the game dropdown with a search-first picker only after a trusted game catalogue and metadata source are identified.
- The search should filter registered game records by title, grade, unit/topic, and skill; it should not construct launch URLs from arbitrary user input.
- The chosen game ID and its approved launch target must come from the registered catalogue.
- Keep student search and multi-select behaviour separate from game search.
- A class should see games that match its grade/curriculum or an explicitly configured availability rule. Class creation must not assign every matching game to every student.
- The current code alone does not show a game-to-class relationship or metadata model. Database inventory is still needed to determine whether such relationships already exist.
- Do not implement durable assignments, completed-state UI, or Game History based on assumptions about tables. First inspect the current schema and functions.

## Existing 30-minute session and completion issue

The source displays “Each selected student receives a secure 30-minute game session.” A separate inspected student portal renders the session's `expires_at` timestamp and labels returned sessions `READY`.

This confirms that the client UI is session-centric. It does not establish whether a durable assignment record exists independently of the session, whether expired sessions are automatically recreated, or whether completed assignments are excluded by the database query. Those questions require the read-only schema inventory and review of the exact SQL definitions.

## Safety and scope

- This document does not authorize changes to `cloud-test` or `main`.
- Do not modify or deploy the frontend during this design stage.
- Do not make schema/permission changes or run test writes on the shared Supabase project.
- The read-only schema inventory remains the next evidence needed before recommending a concrete data model.
