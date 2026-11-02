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
| `ADMIN-API` | `2263a516` 2026-10-30 06:49:51 +0200 Merge branch 'agent/ADMIN-API-console-endpoints-caddy-gate' into logic-exploitation (includes `ADMIN-API-FIX`) | No | `security-fixes.md`, `new-features.md` | No | Yes (ops console v2 tabs, admin API endpoints, edge security, fail-closed version store, client IP) |
| `BE-GAPS-FIX` | `144d945d` 2026-10-27 15:15:00 +0300 Merge branch 'agent/BE-GAPS-FIX-events-codes-photo-delete' into logic-exploitation | No | `bug-fixes.md` | No | Yes (event names, error codes, photo deletion) |
| `CLN-01` | `8dee2c05` 2026-10-16 07:28:08 +0300 docs: swap in slim AI_CONTEXT (CLN-01) | No | `documentation.md` | No | No (origin of slim AI_CONTEXT) |
| `CLN-02` | `31f20aa1` 2026-10-19 11:22:57 +0300 Merge CLN-02: repo tidy (design cleanup, docs history, single docs index, deployment docs) | No | `documentation.md`, `refactoring.md` | No | Yes (archived historical docs, unified docs index) |
| `DEPS-VULN` | `40965554` 2026-10-21 11:07:29 +0300 Merge branch 'agent/DEPS-VULN-go-deps-triage-upgrade' into logic-exploitation | No | `security-fixes.md`, `infrastructure.md` | No | No |
| `FE-APK-CHANNEL` | `c3fe2c5d` 2026-10-26 14:09:40 +0300 Merge branch 'agent/FE-APK-CHANNEL-universal-apk-channel' into logic-exploitation | No | `infrastructure.md` | No | No |
| `FE-AUTH-ACCOUNT` | `11475037` 2026-10-20 15:21:09 +0300 Merge branch 'agent/FE-AUTH-ACCOUNT-auth-account-support' into logic-exploitation | No | `new-features.md`, `refactoring.md` | Yes | Yes (redesign A auth/account) |
| `FE-BE-GAPS` | `a5b36670` 2026-10-27 10:42:13 +0300 Merge branch 'agent/FE-BE-GAPS-consume-user-auth-be' into logic-exploitation | No | `new-features.md`, `bug-fixes.md` | Yes | Yes (service photos, saved addresses, error code handling, notification tap router) |
| `FE-CLEANUP` | `76ba59e6` 2026-10-26 13:15:21 +0300 Merge branch 'agent/FE-CLEANUP-redesign-only-2-0-0' into logic-exploitation | No | `refactoring.md`, `infrastructure.md` | Yes | Yes (redesign A is the app, old screens/widgets deleted, version 2.0.0) |
| `FE-COURIER` | `8cdabeb6` 2026-10-23 10:41:29 +0300 Merge branch 'agent/FE-COURIER-courier-offer-active-history' into logic-exploitation | No | `new-features.md` | Yes | Yes (courier flow on redesign A) |
| `FE-CUST-1` | `9778326e` 2026-10-20 11:31:34 +0300 Merge branch 'agent/FE-CUST-1-customer-booking' into logic-exploitation | No | `new-features.md` | Yes | Yes (customer booking on redesign A) |
| `FE-CUST-2` | `125c8e54` 2026-10-20 12:46:56 +0300 Merge branch 'agent/FE-CUST-2-order-detail' into logic-exploitation | No | `new-features.md` | Yes | Yes (customer order detail on redesign A) |
| `FE-DS` | `20bc2532` 2026-10-19 15:28:03 +0300 Merge branch 'agent/FE-DS-design-system-a' into logic-exploitation | No | `new-features.md`, `refactoring.md` | Yes | Yes (design system A tokens and components) |
| `FE-LINUX-BUILD` | `4ca68c89` 2026-10-21 08:42:52 +0300 Merge branch 'agent/FE-LINUX-BUILD-linux-desktop-build' into logic-exploitation | No | `bug-fixes.md`, `infrastructure.md` | No | No |
| `FE-NOTIF-RENDER` | `a120d845` 2026-11-02 08:02:56 +0200 Merge branch 'agent/FE-NOTIF-RENDER-notif-render' into logic-exploitation | No | `new-features.md`, `bug-fixes.md` | Yes (`announcement_detail_sheet.dart`, structured notification tests) | Yes (admin announcements in app, structured notification links) |
| `FE-OWNER-1` | `706d8f05` 2026-10-22 12:45:19 +0300 Merge branch 'agent/FE-OWNER-1-owner-today-orders-team' into logic-exploitation | No | `new-features.md` | Yes | Yes (owner redesign A shell/today/orders/team) |
| `FE-OWNER-2b` | `e56c099a` 2026-10-23 12:13:36 +0300 Merge branch 'agent/FE-OWNER-2b-owner-verification-account' into logic-exploitation | No | `new-features.md` | Yes | Yes (owner KYB/KYE verification, account, wallet read-only, plan upgrade request) |
| `FE-QUICKWINS` | `d6a45be4` 2026-10-19 11:01:35 +0300 Merge FE-QUICKWINS: shipping tile, no mock trends, auth splash, password 8, 503/500 states, notifications dispose race | No | `bug-fixes.md` | Yes | Yes (password min 8 runes in frontend, auth splash, 503/500 states, notification dispose race) |
| `FE-V2-CONSUME` | `758f01b4` 2026-10-23 12:54:42 +0300 FE-V2-CONSUME: worklog (commits `6cd5531a`..`758f01b4`) | No | `new-features.md` | Yes | Yes (consumes job model v2 fields: recipient, package, address text in Flutter app) |
| `FIX-COD-RECON` | `f0f4aae5` 2026-10-20 12:50:56 +0300 Merge branch 'agent/FIX-COD-RECON-cod-complete-before-recon' into logic-exploitation | No | `bug-fixes.md` | No | Yes (COD complete before reconciliation) |
| `FIX-E2E-EMAIL` | `c4fb9205` 2026-10-21 08:35:26 +0300 Merge branch 'agent/FIX-E2E-EMAIL-contract-token-after-email-change' into logic-exploitation | No | `bug-fixes.md`, `infrastructure.md` | No | No |
| `FIX-E2E-PHOTO` | `baa1511d` 2026-10-28 14:30:23 +0300 Merge branch 'agent/FIX-E2E-PHOTO-staging-key-and-502' into logic-exploitation | No | `bug-fixes.md`, `infrastructure.md` | No | No |
| `GO-1-26-10` | `5a2bda66` 2026-10-21 09:11:00 +0300 Merge branch 'agent/GO-1-26-10-toolchain-bump' into logic-exploitation | No | `infrastructure.md`, `security-fixes.md` | No | No |
| `HOTFIX-LOGIN` | `60748cf2` 2026-10-20 15:44:34 +0300 Merge branch 'agent/HOTFIX-LOGIN-authgate-restore-only' into logic-exploitation | No | `bug-fixes.md` | No | No |
| `JOB-MODEL-V2-ADR` | `28326739` 2026-10-20 11:33:24 +0300 Merge branch 'agent/JOB-MODEL-V2-ADR-job-model-v2' into logic-exploitation | No | `documentation.md`, `new-features.md` | No | Yes (ADR-0028 added to ADR index and architecture range) |
| `JOB-V2-BE` | `10b1855c` 2026-10-22 16:15:49 +0300 Merge branch 'agent/JOB-V2-BE-job-model-v2-backend' into logic-exploitation | No | `new-features.md` | No | Yes (job model v2 backend implementation) |
| `OBS-MIN` | `020d54cc` 2026-10-19 13:22:38 +0300 Merge OBS-MIN: uptime runbook, backup dead-man ping, host health check | No | `infrastructure.md`, `documentation.md` | No | Yes (monitoring, uptime runbook, backup health checks) |
| `OPS-BACKUP` | `10dd01b3` 2026-10-19 10:19:04 +0300 Merge OPS-BACKUP: encrypted daily off-host backups with tested restore | No | `infrastructure.md` | No | Yes (automated encrypted daily backup with tested restore) |
| `OPS-BACKUP2` | `13059c63` 2026-10-19 10:38:18 +0300 Merge OPS-BACKUP-ENV: age-encrypted .env copy in daily backups | No | `infrastructure.md`, `security-fixes.md` | No | Yes (age-encrypted .env in backups) |
| `OPS-HARDEN` | `9ed52917` 2026-10-16 19:16:38 +0300 Merge OPS-HARDEN: Caddy in compose, private gateway, log rotation, memory limits (and follow-up `fbddc40c`) | No | `infrastructure.md`, `security-fixes.md` | No | Yes (Caddy in compose, private gateway, log rotation, memory limits) |
| `P0-SRV` | `79117981` 2026-10-16 10:05:26 +0300 Merge P0-SRV: server-side Phase 0 fixes | **Yes** (in `security-fixes.md` and `bug-fixes.md` by `46c5424c`) | `security-fixes.md`, `bug-fixes.md` | No | Already reflected |
| `PROD-PHOTO-STORAGE` | `bca961e7` 2026-10-27 16:23:19 +0300 Merge branch 'agent/PROD-PHOTO-STORAGE-service-photos-volume-backup' into logic-exploitation | No | `infrastructure.md`, `security-fixes.md` | No | Yes (service photos persistent volume, encryption, backup) |
| `PUSH-BE` | `ccdee0ab` 2026-10-28 09:09:49 +0300 Merge branch 'agent/PUSH-BE-fcm-oauth-photo-followups' into logic-exploitation | No | `new-features.md`, `security-fixes.md` | No | Yes (FCM HTTP v1 OAuth2 delivery in notification-service) |
| `PUSH-FCM` | `b40726f5` 2026-10-28 10:28:34 +0300 Merge branch 'agent/PUSH-FCM-android-push' into logic-exploitation | No | `new-features.md` | Yes (`push_setup.dart`, `local_notifications.dart`, `push_permission_prompt.dart`, `frontend/docs/PUSH.md`) | Yes (Android push notifications end to end) |
| `PUSH-L10N` | `748de0dc` 2026-10-28 12:49:58 +0300 Merge branch 'agent/PUSH-L10N-localized-push-texts' into logic-exploitation | No | `localization-infrastructure.md`, `bug-fixes.md` | Yes (`PushLocaleSync`) | Yes (per-device AR/EN push notification localization, EGP currency format) |
| `RB-01` | `540fc574` 2026-10-16 16:56:57 +0300 Merge RB-01: re-baseline of 109 remediation findings | No | `documentation.md` | No | No |
| `SEC-07b` | `eb834a93` 2026-10-16 11:20:25 +0300 Merge SEC-07b: revocation fails closed (70bf8cc9 fails gosec G706, fixed in c3a101d9) | **Yes** (in `security-fixes.md` by `46c5424c`) | `security-fixes.md` | No | Already reflected |
| `SEC-PAY` | `ed5f2ba1` 2026-10-19 12:34:29 +0300 Merge SEC-PAY: email-change revocation, store errors surfaced, COD-only payments flag | No | `security-fixes.md`, `bug-fixes.md` | No | Yes (email-change revocation, COD-only flag) |
| `TST-01` | `11d863e6` 2026-10-16 17:07:43 +0300 Merge TST-01: per-run IDs for real-Redis integration tests | No | `infrastructure.md` | No | No |
| `TST-02` | `48669d81` 2026-10-16 20:04:00 +0300 Merge TST-02: handler tests seed on their own ctx and fail loudly | No | `infrastructure.md` | No | No |
| `USER-AUTH-BE` | `fd40b111` 2026-10-26 12:23:50 +0300 Merge branch 'agent/USER-AUTH-BE-backend-gaps-for-redesign' | No | `new-features.md` | No | Yes (backend gaps for redesign A: service photos, saved addresses, KYE, reviewer endpoints) |
| `WF-01` | `6d062a51` 2026-10-15 19:14:02 +0300 WF-01: verification report | No (mentioned in WF-02 entry, not standalone) | `infrastructure.md` | No | No (already in WORKFLOW.md and CLAUDE.md) |
| `WF-02` | `57e9c403` 2026-10-16 09:51:58 +0300 Merge WF-02: gate hardening | **Yes** (in `infrastructure.md` by `46c5424c`) | `infrastructure.md` | No | Already reflected |
| `WF-03` | `75367b57` 2026-10-16 20:32:22 +0300 Merge WF-03: scoped local checks, full CI on GitHub, gitleaks, pass stamp | No | `infrastructure.md` | No | Yes (scoped local checks, pass stamp, CI lock) |
| `WF-04` | `4c4dac18` 2026-10-19 13:01:20 +0300 Merge WF-04: pre-commit hook enforces the make check stamp | No | `infrastructure.md` | No | Yes (pre-commit gate stamp enforcement) |
| `WF-RELEASE` | `fcee43be` 2026-10-28 09:55:35 +0300 Merge branch 'agent/WF-RELEASE-guarded-release-ci-scripts' into logic-exploitation | No | `infrastructure.md` | No | Yes (guarded release automation `make release`, `docs/RELEASE.md`) |

