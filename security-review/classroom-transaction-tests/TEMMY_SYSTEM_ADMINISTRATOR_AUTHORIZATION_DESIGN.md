# Temmy System Administrator Authorization Design

**Status:** Approved design — implementation not authorized  
**Decision date:** 2026-11-09  
**Repository:** `oyeleketemitope787-sys/temmy-smart-classroom`  
**Branch:** `security-review/student-login-hardening`

## 1. Purpose

Define how privileged system-administrator authority is appointed, verified, limited, and audited for Temmy Smart Classroom. This design supports the approved system-wide award maximum policy: initially 20 points per individual student award, changeable only by an authorized system administrator.

This document records an architecture decision. It does not authorize application changes, database changes, SQL execution, migrations, grants, configuration writes, or deployment.

## 2. Approved authority model

1. A single designated **Platform Owner** controls the appointment and removal of System Administrators.
2. A teacher cannot appoint themselves as a System Administrator, grant themselves administrative privileges, or change their own role through the classroom interface.
3. System Administrator authority must be established and verified on a trusted server-side boundary. It must never be accepted from a browser request body, client-side state, or an editable profile field.
4. System Administrators may change the system-wide maximum award configuration, subject to server-side authorization, validation, and audit requirements.
5. System Administrator status does not grant permission to bypass the trusted transaction layer, ledger rules, student/class ownership checks, idempotency controls, or other transaction invariants.
6. Appointment, removal, and every award-limit configuration change must be attributable to the responsible authorized actor and recorded in an audit trail.
7. Strong authentication, including MFA where supported, is required for privileged administrator accounts and should be enforced before sensitive administrative actions.

## 3. Platform Owner responsibilities

The Platform Owner is the root authority for the administrator appointment process. The Platform Owner may designate and remove System Administrators through a controlled, trusted administrative process.

The Platform Owner role must not be assignable through ordinary teacher registration, student registration, public sign-up, or a user-editable metadata field. There must be no self-service privilege escalation path.

The precise technical bootstrap and recovery mechanism for the initial Platform Owner remains an implementation gate and must be designed before privileged roles are implemented.

## 4. System Administrator scope

A System Administrator may:
- Change the single system-wide maximum award amount.
- Review the relevant administrative configuration and audit history, subject to the eventual least-privilege design.

A System Administrator may not:
- Appoint another System Administrator or replace the Platform Owner unless a separately approved delegation model explicitly permits it.
- Bypass the Gateway or trusted database transaction functions.
- Write point ledger entries directly or alter protected student balances.
- Override class/student ownership checks, transaction idempotency, stock controls, reversal rules, or audit requirements.
- Set a different award maximum for an individual teacher or student.

The initial award maximum is **20 points per individual student award**. For an award action involving multiple selected students, the 20-point limit is evaluated separately for each student. An individual award request above 20 is rejected in full; it is not truncated or partially awarded. Only an authorized System Administrator may change the system-wide value.

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
- Administrator appointment and removal: acting Platform Owner, affected account, action, and timestamp.
- Award-limit change: acting administrator, previous value, new value, and timestamp.
- The outcome of each administrative action.

Audit records must be protected against modification by ordinary teachers and users. Audit failure must not be silently ignored. The implementation must define retention, access, and recovery requirements before deployment.

## 7. Remaining implementation gates

The following details are intentionally not decided by this approval:
- The exact server-side role source and provisioning mechanism.
- The secure initial Platform Owner bootstrap procedure.
- Platform Owner account recovery and loss-of-access procedure.
- Whether multiple Platform Owners or emergency/break-glass administrators are permitted.
- The exact MFA/re-authentication challenge required for privileged changes.
- Audit schema, retention, and administrative review workflow.

These must be resolved before implementation. Any proposed change to the approved authority boundaries requires a separate decision.

## 8. Security acceptance criteria

Before production use, tests must demonstrate that:
- A teacher cannot promote themselves or another user.
- A browser-supplied role or actor ID cannot confer administrator privileges.
- An unappointed account cannot change the system-wide award maximum.
- An appointed administrator can change the maximum only through the trusted server-side path.
- Every appointment, removal, and configuration change is attributable and audited.
- Administrator privileges cannot bypass classroom transaction invariants.
- Revoked administrator authority ceases to authorize subsequent privileged actions, including where sessions or tokens remain active.

## 9. Scope and safety boundary

This is an approved design record only. No application code, database schema, SQL draft, role assignment, hosted configuration, permissions, migrations, or deployment has been changed or authorized by this document.

All future implementation and testing must remain isolated from the protected production branch `main` and shared development branch `cloud-test` unless separately and explicitly authorized.
