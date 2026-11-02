# Worklog: DOCS-FOLD — catch up the shared docs with the code (worklog fold backlog + stale facts)

## Task and scope
- Task ID: DOCS-FOLD
- Item IDs covered: Item 1 (Inventory)
- Allowed paths (lane from the task prompt):
  - `AI_CONTEXT.md`
  - `docs/changelog/**` (including the counts in `docs/changelog/README.md`)
  - `docs/frontend/STATUS.md`
  - `docs/README.md` (docs index)
  - `docs/adr/README.md` (index only, never the ADR files themselves)
  - `docs/REPOSITORY_MAP.md`
  - `docs/WORKFLOW.md` (only the merge-procedure drift in item 5)
  - `docs/worklog/DOCS-FOLD.md`
- Agent branch: `agent/DOCS-FOLD-shared-docs-catchup`, created from `logic-exploitation` (short SHA `a120d845`)

## Decisions taken
- **Inventory verification**: Verified every merge and integration commit against `logic-exploitation` first-parent git history and confirmed ancestry via `git merge-base --is-ancestor`.
- **Changelog fold status audit**: Audited changelog files by content rather than just task ID. Verified that only `P0-SRV`, `SEC-07b`, and `WF-02` were folded (in commit `46c5424c` on 2026-10-16). `WF-01` was mentioned inside `WF-02` prose but never had a standalone entry. All subsequent integrations (from 2026-10-16 through 2026-11-02) have not been folded into `docs/changelog/**`.
- **Item 1 scope**: Committed worklog inventory only, with zero shared doc edits in this initial step.

## Item 1: Worklog Inventory Table