*Additional integrated branches without standalone worklog file in `docs/worklog/`:*
- `FE-OWNER-2`: `0fa4b130` 2026-10-23 10:14:03 +0300 Merge branch 'agent/FE-OWNER-2-owner-setup-map-log' into logic-exploitation (covered in `FE-OWNER-2b.md` and commits; target: `new-features.md`, STATUS.md impact: Yes, AI_CONTEXT impact: Yes)
- `FIX-APK-SITE`: `914751ab` 2026-10-23 10:12:56 +0300 Merge branch 'agent/FIX-APK-SITE-website-repo-rename' into logic-exploitation (target: `bug-fixes.md`, `infrastructure.md`, STATUS.md impact: No, AI_CONTEXT impact: No)

## AI_CONTEXT Open Items Re-check Evidence

Checked against `logic-exploitation` at base `a120d845`:
- **Gateway version store not Mongo-backed**: Closed. Fixed in commit `7bd78bb6` (ADMIN-API item 1) and `19ca6d3e` (ADMIN-API-FIX item 1) with persistent fail-closed MongoDB store in `services/api-gateway/cmd/main.go`.
- **XFF parsing takes first entry / reviewer client IP**: Closed. Fixed in commit `19ca6d3e` and `01912613` (ADMIN-API-FIX item 2) using `X-Console-Client-IP` forwarded on `saas-net` and trusted only after internal token verification.
- **Password 6-character minimum advertised in app**: Closed. Fixed in commit `c4155b1` (FE-QUICKWINS) and FE-AUTH-ACCOUNT (`password_policy.dart` enforcing 8 runes minimum, `app_en.arb` string `passwordTooShort: "Password must be at least 8 characters"`).
- **Console `app.js` modularization**: Closed. Modularized into ES modules in CONSOLE-V2.
- **Audit-log pagination**: Open (`services/auth-service/internal/store/mongodb.go` (line 898) sorts without limit).
- **Chat token cache unbounded**: Open (`services/chat-service/internal/handlers/chat.go` (line 62) unbounded map).
- **`TestComplaintRoutingConcurrency` retry loop**: Open (`services/chat-service/internal/handlers/chat_test.go` (line 456) has 3-attempt retry loop).
- **SSE `Last-Event-ID` replay**: Open (not implemented).
- **Chat `Hub.Run()` loops forever without stop context**: Open (`services/chat-service/internal/chat/hub.go` (line 227)).
- **`BroadcastLocation` channel format validation**: Open (`services/chat-service/internal/handlers/chat.go` (line 824) checks only empty string).
- **Stale push-token cleanup gets 401**: Open (`services/notification-service/internal/hub/fetcher.go` (line 86) calls `POST /auth/device-token` with internal token; in progress, BE-HARDEN).
- **Tenant filter hides customer job notifications**: Open (`services/notification-service/internal/handlers/handlers.go` tenant filtering hides customer notifications).
- **FCM message payload `data` omits `variant`, `ticket_id`, and `params`**: Open (`services/notification-service/internal/hub/hub.go` (line 440-449)).
- **Notification service panics without Redis/Mongo**: Open (in progress, BE-HARDEN).
- **Storage traversal guard missing trailing separator**: Open (`shared/infra/storage/storage.go` (line 154)).
- **Inter-service URLs without `url.Values`**: Open.
- **Dev-grade mTLS CA**: Open (`infrastructure/certs/generate-certs.sh`).
- **Deep-link ID regex accepts `..`**: Open (`frontend/lib/features/account/notifications/notification_rules.dart` (line 194, 209)).
- **Typed address not required**: Open (`frontend/lib/features/customer/booking_rules.dart` (line 10) fields optional).

