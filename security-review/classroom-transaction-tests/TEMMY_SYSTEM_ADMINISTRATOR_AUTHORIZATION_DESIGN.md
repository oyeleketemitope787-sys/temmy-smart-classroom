# Temmy System Administrator Authorization Design

**Status:** Approved design — implementation not authorized  
**Decision date:** 2026-11-09  
**Repository:** `oyeleketemitope787-sys/temmy-smart-classroom`  
**Branch:** `security-review/student-login-hardening`

## 1. Purpose

Define how privileged system-administrator authority is appointed, verified, limited, audited, and recovered for Temmy Smart Classroom. This design supports the approved system-wide award maximum policy: initially 20 points per individual student award, changeable only by an authorized system administrator.

This document records architecture decisions only. It does not authorize application changes, database changes, SQL execution, migrations, grants, configuration writes, or deployment.

## 2. Approved authority model

1. A single designated **Platform Owner** controls the appointment and removal of System Administrators.
2. A teacher cannot appoint themselves as a System Administrator, grant themselves administrative privileges, or change their own role through the classroom interface.
3. System Administrator authority must be established and verified on a trusted server-side boundary. It must never be accepted from a browser request body, client-side state, or an editable profile field.
4. System Administrators may change the system-wide maximum award configuration, subject to server-side authorization, validation, and audit requirements.
5. System Administrator status does not grant permission to bypass the trusted transaction layer, ledger rules, student/class ownership checks, idempotency controls, or other transaction invariants.
6. Appointment, removal, and every award-limit configuration change must be attributable to the responsible authorized actor and recorded in an audit trail.
7. Strong authentication, including MFA where supported, is required for privileged administrator accounts. A fresh MFA/re-authentication challenge is required before:
   - Changing the system-wide maximum award configuration.
   - Appointing a System Administrator.
   - Removing a System Administrator.

   These challenges are required even if the Platform Owner or administrator already has an active signed-in session. The appointment/removal challenge must be completed by the Platform Owner authorizing the change.

## 3. Platform Owner responsibilities

The Platform Owner is the root authority for the administrator appointment process. The Platform Owner may designate and remove System Administrators through a controlled, trusted administrative process.

The Platform Owner role must not be assignable through ordinary teacher registration, student registration, public sign-up, or a user-editable metadata field. There must be no self-service privilege escalation path.

The precise technical bootstrap and recovery mechanism for the initial Platform Owner must follow the approved controlled offline recovery procedure below and be designed before privileged roles are implemented.

## 4. System Administrator scope

A System Administrator may:
- Change the single system-wide maximum award amount, after satisfying the fresh MFA/re-authentication requirement.
- Review the relevant administrative configuration and audit history, subject to the eventual least-privilege design.

A System Administrator may not:
- Appoint another System Administrator or replace the Platform Owner unless a separately approved delegation model explicitly permits it.
- Bypass the Gateway or trusted database transaction functions.
- Write point ledger entries directly or alter protected student balances.
- Override class/student ownership checks, transaction idempotency, stock controls, reversal rules, or audit requirements.
- Set a different award maximum for an individual teacher or student.

The initial award maximum is **20 points per individual student award**. For an award action involving multiple selected students, the 20-point limit is evaluated separately for each student. An individual award request above 20 is rejected in full; it is not truncated or partially awarded. Only an authorized System Administrator may change the system-wide value, and each such change requires a fresh MFA/re-authentication challenge.

## 5. Trusted role verification

The implementation must select a server-controlled source of truth for Platform Owner and System Administrator assignments. Every privileged operation must verify the actor's authenticated identity and current administrative authority on the server side.

The implementation must not trust:
- A role, flag, or actor ID supplied in a request body.
- Browser local storage or client-side application state.
- User-editable profile fields or user-controlled authentication metadata.
- A hidden or disabled UI control as an authorization mechanism.

The exact role storage, provisioning workflow, token/session handling, and authorization checks remain to be specified and reviewed before implementation. The role source must be protected from writes by ordinary teachers and users.

## 6. Administrative audit requirements

At minimum, the audit design must capture:
- Administrator appointment and removal: acting Platform Owner, affected account, action, timestamp, and confirmation that the fresh MFA/re-authentication challenge was satisfied.
- Award-limit change: acting administrator, previous value, new value, timestamp, and confirmation that the fresh MFA/re-authentication challenge was satisfied.
- Platform Owner recovery: the two approving ownership representatives, recovery event, authorizing evidence/process reference, outcome, and timestamp, without storing recovery secrets or sensitive proof materials in ordinary application logs.
- The outcome of each administrative action.

Audit records must be protected against modification by ordinary teachers and users. Audit failure must not be silently ignored. The implementation must define retention, access, and recovery requirements before deployment.

## 7. Approved Platform Owner recovery approach

If the Platform Owner loses access, recovery must use a **controlled offline recovery procedure**. This is not a public or self-service account recovery route.

**Two-person approval is mandatory:** Platform Owner recovery requires independent verification and approval by **two separately authorized ownership representatives**. One representative acting alone cannot authorize or complete recovery. The two approvals must be independently attributable and recorded; the implementation must not treat two credentials controlled by the same person as two-person approval.

