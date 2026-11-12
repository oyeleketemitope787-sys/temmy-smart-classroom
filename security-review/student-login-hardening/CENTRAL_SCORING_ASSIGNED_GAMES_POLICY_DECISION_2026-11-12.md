# Central Scoring Policy Decision — Assigned Games Only

**Decision date:** 2026-11-12  
**Status:** User-confirmed product rule; design baseline  
**Branch:** `security-review/student-login-hardening`  
**Scope:** Policy clarification only. This document does not authorize code changes, SQL execution, database changes, secrets, feature flags, or deployment.

## 1. Confirmed reward policy

**Only assigned games may generate Temmy Smart Classroom reward points.** A reward is permitted only after the server has verified the result of a valid assigned-game session.

The policy applies regardless of whether the player is a Classroom student or a member of the public.

| Gameplay context | Requires Classroom assignment session | Calls reward-scoring gateway | Classroom points |
|---|---:|---:|---:|
| Public practice | No | No | Never |
| Student practice not launched as an assignment | No | No | Never |
| Assigned game with valid session | Yes | Yes | Verified final score only |
| Assigned game with invalid, expired, consumed, or mismatched session | Yes, but validation fails | May be rejected before scoring | Never |
| Retry of an already committed answer/result | Same original assignment context | Yes, using the same idempotency key | No second award |

## 2. Separate gameplay mode from reward eligibility

The existing gateway contract uses game modes such as `practice`, `challenge`, and `class`. These are gameplay-mode values; they must not be treated as proof that a game is assigned or eligible for reward points.

Reward eligibility is determined by trusted server-side validation of the Classroom assignment session and its stored student, class, game, expiry, and consumption state. It is not determined by a browser-supplied mode, student ID, score, or reward flag.

A future assigned game may offer different gameplay modes. The product must define which modes are offered for an assignment, but no mode value alone may grant reward eligibility.

## 3. Required architecture

### Public and student practice
- Practice remains available to the public and to students.
- Unassigned practice does not require a Classroom assignment session.
- Unassigned practice does not call the reward-scoring gateway and cannot create Classroom point transactions.
- Logging in as a student, by itself, does not turn practice into an assigned game.

### Assigned gameplay
- An assigned game is launched with a valid Classroom-issued session credential.
- The gateway validates the assignment session using trusted server-side state.
- Student, class, and game identity are derived from that validated session, not from client identity claims.
- Questions, answer verification, score calculation, and final award are controlled by trusted server-side logic.
- The exact verified final score is the points award, under the registered game scoring rule.
- Completion, session consumption, idempotency outcome, and the single points-ledger award must commit atomically.
- Invalid sessions, invalid answers, conflicting retries, and system failures must not produce an award.
- Identical retries must return the original safe result and must never create a second point transaction.

## 4. Gateway contract implications

1. The gateway is the future central scoring boundary between Temmy Smart Classroom and Temmy Smart Games.
2. The gateway is for assigned-game scoring, not public or unassigned practice.
3. A missing assignment session must never be converted into a reward-capable anonymous practice request.
4. A valid assignment session is necessary but not sufficient: game ID, session state, expiry, student/class relationship, attempt state, answer sequence, and scoring rule must also be verified.
5. The browser must never supply an authoritative score, maximum score, correctness flag, points award, or student identity.
6. Every logical start/answer operation must use the approved request-idempotency protocol before activation.
7. No reward is shown as awarded until the final database transaction has committed and the trusted response has been validated.

## 5. Review findings to carry forward

The current review-branch gateway request validator requires a session token for both `start_attempt` and `submit_answer`. This is consistent with the gateway being assigned-game-only. Public and unassigned student practice should remain outside this reward gateway.

The current request validator does not yet include the `request_id` described in the transaction pseudocode. This is a contract/design gap to resolve before implementation approval; it is not permission to execute SQL or activate the gateway.

The current mode enum includes `practice`, `challenge`, and `class`. These values must remain distinct from assignment context. Do not infer that `mode: "practice"` means public/unassigned play or that it disables reward eligibility for an otherwise valid assigned session. The assignment policy and allowed mode choices must be explicit in the future product contract.

## 6. Release and safety gates

- This decision does not authorize using existing games for testing.
- Build Temmy Smart Games from scratch after the Temmy Smart Classroom launch, as planned.
- Do not modify the existing game repository or migrate an existing game client as part of this gateway review.
- Do not execute proposed SQL, alter the shared Supabase TEST project or `temmy_classroom_local`, change ACLs, configure feature flags, deploy functions, or touch production.
- Integration testing requires a separately provisioned disposable environment with synthetic data and explicit approval.
- The gateway remains review-only and default-deny until all security, transaction, rate-limit, integration, and release gates are independently satisfied.

## 7. Product decision recorded

User-confirmed rule: **Only assigned games: verified scores generate Classroom reward points.**