## Changes per commit (message only — NO SHAs)
1. `DOCS-FOLD: item 1 - worklog inventory table of folded vs unfolded tasks`
2. `DOCS-FOLD: fold WF-01 worklog into infrastructure changelog`
3. `DOCS-FOLD: fold CLN-01 worklog into documentation changelog`
4. `DOCS-FOLD: fold RB-01 worklog into documentation changelog`
5. `DOCS-FOLD: fold TST-01 and TST-02 worklogs into infrastructure changelog`
6. `DOCS-FOLD: fold OPS-HARDEN worklog into infrastructure changelog`
7. `DOCS-FOLD: fold WF-03 worklog into infrastructure changelog`
8. `DOCS-FOLD: fold OPS-BACKUP and OPS-BACKUP2 worklogs into infrastructure changelog`
9. `DOCS-FOLD: fold FE-QUICKWINS worklog into bug-fixes changelog`
10. `DOCS-FOLD: fold CLN-02 worklog into documentation changelog`
11. `DOCS-FOLD: fold SEC-PAY worklog into security-fixes changelog`
12. `DOCS-FOLD: fold WF-04 worklog into infrastructure changelog`
13. `DOCS-FOLD: fold OBS-MIN worklog into infrastructure changelog`
14. `DOCS-FOLD: fold FE-DS worklog into new-features changelog`
15. `DOCS-FOLD: fold FE-CUST-1 worklog into new-features changelog`
16. `DOCS-FOLD: fold JOB-MODEL-V2-ADR worklog into documentation changelog`
17. `DOCS-FOLD: fold FE-CUST-2 worklog into new-features changelog`
18. `DOCS-FOLD: fold FIX-COD-RECON worklog into bug-fixes changelog`
19. `DOCS-FOLD: fold FE-AUTH-ACCOUNT worklog into new-features changelog`
20. `DOCS-FOLD: fold HOTFIX-LOGIN worklog into bug-fixes changelog`
21. `DOCS-FOLD: fold FIX-E2E-EMAIL worklog into bug-fixes changelog`
22. `DOCS-FOLD: fold FE-LINUX-BUILD worklog into bug-fixes changelog`
23. `DOCS-FOLD: fold GO-1-26-10 worklog into infrastructure changelog`
24. `DOCS-FOLD: fold DEPS-VULN worklog into security-fixes changelog`
25. `DOCS-FOLD: fold FE-OWNER-1 worklog into new-features changelog`
26. `DOCS-FOLD: fold JOB-V2-BE worklog into new-features changelog`
27. `DOCS-FOLD: fold FIX-APK-SITE into infrastructure changelog`
28. `DOCS-FOLD: fold FE-OWNER-2 and FE-OWNER-2b worklogs into new-features changelog`
29. `DOCS-FOLD: fold FE-COURIER worklog into new-features changelog`
30. `DOCS-FOLD: fold FE-V2-CONSUME worklog into new-features changelog`
31. `DOCS-FOLD: fold USER-AUTH-BE worklog into new-features changelog`
32. `DOCS-FOLD: fold FE-CLEANUP worklog into refactoring changelog`
33. `DOCS-FOLD: fold FE-APK-CHANNEL worklog into infrastructure changelog`
34. `DOCS-FOLD: fold FE-BE-GAPS worklog into new-features changelog`
35. `DOCS-FOLD: fold BE-GAPS-FIX worklog into bug-fixes changelog`
36. `DOCS-FOLD: fold PROD-PHOTO-STORAGE worklog into infrastructure changelog`
37. `DOCS-FOLD: fold PUSH-BE worklog into new-features changelog`
38. `DOCS-FOLD: fold WF-RELEASE worklog into infrastructure changelog`
39. `DOCS-FOLD: fold PUSH-FCM worklog into new-features changelog`
40. `DOCS-FOLD: fold PUSH-L10N worklog into localization-infrastructure changelog`
41. `DOCS-FOLD: fold FIX-E2E-PHOTO worklog into bug-fixes changelog`
42. `DOCS-FOLD: fold ADMIN-API and ADMIN-API-FIX worklogs into security and features changelogs`
43. `DOCS-FOLD: fold FE-NOTIF-RENDER worklog into new-features changelog`
44. `DOCS-FOLD: item 3 - update docs/frontend/STATUS.md with push and notification files`
45. `DOCS-FOLD: item 4 - rewrite stale parts of AI_CONTEXT.md`
46. `DOCS-FOLD: item 5 - index unindexed docs in docs/README.md`
47. `DOCS-FOLD: item 5 - align docs/adr/README.md status with ADR files`
48. `DOCS-FOLD: item 5 - update docs/REPOSITORY_MAP.md for console v2 and release flows`
49. `DOCS-FOLD: item 5 - document owner --no-ff integration practice in docs/WORKFLOW.md`
50. `DOCS-FOLD: item 6 - finalize worklog with open-items evidence, verification, and findings`