| Task ID | Merge commit on `logic-exploitation` | Already folded? | Target changelog category(ies) | STATUS.md impact? | AI_CONTEXT impact? |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `ADMIN-API` | `2263a516 2026-10-30 06:49:51 +0200 Merge branch 'agent/ADMIN-API-console-endpoints-caddy-gate' into logic-exploitation` (includes `ADMIN-API-FIX`) | No | `security-fixes.md`, `new-features.md` | No | Yes (ops console v2 tabs, admin API endpoints, edge security, fail-closed version store, client IP) |
| `BE-GAPS-FIX` | `144d945d 2026-10-27 15:15:00 +0300 Merge branch 'agent/BE-GAPS-FIX-events-codes-photo-delete' into logic-exploitation` | No | `bug-fixes.md` | No | Yes (event names, error codes, photo deletion) |
| `CLN-01` | `8dee2c05 2026-10-16 07:28:08 +0300 docs: swap in slim AI_CONTEXT (CLN-01)` | No | `documentation.md` | No | No (origin of slim AI_CONTEXT) |
| `CLN-02` | `31f20aa1 2026-10-19 11:22:57 +0300 Merge CLN-02: repo tidy (design cleanup, docs history, single docs index, deployment docs)` | No | `documentation.md`, `refactoring.md` | No | Yes (archived historical docs, unified docs index) |
| `DEPS-VULN` | `40965554 2026-10-21 11:07:29 +0300 Merge branch 'agent/DEPS-VULN-go-deps-triage-upgrade' into logic-exploitation` | No | `security-fixes.md`, `infrastructure.md` | No | No |
| `FE-APK-CHANNEL` | `c3fe2c5d 2026-10-26 14:09:40 +0300 Merge branch 'agent/FE-APK-CHANNEL-universal-apk-channel' into logic-exploitation` | No | `infrastructure.md` | No | No |
| `FE-AUTH-ACCOUNT` | `11475037 2026-10-20 15:21:09 +0300 Merge branch 'agent/FE-AUTH-ACCOUNT-auth-account-support' into logic-exploitation` | No | `new-features.md`, `refactoring.md` | Yes | Yes (redesign A auth/account) |
| `FE-BE-GAPS` | `a5b36670 2026-10-27 10:42:13 +0300 Merge branch 'agent/FE-BE-GAPS-consume-user-auth-be' into logic-exploitation` | No | `new-features.md`, `bug-fixes.md` | Yes | Yes (service photos, saved addresses, error code handling, notification tap router) |
| `FE-CLEANUP` | `76ba59e6 2026-10-26 13:15:21 +0300 Merge branch 'agent/FE-CLEANUP-redesign-only-2-0-0' into logic-exploitation` | No | `refactoring.md`, `infrastructure.md` | Yes | Yes (redesign A is the app, old screens/widgets deleted, version 2.0.0) |
| `FE-COURIER` | `8cdabeb6 2026-10-23 10:41:29 +0300 Merge branch 'agent/FE-COURIER-courier-offer-active-history' into logic-exploitation` | No | `new-features.md` | Yes | Yes (courier flow on redesign A) |
| `FE-CUST-1` | `9778326e 2026-10-20 11:31:34 +0300 Merge branch 'agent/FE-CUST-1-customer-booking' into logic-exploitation` | No | `new-features.md` | Yes | Yes (customer booking on redesign A) |
| `FE-CUST-2` | `125c8e54 2026-10-20 12:46:56 +0300 Merge branch 'agent/FE-CUST-2-order-detail' into logic-exploitation` | No | `new-features.md` | Yes | Yes (customer order detail on redesign A) |
| `FE-DS` | `20bc2532 2026-10-19 15:28:03 +0300 Merge branch 'agent/FE-DS-design-system-a' into logic-exploitation` | No | `new-features.md`, `refactoring.md` | Yes | Yes (design system A tokens and components) |
| `FE-LINUX-BUILD` | `4ca68c89 2026-10-21 08:42:52 +0300 Merge branch 'agent/FE-LINUX-BUILD-linux-desktop-build' into logic-exploitation` | No | `bug-fixes.md`, `infrastructure.md` | No | No |
| `FE-NOTIF-RENDER` | `a120d845 2026-11-02 08:02:56 +0200 Merge branch 'agent/FE-NOTIF-RENDER-notif-render' into logic-exploitation` | No | `new-features.md`, `bug-fixes.md` | Yes (`announcement_detail_sheet.dart`, structured notification tests) | Yes (admin announcements in app, structured notification links) |
| `FE-OWNER-1` | `706d8f05 2026-10-22 12:45:19 +0300 Merge branch 'agent/FE-OWNER-1-owner-today-orders-team' into logic-exploitation` | No | `new-features.md` | Yes | Yes (owner redesign A shell/today/orders/team) |
| `FE-OWNER-2b` | `e56c099a 2026-10-23 12:13:36 +0300 Merge branch 'agent/FE-OWNER-2b-owner-verification-account' into logic-exploitation` | No | `new-features.md` | Yes | Yes (owner KYB/KYE verification, account, wallet read-only, plan upgrade request) |
| `FE-QUICKWINS` | `d6a45be4 2026-10-19 11:01:35 +0300 Merge FE-QUICKWINS: shipping tile, no mock trends, auth splash, password 8, 503/500 states, notifications dispose race` | No | `bug-fixes.md` | Yes | Yes (password min 8 runes in frontend, auth splash, 503/500 states, notification dispose race) |
| `FE-V2-CONSUME` | `758f01b4 2026-10-23 12:54:42 +0300 FE-V2-CONSUME: worklog` (commits `6cd5531a`..`758f01b4`) | No | `new-features.md` | Yes | Yes (consumes job model v2 fields: recipient, package, address text in Flutter app) |
| `FIX-COD-RECON` | `f0f4aae5 2026-10-20 12:50:56 +0300 Merge branch 'agent/FIX-COD-RECON-cod-complete-before-recon' into logic-exploitation` | No | `bug-fixes.md` | No | Yes (COD complete before reconciliation) |
| `FIX-E2E-EMAIL` | `c4fb9205 2026-10-21 08:35:26 +0300 Merge branch 'agent/FIX-E2E-EMAIL-contract-token-after-email-change' into logic-exploitation` | No | `bug-fixes.md`, `infrastructure.md` | No | No |
| `FIX-E2E-PHOTO` | `baa1511d 2026-10-28 14:30:23 +0300 Merge branch 'agent/FIX-E2E-PHOTO-staging-key-and-502' into logic-exploitation` | No | `bug-fixes.md`, `infrastructure.md` | No | No |
| `GO-1-26-10` | `5a2bda66 2026-10-21 09:11:00 +0300 Merge branch 'agent/GO-1-26-10-toolchain-bump' into logic-exploitation` | No | `infrastructure.md`, `security-fixes.md` | No | No |
| `HOTFIX-LOGIN` | `60748cf2 2026-10-20 15:44:34 +0300 Merge branch 'agent/HOTFIX-LOGIN-authgate-restore-only' into logic-exploitation` | No | `bug-fixes.md` | No | No |
| `JOB-MODEL-V2-ADR` | `28326739 2026-10-20 11:33:24 +0300 Merge branch 'agent/JOB-MODEL-V2-ADR-job-model-v2' into logic-exploitation` | No | `documentation.md`, `new-features.md` | No | Yes (ADR-0028 added to ADR index and architecture range) |
| `JOB-V2-BE` | `10b1855c 2026-10-22 16:15:49 +0300 Merge branch 'agent/JOB-V2-BE-job-model-v2-backend' into logic-exploitation` | No | `new-features.md` | No | Yes (job model v2 backend implementation) |
| `OBS-MIN` | `020d54cc 2026-10-19 13:22:38 +0300 Merge OBS-MIN: uptime runbook, backup dead-man ping, host health check` | No | `infrastructure.md`, `documentation.md` | No | Yes (monitoring, uptime runbook, backup health checks) |
| `OPS-BACKUP` | `10dd01b3 2026-10-19 10:19:04 +0300 Merge OPS-BACKUP: encrypted daily off-host backups with tested restore` | No | `infrastructure.md` | No | Yes (automated encrypted daily backup with tested restore) |
| `OPS-BACKUP2` | `13059c63 2026-10-19 10:38:18 +0300 Merge OPS-BACKUP-ENV: age-encrypted .env copy in daily backups` | No | `infrastructure.md`, `security-fixes.md` | No | Yes (age-encrypted .env in backups) |
| `OPS-HARDEN` | `9ed52917 2026-10-16 19:16:38 +0300 Merge OPS-HARDEN: Caddy in compose, private gateway, log rotation, memory limits` (and follow-up `fbddc40c`) | No | `infrastructure.md`, `security-fixes.md` | No | Yes (Caddy in compose, private gateway, log rotation, memory limits) |
| `P0-SRV` | `79117981 2026-10-16 10:05:26 +0300 Merge P0-SRV: server-side Phase 0 fixes` | **Yes** (in `security-fixes.md` and `bug-fixes.md` by `46c5424c`) | `security-fixes.md`, `bug-fixes.md` | No | Already reflected |
| `PROD-PHOTO-STORAGE` | `bca961e7 2026-10-27 16:23:19 +0300 Merge branch 'agent/PROD-PHOTO-STORAGE-service-photos-volume-backup' into logic-exploitation` | No | `infrastructure.md`, `security-fixes.md` | No | Yes (service photos persistent volume, encryption, backup) |
| `PUSH-BE` | `ccdee0ab 2026-10-28 09:09:49 +0300 Merge branch 'agent/PUSH-BE-fcm-oauth-photo-followups' into logic-exploitation` | No | `new-features.md`, `security-fixes.md` | No | Yes (FCM HTTP v1 OAuth2 delivery in notification-service) |
| `PUSH-FCM` | `b40726f5 2026-10-28 10:28:34 +0300 Merge branch 'agent/PUSH-FCM-android-push' into logic-exploitation` | No | `new-features.md` | Yes (`push_setup.dart`, `local_notifications.dart`, `push_permission_prompt.dart`, `frontend/docs/PUSH.md`) | Yes (Android push notifications end to end) |
| `PUSH-L10N` | `748de0dc 2026-10-28 12:49:58 +0300 Merge branch 'agent/PUSH-L10N-localized-push-texts' into logic-exploitation` | No | `localization-infrastructure.md`, `bug-fixes.md` | Yes (`PushLocaleSync`) | Yes (per-device AR/EN push notification localization, EGP currency format) |
| `RB-01` | `540fc574 2026-10-16 16:56:57 +0300 Merge RB-01: re-baseline of 109 remediation findings` | No | `documentation.md` | No | No |
| `SEC-07b` | `eb834a93 2026-10-16 11:20:25 +0300 Merge SEC-07b: revocation fails closed (70bf8cc9 fails gosec G706, fixed in c3a101d9)` | **Yes** (in `security-fixes.md` by `46c5424c`) | `security-fixes.md` | No | Already reflected |
| `SEC-PAY` | `ed5f2ba1 2026-10-19 12:34:29 +0300 Merge SEC-PAY: email-change revocation, store errors surfaced, COD-only payments flag` | No | `security-fixes.md`, `bug-fixes.md` | No | Yes (email-change revocation, COD-only flag) |
| `TST-01` | `11d863e6 2026-10-16 17:07:43 +0300 Merge TST-01: per-run IDs for real-Redis integration tests` | No | `infrastructure.md` | No | No |
| `TST-02` | `48669d81 2026-10-16 20:04:00 +0300 Merge TST-02: handler tests seed on their own ctx and fail loudly` | No | `infrastructure.md` | No | No |
| `USER-AUTH-BE` | `fd40b111 2026-10-26 12:23:50 +0300 Merge branch 'agent/USER-AUTH-BE-backend-gaps-for-redesign'` | No | `new-features.md` | No | Yes (backend gaps for redesign A: service photos, saved addresses, KYE, reviewer endpoints) |
| `WF-01` | `6d062a51 2026-10-15 19:14:02 +0300 WF-01: verification report` | No (mentioned in WF-02 entry, not standalone) | `infrastructure.md` | No | No (already in WORKFLOW.md and CLAUDE.md) |
| `WF-02` | `57e9c403 2026-10-16 09:51:58 +0300 Merge WF-02: gate hardening` | **Yes** (in `infrastructure.md` by `46c5424c`) | `infrastructure.md` | No | Already reflected |
| `WF-03` | `75367b57 2026-10-16 20:32:22 +0300 Merge WF-03: scoped local checks, full CI on GitHub, gitleaks, pass stamp` | No | `infrastructure.md` | No | Yes (scoped local checks, pass stamp, CI lock) |
| `WF-04` | `4c4dac18 2026-10-19 13:01:20 +0300 Merge WF-04: pre-commit hook enforces the make check stamp` | No | `infrastructure.md` | No | Yes (pre-commit gate stamp enforcement) |
| `WF-RELEASE` | `fcee43be 2026-10-28 09:55:35 +0300 Merge branch 'agent/WF-RELEASE-guarded-release-ci-scripts' into logic-exploitation` | No | `infrastructure.md` | No | Yes (guarded release automation `make release`, `docs/RELEASE.md`) |

*Additional integrated branches without standalone worklog file in `docs/worklog/`:*
- `FE-OWNER-2`: `0fa4b130 2026-10-23 10:14:03 +0300 Merge branch 'agent/FE-OWNER-2-owner-setup-map-log' into logic-exploitation` (covered in `FE-OWNER-2b.md` and commits; target: `new-features.md`, STATUS.md impact: Yes, AI_CONTEXT impact: Yes)
- `FIX-APK-SITE`: `914751ab 2026-10-23 10:12:56 +0300 Merge branch 'agent/FIX-APK-SITE-website-repo-rename' into logic-exploitation` (target: `bug-fixes.md`, `infrastructure.md`, STATUS.md impact: No, AI_CONTEXT impact: No)

## Changes per commit (message only — NO SHAs)
1. `DOCS-FOLD: item 1 - worklog inventory table of folded vs unfolded tasks`

## Verification
- `make check` — PASS

## Unverified
- none

## Follow-ups / out-of-lane findings
- none

## Open questions
- none
