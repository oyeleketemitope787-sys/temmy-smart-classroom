# Temmy Smart Classroom — Live Activity Approved Implementation Plan

**Status:** Product decisions approved; implementation pending schema and code inspection  
**Date approved:** 25 November 2026  
**Working repository:** `oyeleketemitope787-sys/temmy-smart-classroom`  
**Working branch:** `cloud-test`  
**Production branch:** `main` — do not modify  
**Database:** isolated Supabase project `temmy-smart-classroom-test` only

## 1. Scope

Implement the approved Live Activity experience in Temmy Smart Classroom. Preserve existing classroom, student, teacher, points, and activity data. Do not redesign or integrate other Temmy products.

## 2. Supported activity formats

Every Live Activity must support these six formats:

1. Multiple choice
2. Fill in the gaps
3. True/false
4. Matching
5. Short answer
6. Extended response / explain your work

Objective formats are automatically graded. Written or judgement-based responses are teacher graded and support partial marks. Each attempt is scored once. Automatic retakes are not allowed; exceptional reopening is teacher-authorised and audited.

## 3. Approved student interface

The user-approved screenshot dated 25 November 2026 is the visual reference and standard layout for all six formats.

- Retain the clean, compact interface and the countdown timer at the top.
- Show activity progress and the current question number (for example, “Question 8 of 12”).
- Show a progress indicator.
- Represent every question using a numbered navigation tile.
- Numbered tiles are the sole question-navigation method. There are no Previous or Next buttons.
- Students may select any question number and revisit/change answers before submission or expiry.
- Visually distinguish states: green = answered; blue = current question; neutral/plain = unanswered.
- Keep the question and response area below the numbered navigation.
- Adapt only the response control to the question format; retain the common navigation and overall layout.
- Do not create alternative selection interfaces. Retain the approved multiple-choice selection presentation from the reference screenshot.

## 4. Teacher-configurable activity duration

- The teacher sets the time limit for each activity; there is no single fixed duration for all activities.
- Store the configured duration with the activity on the server.
- Each student's attempt receives a server-controlled countdown based on that activity's configured duration.
- The countdown must not reset when a student resumes after interruption.

## 5. Autosave, expiry, and submission

- Autosave student responses throughout the attempt and confirm successful saves.
- Preserve saved work across refreshes, navigation, and temporary connection loss.
- Use safe retry/recovery and stale-write protection; do not create duplicate attempts or duplicate submissions.
- When the countdown reaches 00:00, automatically submit the student's saved work without requiring a button click.
- Make a final save of any pending response changes where connectivity permits; never claim an unsaved answer was preserved.
- Assess only answers actually saved at the submission cutoff. Unanswered questions receive no marks.
- Lock the attempt after manual submission or time expiry.
- If the connection is unavailable at expiry, preserve the last confirmed saved work and complete submission safely when connectivity returns, without creating a second attempt.
- Teacher-authorised exceptional recovery/reopening must be audited.

## 6. Marking and results

- Automatically grade objective questions and make the available objective score visible after submission.
- Route short-answer and extended-response items requiring judgement to the teacher for marking, including partial marks.
- Clearly distinguish provisional/automatically available results from results awaiting teacher marking.
- Publish teacher-marked results according to the existing/approved teacher result-publication workflow.
- Never invent marks for unanswered or unsubmitted responses.

## 7. Teacher monitoring and security

- Teacher monitoring may show student progress, timer/status, answered/unanswered counts, and submission state.
- Teachers must not see students' active answers before submission/expiry.
- Enforce attempt timing, submission, grading, and points effects server-side; do not rely on the browser clock or client-side score.
- Maintain audit history for exceptional recovery and consequential teacher actions.

## 8. Points integration

- Live Activity assessment must integrate with the approved Aggregate Points and Spendable Points architecture.
- Apply activity points only through trusted server-side atomic operations, after the relevant assessment/review is valid.
- Record each points award once; retries must be idempotent.
- Marketplace purchases affect Spendable Points only; they do not change Aggregate Points.
- Do not award points for unanswered questions or ungraded written responses unless the approved scoring rule explicitly provides a mark.

## 9. Implementation sequence

1. Inspect the existing activity tables, records, functions, triggers, RLS policies, and current frontend activity workflow.
2. Map the current schema to the approved requirements; identify compatibility and migration risks.
3. Design additive, reversible database changes for configurable duration, attempt timing, autosave, expiry, submission, marking, and audit state.
4. Implement and verify server-side save, submit/expiry, grading, and idempotent points workflows.
5. Implement the approved shared student interface and six response controls.
6. Implement teacher duration configuration and monitoring.
7. Test all six formats, manual submission, timeout on a partially completed question, autosave/reconnect, duplicate requests, teacher marking/partial credit, attempt locking, and points integrity.
8. Update `docs/IMPLEMENTATION_PROGRESS.md` with evidence and commit changes to `cloud-test` only.

## 10. Safety and release boundaries

- Apply database migrations manually only in `temmy-smart-classroom-test`.
- Work only on GitHub branch `cloud-test`.
- Never modify `main`, production Supabase, or the production website during this implementation.
- Inspect actual schema/code before writing migrations or changing application code.
- Do not claim implementation or tests are complete until verified.