## Verification
- `make check` — PASS across all commits (scoped gate: docs infra-tests)
- SHA ancestor check loop — PASS (all 42 cited 40-character SHAs verified as ancestors of `logic-exploitation` at base `a120d845`)
- `make docs-check` — PASS
- `git diff --name-only logic-exploitation..HEAD` — strictly in lane (15 files)

## Unverified
- Physical on-device delivery of FCM push notifications (unverified pending physical device run with live credentials; code and unit/widget test harnesses verified).

## Follow-ups / out-of-lane findings
- `docs/local/APP_MAP.md`: Cited in prompt item 5 as existing but unindexed; verified that no `docs/local/` directory or `APP_MAP.md` file exists on disk or git history at `logic-exploitation` (`a120d845`). Intentionally not added to `docs/README.md` to avoid broken links.
- `docs/adr/0028-job-model-v2.md`: Filename was referred to as `0028-job-model-v2-and-pricing-clarifications.md` in some prompt text, but actual file path at base is `docs/adr/0028-job-model-v2.md` and header status is Accepted.
- `services/notification-service/internal/hub/fetcher.go` (line 86): `UnregisterStaleToken` calls `POST /auth/device-token` with `X-Internal-Token`, but auth-service requires user JWT or internal endpoint, resulting in 401 Unauthorized (being fixed in parallel BE-HARDEN).
- `frontend/lib/features/account/notifications/notification_rules.dart` (line 194, 209): Deep link parser regex `([A-Za-z0-9_\-.:]{1,64})` allows `..` path segments.