The procedure must:
1. Be documented and restricted to the legitimate platform ownership authority.
2. Require independent proof of ownership through a separately protected recovery method.
3. Obtain and verify approval from both authorized ownership representatives before any recovery action is carried out.
4. Be performed through a trusted administrative process outside ordinary teacher registration and the classroom UI.
5. Record the recovery event, both approving representatives, responsible recovery authority, outcome, and timestamp in a protected audit trail.
6. Notify the Platform Owner through a separately controlled notification channel where feasible.
7. Avoid creating a permanent backdoor, public recovery endpoint, or unrestricted emergency account.
8. Re-establish strong authentication, including MFA where supported, before normal privileged administration resumes.

Recovery secrets, proof documents, and other sensitive evidence must not be stored in ordinary application logs or exposed to teachers, students, or browser clients.

The exact ownership evidence, identity-verification method, appointment and independence of the two representatives, offline custodians, operational steps, notification channel, and audit implementation remain to be specified and security-reviewed before implementation. Recovery must not be enabled until those details are approved. The two-person approval requirement itself is approved and must not be weakened during implementation without a separate decision.

## 8. Proposed recovery-representative governance — pending approval

The following is a recommended governance model for deciding who may act as the two recovery representatives. It is a proposal only and does not yet authorize or appoint any individual.

1. **Selection authority:** The representatives should be designated through the platform's documented legal/business ownership authority, rather than being self-appointed by a System Administrator or selected informally through the classroom application. The exact authority depends on the platform's actual ownership structure and must be confirmed before implementation.
2. **Pre-designation:** Both representatives should be selected and recorded during secure Platform Owner bootstrap, before the platform relies on the recovery process. Their identities and acceptance should be recorded in a protected offline governance record.
3. **Independence:** The two representatives must be different natural persons, use separate contact and authentication channels, and not share recovery credentials. Neither may approve on behalf of the other. Neither representative receives routine System Administrator privileges merely by being a recovery representative.
4. **Identity verification:** Each representative's identity and authority should be verified independently using reliable identity evidence and an independently sourced contact channel. The specific evidence standard and verification operator must be defined in the offline runbook; sensitive identity documents should not be copied into ordinary application logs.
5. **Recovery approval:** For a recovery event, both representatives independently review the recovery request and evidence, then provide separate approvals through separately controlled channels. The recovery operator verifies both approvals and the evidence before acting. A request initiated by one representative cannot count as that representative's approval and the second person's approval.
6. **Replacement while the Platform Owner is available:** A representative may be replaced only through the documented ownership authority, with fresh MFA/re-authentication by the Platform Owner, independent identity verification and acceptance by the incoming representative, and an auditable record. The change must not create a period in which fewer than two valid representatives are designated.
7. **Replacement while the Platform Owner is unavailable:** The remaining representative cannot appoint a replacement alone. Any replacement must be authorized through the same independently documented legal/business ownership authority and independently verified process. If that authority cannot be established, recovery must pause rather than weaken the two-person rule.
8. **Periodic review:** The designated representatives and their secure contact methods should be reviewed periodically and whenever ownership, employment, or contact circumstances change. Review must not expose recovery secrets or grant routine application access.

Before implementation, the platform owner must confirm that this governance model matches the actual legal/business ownership structure and name the authority responsible for designating representatives. No real person's name, identity, contact detail, or authority is assumed in this design.

## 9. Remaining implementation gates

The following details are intentionally not decided by these approvals:
- Whether the proposed recovery-representative governance model in Section 8 is approved.
- The platform's actual legal/business ownership structure and the authority empowered to designate the two representatives.
- The identities of the two representatives and the independent identity-verification evidence/process.
- The exact server-side role source and provisioning mechanism.
- The detailed secure initial Platform Owner bootstrap procedure.
- The offline custodians, operational recovery runbook, and notification channel.
- Whether multiple Platform Owners or emergency/break-glass administrators are permitted outside the approved two-person recovery procedure.
- The exact MFA provider and technical challenge/session freshness mechanism.
- Audit schema, retention, access, and administrative review workflow.

These must be resolved before implementation. Any proposed change to the approved authority boundaries, two-person recovery approval, or offline recovery model requires a separate decision.

## 10. Security acceptance criteria

Before production use, tests and operational review must demonstrate that:
- A teacher cannot promote themselves or another user.
- A browser-supplied role or actor ID cannot confer administrator privileges.
- An unappointed account cannot change the system-wide award maximum.
- An appointed administrator cannot change the maximum without completing a fresh MFA/re-authentication challenge.
- An expired, missing, or failed challenge blocks the configuration change.
- A Platform Owner cannot appoint or remove an administrator without completing a fresh MFA/re-authentication challenge.
- An expired, missing, or failed challenge blocks an appointment or removal.
- Platform Owner recovery cannot proceed with only one ownership representative's approval.
- Both recovery approvals are independently attributable, verified, and recorded before recovery is performed.
- The offline recovery procedure cannot be initiated by an ordinary teacher, student, or unauthenticated public user and does not create a standing backdoor.
- If two valid representatives or required approvals are unavailable, recovery remains blocked until the separately approved ownership process resolves the issue.

## 11. Scope and safety boundary

This is an approved design record with the Section 8 governance proposal pending approval. Implementation is not authorized. No application code, database schema, SQL draft, role assignment, hosted configuration, permissions, migrations, or deployment has been changed or authorized by this document.

All future implementation and testing must remain isolated from the protected production branch `main` and shared development branch `cloud-test` unless separately and explicitly authorized.
