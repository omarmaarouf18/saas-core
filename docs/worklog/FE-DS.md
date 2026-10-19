# Worklog: FE-DS — redesign A design system (tokens + components)

## Task and scope
- Task ID: FE-DS
- Item IDs covered: 1 (mockups + DESIGN_SYSTEM.md), 2 (tokens, theme, font), 3 (components + tests + l10n), 4 (debug gallery + goldens)
- Allowed paths (lane): frontend/lib/ui/**, frontend/assets/fonts/**, frontend/pubspec.yaml (fonts + assets only), frontend/lib/l10n/*.arb + generated l10n, frontend/test/ui/**, frontend/lib/main.dart (debug gallery route only), docs/design/redesign-a/**, docs/design/DESIGN_SYSTEM.md, docs/worklog/FE-DS.md
- Agent branch: agent/FE-DS-design-system-a, created from logic-exploitation

## Decisions taken
- **Mockups source.** `docs/design/redesign-a/` was an empty directory in the worktree. The 27 mockups were taken from `~/Documents/Claude outputs/redesign-a.zip` (same 27 file names the screen map links to, created minutes before the worktree) and committed as-is. Owner: confirm this is the approved set.
- **Font source.** IBM Plex Sans Arabic 400/500/600/700 + `OFL.txt` downloaded from the official google/fonts repo (`ofl/ibmplexsansarabic`, version 1.101). License shipped as `frontend/assets/fonts/IBMPlexSansArabic-OFL.txt`; already covered by the existing `assets/fonts/` asset entry, so pubspec only gained the `fonts:` family block. pubspec.lock unchanged.
- **New ARB keys, no edits to old ones.** Existing `status*` keys are Title Case ("Awaiting Price") and used by current screens and their Ahem goldens, so the components use new `qd*` keys (sentence case, Egyptian Arabic). Reused existing `retry`, `showPassword`, `hidePassword`. Nothing removed.
- **Status mapping tones** (prompt fixed only the colours): pending / pending_dispatch / awaiting_price_response / under review → warning; assigned / active → success; completed → neutral (mockup A-Orders shows delivered in neutral grey); cancelled and unavailable → danger. `unavailable` is danger, not warning, because nothing happens without a retry. Owner may re-tone in one place: `QdJobStatus` in `lib/ui/components/qd_status_chip.dart`.
- **Pending cancellation chip** is shown whenever `cancellation_request_status == "pending"`, regardless of job status (literal reading of the prompt).
- **Money digits.** Western digits and `,` thousands separator in both languages (`1,250 ج.م`, `EGP 1,250`), as in the mockups; whole amounts without decimals, fractions with two. Currency placement comes from the `qdMoneyAmount` ARB template.
- **Segmented control** uses a 1 px border on the selected tab instead of the mockup's tiny box-shadow (rule: borders, not shadows).
- **Banners** follow C-History: tone fill (`#F3F4F6` info, `#FEF3C7` warning, `#FEE2E2` danger), navy text, tone-coloured icon, radius 14.
- **Dark tokens** (not wired): surface `#0D1321`, cards `#161D2E`, fills `#1F2738`, borders `#273047`, text `#F9FAFB` / `#9CA3AF`, same gold; light status colours replaced by AA-passing pairs (table in DESIGN_SYSTEM.md).
- **Goldens location.** Gallery goldens live in `frontend/test/ui/goldens/` (inside the lane), not `frontend/test/goldens/`. They load the bundled Plex font through `FontLoader`, unlike the screen goldens (Ahem), so Arabic shaping is reviewable. MaterialIcons is not loaded (icons are test-font boxes, same as the screen goldens).
- **Gallery sample text** (names, addresses) is debug-only demo data picked by locale inside `qd_gallery_screen.dart`, not ARB. All component-owned strings are ARB.
- **Worklog git log.** Per CLAUDE.md (no SHAs in committed files on agent branches; short SHAs in the chat report only) this file lists commit subjects; the literal `git log --oneline` with short SHAs is in the final chat report.

## Changes per commit (message only — NO SHAs)
1. `FE-DS: add redesign-a mockups and design system doc`
2. `FE-DS: add redesign-a tokens, theme and bundled Plex font`
3. `FE-DS: add redesign-a components with widget tests`
4. `FE-DS: add debug-only design system gallery and goldens`
5. `FE-DS: worklog` (this file)

No file under `frontend/lib/screens/` or `frontend/lib/widgets/` was touched; the app theme (`core/theme.dart`, `main.dart` theme wiring) is unchanged. `main.dart` only gained the import and the `kDebugMode` `/qd-gallery` route.

## Items
1. Mockups + DESIGN_SYSTEM.md — **done**.
2. Tokens (`lib/ui/tokens.dart`), theme (`lib/ui/qd_theme.dart`, light + dark, not wired), bundled font + OFL — **done**.
3. Components in `lib/ui/components/`, each with widget tests in `test/ui/` — **done**: QdButton, QdTextField, QdCard, QdListGroup + QdListTile, QdStatusChip + QdJobStatus mapping + QdJobStatusChips, QdSegmented, QdBottomNav, QdRouteLines, QdStepProgress, QdTimeline, QdAvatarInitial, QdSectionHeader, QdEmptyState, QdErrorState, QdBanner, QdCountdown, QdBottomSheet, QdMoney (unit tests). Barrel: `lib/ui/qd_ui.dart`.
4. Debug-only gallery (`lib/ui/gallery/qd_gallery_screen.dart`, route `/qd-gallery` under `kDebugMode`) + goldens of 10 sections × AR-RTL / EN-LTR at 360x800 light — **done** (CI rendering not yet observed, see Unverified).

## Job statuses and chip mapping

Sources: `services/user-service/internal/models/models.go` (`JobStatus*` constants: pending, pending_dispatch, unavailable, awaiting_price_response, active, completed, cancelled, escrow_reconciliation_required), `frontend/lib/core/enum_labels.dart` (`canceled`, `reconciliation_required` aliases) and the frontend-only `assigned` (customer_home_screen / customer_jobs_screen; the backend never emits it), plus `cancellation_request_status` (pending / approved / rejected / expired).

| Backend value | QdJobStatus | EN | AR | Tone |
|---|---|---|---|---|
| `pending` | pending | Waiting for courier | مستني مندوب | warning |
| `pending_dispatch` | pendingDispatch | Finding a courier | بندور على مندوب | warning |
| `unavailable` | unavailable | No courier available | مفيش مندوب متاح | danger |
| `awaiting_price_response` | awaitingPrice | New price offered | فيه عرض سعر | warning |
| `assigned` | assigned | Courier assigned | المندوب قبل | success |
| `active` | active | On the way | في الطريق | success |
| `completed` | completed | Delivered | اتسلم | neutral |
| `cancelled`, `canceled` | cancelled | Cancelled | اتلغى | danger |
| `escrow_reconciliation_required`, `reconciliation_required` | underReview | Under review | بيتراجع | warning |
| `cancellation_request_status == "pending"` (extra chip) | cancellationRequested | Cancellation requested | طلب إلغاء | warning |
| anything else, empty, null | unknown | Unknown status | حالة مش معروفة | neutral |

Matching ignores case and surrounding whitespace. Covered by `test/ui/qd_status_chip_test.dart`.

## Verification

Literal output (captured on the final tree before this worklog commit):

```
$ git diff --stat logic-exploitation..HEAD | tail -5
 frontend/test/ui/qd_route_progress_test.dart       | 115 +++++
 frontend/test/ui/qd_status_chip_test.dart          | 106 ++++
 frontend/test/ui/qd_text_field_test.dart           |  67 +++
 frontend/test/ui/tokens_test.dart                  | 128 +++++
 91 files changed, 7226 insertions(+), 2 deletions(-)
$ git diff --stat logic-exploitation..HEAD -- frontend/test/goldens
(end)
$ flutter analyze
Analyzing frontend...                                           
No issues found! (ran in 0.8s)
$ flutter test
00:34 +905: All tests passed!
$ flutter test test/ui
00:03 +102: All tests passed!
```

`(end)` is a marker echoed after the command: the diff on `frontend/test/goldens` printed nothing, so the existing goldens are byte-identical. The `2 deletions` are the last lines of the two ARB files, which gained a trailing comma.

`make check` before the item 4 commit (last lines):

```
scope: SCOPED gate (91 changed path(s)): docs infra-tests docgen frontend
== frontend composition gate: all checks passed ==
== pre-push gate: all checks passed (scope: docs infra-tests docgen frontend) ==
```

Every commit went through `make check && make commit`. Item 2's first `make check` failed on `dart format` (qd_theme.dart) and item 3's first run failed `flutter analyze` (3 `prefer_const` infos in a test); both were fixed and re-run green before committing.

Local Flutter: `Flutter 3.44.6 • channel stable`, same as `.github/workflows/ci.yml` `flutter-version: '3.44.6'`.

### Contrast (WCAG 2.1, every text/background pair used by components)

Asserted in `test/ui/tokens_test.dart` (≥ 4.5:1 for light and dark).

| Text | Background | Ratio | Use |
|---|---|---|---|
| `#0D1321` | `#FFFFFF` | 18.55 | body text |
| `#0D1321` | `#F9FAFB` | 17.75 | subtle card |
| `#0D1321` | `#F3F4F6` | 16.85 | segmented selected, info banner |
| `#4B5563` | `#FFFFFF` | 7.56 | secondary text |
| `#4B5563` | `#F9FAFB` | 7.23 | secondary on subtle card |
| `#4B5563` | `#F3F4F6` | 6.87 | segmented unselected |
| `#0D1321` | `#FFC107` | 11.38 | primary button |
| `#0D1321` | `#FFF8E1` | 17.46 | selected option |
| `#15803D` | `#DCFCE7` | 4.57 | success chip |
| `#B45309` | `#FEF3C7` | 4.51 | warning chip |
| `#BA1A1A` | `#FEE2E2` | 5.29 | danger chip |
| `#374151` | `#F3F4F6` | 9.37 | neutral chip |
| `#BA1A1A` | `#FFFFFF` | 6.46 | destructive button, field error |
| `#374151` | `#E5E7EB` | 8.33 | disabled primary button |
| `#FFC107` | `#0D1321` | 11.38 | avatar initial |
| `#0D1321` | `#FEF3C7` | 16.66 | warning banner |
| `#0D1321` | `#FEE2E2` | 15.18 | danger banner |
| `#F9FAFB` | `#0D1321` | 17.75 | dark: text |
| `#9CA3AF` | `#161D2E` | 6.62 | dark: secondary on card |
| `#86EFAC` | `#14532D` | 6.49 | dark: success chip |
| `#FCD34D` | `#78350F` | 6.29 | dark: warning chip |
| `#FCA5A5` | `#7F1D1D` | 5.28 | dark: danger chip |
| `#D1D5DB` | `#273047` | 8.91 | dark: neutral chip |

## Data gaps (screen map list vs the API)

Checked against `services/user-service/internal/models/models.go` (`Job`, `Location`, `OwnerJobResponse`, `EmployeeJobResponse`) and `services/auth-service` (user model, `/auth/user`, `/auth/employees`).

| Gap | Verdict | Evidence |
|---|---|---|
| Recipient name / phone | **confirmed gap** | `Job` has no recipient fields; only `user_id` (the booker). |
| ETA | **confirmed gap** | No ETA / duration field and no routing service. Only coordinates (`location`, `destination`, `current_location`) and `booked_distance` (internal `Job` only, not in the owner/employee DTOs), so the client could only guess a straight-line estimate. |
| Text address | **confirmed gap** | `Location` = `latitude`, `longitude`, `address_note` (free-text landmark, ≤ 500 chars). `Service.address` exists but is the business address, not the job's. |
| "Picked up" step | **confirmed gap** | `JobStatus` goes `active` → `completed`; no picked-up status or timestamp. |
| Per-status timestamps | **confirmed gap, partial data** | Only `created_at` (ordered), `updated_at` (last change), `cancellation_requested_at`, `offer_expires_at`, `price_proposal_expires_at`. No accepted/completed/cancelled times; the audit log (`/auth/audit-log`) records account and KYC events only, not job transitions. |
| Courier phone | **confirmed gap (exists, not exposed)** | `User.phone` is stored (auth-service) but only returned to the user themself on `/auth/me`; `/auth/employees` returns id, username, email, is_active, created_at; no job DTO carries courier contact. |
| Courier vehicle | **confirmed gap** | No vehicle field anywhere in the models. |
| Order size (screen map list) | **confirmed gap** | No size / weight field on `Job`. |

## Unverified
- **CI rendering of the new goldens.** They were generated locally (Fedora, Flutter 3.44.6, the CI version) and pass locally, but have not run on the CI runner (ubuntu-latest). Unlike the screen goldens they rasterise a real font. If CI shows small pixel diffs, regenerate them on CI (see follow-up on regen-goldens.yml).
- **Release build exclusion of `/qd-gallery`.** The route is behind `kDebugMode` like `/component-library`; not verified with an actual release build.
- **Device check.** Components were not run on a device or emulator; checked only through widget tests and golden images (all 20 PNGs reviewed by eye for RTL/LTR layout).
- **Mockup provenance.** See the first decision: the zip is assumed to be the approved set.

## Follow-ups / out-of-lane findings
- `.github/workflows/regen-goldens.yml` regenerates only `test/golden_screens_test.dart` and uploads only `frontend/test/goldens/`. To get CI-rendered baselines for the new goldens it should also run `flutter test --update-goldens test/ui/qd_gallery_golden_test.dart` and upload `frontend/test/ui/goldens/` (hot path `.github/**`, not in this lane).
- The OFL license is bundled as an asset but not registered with `LicenseRegistry`, so it does not appear in Flutter's licenses page. A `LicenseRegistry.addLicense` call belongs in `main.dart` app setup, outside this lane (only the gallery route was allowed there). Do it when the new theme is wired.
- `docs/frontend/DESIGN_SYSTEM.md` (old system) should get a pointer to `docs/design/DESIGN_SYSTEM.md` when the screen rebuilds start (out of lane).
- The backend data gaps above are input for JOB-MODEL-V2.

## Open questions
- Confirm the mockups taken from `redesign-a.zip` are the approved set.
- Confirm the chip tones in the mapping table (especially `unavailable` = danger, `completed` = neutral, pending cancellation shown even on terminal statuses).