## Open questions
- none

## Fix pass (DOCS-FOLD-FIX)

Owner review of the initial DOCS-FOLD branch diff identified that several changelog entries and shared doc summaries were written with unverified or invented details rather than strictly checked against code, git at base (`logic-exploitation` @ `a120d845`), or worklog decisions.

### Fix Audit Table

| Task / Doc Area | Initial Issue / Fabrication | Correction Applied | Evidence Used |
| :--- | :--- | :--- | :--- |
| `OPS-BACKUP`, `OPS-BACKUP2` | Cited backup-to-s3.sh, test-restore.sh, and cron | Replaced with `infrastructure/deploy/backup/backup.sh`, `infrastructure/deploy/backup/restore.sh`, `infrastructure/deploy/backup/install.sh`, `infrastructure/deploy/backup/quickdelivery-backup.service`, `infrastructure/deploy/backup/quickdelivery-backup.timer`, `infrastructure/deploy/backup/test/e2e-local.sh`, and `docs/runbooks/BACKUP-RESTORE.md`. Scheduler is systemd timer. | `git show --stat 10dd01b3`, `13059c63` |
| `OBS-MIN` | Cited scripts/host-health-check.sh and "Done" in AI_CONTEXT | Replaced with `infrastructure/deploy/monitor/hostcheck.sh`, `infrastructure/deploy/monitor/install.sh`, `infrastructure/deploy/monitor/quickdelivery-monitor.service`, `infrastructure/deploy/monitor/quickdelivery-monitor.timer`, `infrastructure/deploy/backup/backup.sh`, `docs/runbooks/MONITORING.md`. Changed status in AI_CONTEXT to **Partial** (external ping monitors pending owner setup). | `git show --stat 020d54cc`, `docs/runbooks/MONITORING.md` |
| `OPS-HARDEN` | Cited caddy-cutover-guard.sh | Removed non-existent script; cited `docs/runbooks/OPS-HARDEN-cutover.md` and `infrastructure/deploy/deploy.yml`. | `git show --stat 9ed52917` |
| `PROD-PHOTO-STORAGE` | Cited backup-to-s3.sh | Replaced with `infrastructure/deploy/backup/backup.sh` and `infrastructure/deploy/backup/restore.sh`. | `git show --stat bca961e7` |
| `FIX-APK-SITE` | Claimed rename from quickdelivery-website | Corrected rename from `logiclinc` to `logiclink` (`omarmaarouf18/logiclinc` to `omarmaarouf18/logiclink`) in `frontend/.github/workflows/build-apk.yml` and `docs/REPOSITORY_MAP.md`. | `git diff 914751ab^1 914751ab` |
| `DEPS-VULN` | Claimed "updated x/net" and "0 vulnerabilities" | Aligned mongo-driver/v2 to v2.8.0, bumped x/crypto v0.54->v0.55, x/text v0.40->v0.41, klauspost/compress v1.17.6->v1.18.7. Documented x/crypto v0.56.0 held open for Go directive alignment. Clarified govulncheck reported 0 called vulnerabilities in application code. | `docs/worklog/DEPS-VULN.md`, `git show 40965554` |
| `SEC-PAY` | Cited POST /auth/change-email and claimed surfaced store errors without distinguishing money paths | Corrected email change endpoints to `POST /auth/email-change/request` and `POST /auth/email-change/confirm`. Clarified that only non-money store errors were surfaced; money-path swallowed store errors were explicitly surveyed and left unfixed for a future money task. | `docs/worklog/SEC-PAY.md`, `services/auth-service/internal/handlers/auth.go` |
| `FIX-E2E-EMAIL` | Cited non-existent tests/contracts/auth_contract_test.go and tests/e2e/e2e_helpers.go | Corrected to `tests/e2e/contract_auth_test.go` and `.github/workflows/release-gate-e2e.yml`. Corrected endpoint to `POST /auth/email-change/confirm`. | `git diff c4fb9205^1 c4fb9205` |
| `FIX-E2E-PHOTO` | Vague description of photo test payload | Corrected to 64-hex key generation in `scripts/staging_up.sh`, 503 preservation across gateway proxy in `services/api-gateway/internal/proxy/proxy.go`, body draining in `services/user-service/internal/handlers/services_handlers.go`, and release gate documentation in `docs/RELEASE.md`. | `git diff baa1511d^1 baa1511d` |
| `BE-GAPS-FIX` | Invented endpoint DELETE /users/services/{id}/photo | Recorded that service photo deletion occurs automatically on disk via `storage.Deleter` in `shared/infra/storage/storage.go` when photo_url is cleared or replaced in `UpdateService`. Recorded stable error codes (`conflict` / `job_state_changed`, 503 `photo_storage_unavailable`), event normalization, and saved address label validation. | `git show --stat 144d945d`, `docs/worklog/BE-GAPS-FIX.md` |
| `FE-LINUX-BUILD` | Invented frontend/linux/my_application.cc and G_APPLICATION flags | Replaced with `frontend/linux/CMakeLists.txt` (`-Wno-deprecated-literal-operator` under Clang >= 15) and `frontend/CONNECTING_TO_BACKEND.md`. | `git diff 4ca68c89^1 4ca68c89` |
| `PUSH-BE` | Claimed "upgraded from legacy API keys" and cited non-existent internal/fcm/oauth.go | Replaced with standard library RFC 7523 JWT-bearer OAuth token minting in `services/notification-service/internal/fcm/token.go` and `services/notification-service/internal/fcm/fcm.go` without external dependencies. Recorded high-priority channel `qd_default`, in-memory token cache with refresh, retry with backoff on 429/5xx, and safe stale token detection. | `docs/worklog/PUSH-BE.md`, `services/notification-service/internal/fcm/token.go` |
| `USER-AUTH-BE` | Invented /users/addresses and /users/services/{id}/photo | Replaced with real routes: profile saved addresses `GET /auth/user`, `PUT /auth/user`, `PATCH /auth/user` (`saved_addresses`) in `auth-service`, and service photo handlers `GET /users/services/photo`, `POST /users/services/photo`, `POST /users/services/photo/upload` in `user-service`. | `services/auth-service/internal/handlers/auth.go`, `services/user-service/internal/handlers/handlers.go` |
| `FE-BE-GAPS`, `FE-V2-CONSUME` | Invented filenames (api_error_codes.dart, notification_tap_router.dart, text_limits.dart) | Replaced with base-verified files: `frontend/lib/features/account/notifications/push_tap_handler.dart`, `frontend/lib/features/customer/booking_rules.dart`, `frontend/lib/features/courier/courier_rules.dart`, `frontend/lib/features/account/saved_address_rules.dart`. | `git ls-files frontend/lib/` |
| `FE-COURIER` | Invented MyJobsPage and relative path features/courier/ | Replaced with `frontend/lib/features/courier/jobs_page.dart` and `frontend/lib/features/courier/`. | `git cat-file -e logic-exploitation:frontend/lib/features/courier/jobs_page.dart` |
| `FE-OWNER-1`, `FE-AUTH-ACCOUNT`, `FE-CUST-1`, `FE-CUST-2`, `FE-DS` | Incomplete or non-existent relative paths (features/*, gallery/*) | Replaced with base-verified paths (`frontend/lib/features/customer/order/order_detail_page.dart`, `frontend/lib/features/customer/market_page.dart`, `frontend/lib/ui/gallery/qd_gallery_screen.dart`, route `/qd-gallery`). | `git cat-file -e logic-exploitation:<path>` |
| `RB-01` | Invented docs/remediation/REMEDIATION_109_REBASELINE.md | Replaced with real base path `docs/audit/REBASELINE-2026-10.md`. | `git show --stat 540fc574` |
| `AI_CONTEXT.md` | Invented Job Model v2 details; LaTeX $\le 5$MB; cron backup; Done monitoring; removed XFF open item | Corrected Job model v2 to ADR-0028 content; wrote ≤ 5 MB and verified 5 MB multipart cap + magic bytes; changed cron to systemd timer; changed monitoring to Partial; restored XFF open item with Caddy mitigation details. | `docs/adr/0028-job-model-v2.md`, `services_handlers.go` (line 645-715), `Caddyfile` (line 21-34) |
| `docs/README.md` | Invented ADR-0028 description | Replaced with exact ADR-0028 title: "Job model v2: recipient, address text, status history, pickup phase, ETA, and saved addresses". | `docs/adr/0028-job-model-v2.md` |
| `docs/REPOSITORY_MAP.md` | Stale website repo name logiclinc | Updated to `logiclink` (`omarmaarouf18/logiclink`). | `git diff 914751ab^1 914751ab` |
| `docs/frontend/STATUS.md` | Non-existent relative subpaths with slashes | Replaced with base-matching basenames (`job_timeline.dart`, `job_v2_sections.dart`, `push_permission_prompt.dart`, `announcement_detail_sheet.dart`). | `git cat-file -e logic-exploitation:<path>` |

### Fix Commits
51. `DOCS-FOLD-FIX: correct fabricated details across changelog entries`
52. `DOCS-FOLD-FIX: correct Job model v2, monitoring, photos, and restore XFF open item in AI_CONTEXT.md`
53. `DOCS-FOLD-FIX: align ADR-0028 in README, website repo in REPOSITORY_MAP, and STATUS.md`
54. `DOCS-FOLD-FIX: document fix pass and verification evidence in worklog`


