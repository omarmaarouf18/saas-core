# Worklog: FE-CLEANUP — redesign A becomes the app; old UI deleted; 2.0.0

## Task and scope
- Task ID: FE-CLEANUP
- Item IDs covered: 0 (inventory), 1 (replace what is still old), 2 (app-wide theme + dark review), 3 (remove the QD_REDESIGN_* flags), 4 (delete the old UI), 5 (version 2.0.0 + split APKs), 5b (universal legacy APK, owner decision), 6 (docs), 7 (drop unused pubspec deps), 8 (changed-scope SIGPIPE fix + regen-goldens)
- Lane extension (second session, item 8 only): scripts/changed-scope.sh (+ its new test scripts/test_changed_scope.sh) and .github/workflows/regen-goldens.yml; item 7 granted pubspec.yaml / pubspec.lock.
- Allowed paths (lane): frontend/** (including frontend/.github/workflows/build-apk.yml and frontend/docs/**), docs/frontend/**, docs/design/**, docs/worklog/FE-CLEANUP.md. Providers, models and core/api_client.dart are kept (dead code removed only when proven unused).
- Agent branch: agent/FE-CLEANUP-redesign-only-2-0-0, created from logic-exploitation (all FE-* redesign tasks and FE-V2-CONSUME merged)

## Item 0 — inventory of old UI still reachable with all four flags ON

Method: `grep -rn "import .*\(screens\|widgets\|core/theme\|utils/logout\)"` over `lib/features`, `lib/ui`, `lib/core`, `lib/services`, `lib/utils`, `lib/providers`, `lib/models` and `lib/main.dart`, then each hit followed by hand to see whether it sits on a flag-ON path or only in a `legacy:` / `redesign ? … : old` branch. `lib/features/**` and `lib/ui/**` import nothing else from `lib/screens/` or `lib/widgets/` (the `widgets/…` hits under `features/auth/widgets/` and the `*_widgets.dart` files are new code).

Baseline on the branch start: `flutter analyze` → `No issues found! (ran in 5.2s)`; `flutter test` → `01:06 +1831: All tests passed!`.

### Reachable with the flags ON (must be replaced)

| Old code | Reached from | Who opens it |
|---|---|---|
| `screens/notifications_screen.dart` (`NotificationsScreen`, old look, deep links regardless of role) | `features/owner/owner_nav.dart` `openNotifications` → `_old(...)` | Owner: bell on the Today tab (`today_page.dart`). Customer and courier already open the redesigned `NotificationsPage`, but its links are customer-only (`notificationTarget` returns none for other roles), so courier taps do nothing. |
| `widgets/kyc_rejection_dialog_host.dart` + `widgets/info_alert_dialog.dart` (old AlertDialog) | `main.dart` `MaterialApp.builder` | Every signed-in user; fires when a `kyc_rejected` SSE notification for that user arrives (owner KYB, courier KYE). |
| `AuthSplashScreen` in `main.dart` (old tokens from `core/theme.dart`, `widgets/themed_panel.dart`) | `RedesignAuthGate(splash: AuthSplashScreen())` in `main.dart` `AuthGate` | Everyone, on every launch while the stored session is restored. |
| `features/auth/update_required_page.dart` — redesigned already, but its button only copies the link | `RedesignUpdateGate` (HTTP 426, ADR-0018) | Anyone whose build is below the server minimum. |
| `core/theme.dart` (`quickDeliveryTheme` / `quickDeliveryDarkTheme`) | `main.dart` `MaterialApp.theme` / `darkTheme` | Everything not wrapped in `QdThemeScope` / `CustomerTheme`: the splash, the KYC dialog, root-level dialogs and snackbars, the HomeScreen router frame. |
| `screens/home_screen.dart` (`HomeScreen`) | `RedesignAuthGate` and `AuthNav.goHome` | Everyone signed in: used only as the role router (`build` → the three shells), but it still runs `_refreshData` (`fetchUserProfile`) and carries the whole old owner dashboard. |
| `HomeScreen._buildNonOwnerShell` (old `AppShell` + `SettingsScreen` + `NotificationsScreen`) | `HomeScreen.build` when the role is none of `owner` / `employee` / `user` | Any other role that signs in to the mobile app (admin, reviewer, support agent); not a supported mobile role. |
| `screens/component_library_screen.dart` | `main.dart` debug route `/component-library` | Debug builds only (task: delete). |
| `utils/logout_helper.dart` (`redesign` parameter defaulting to `kRedesignAuth`) | `features/account/account_nav.dart` `signOut` | Every role's sign out; with the flag ON it lands on the new `LoginPage` (correct), but the flag branch must go. |

### Only on flag-OFF paths (dead once the flags go)

| Old code | Legacy branch |
|---|---|
| `screens/login_screen.dart` | `main.dart` `AuthGate` (flag off), `auth_nav.dart` `signedOutRootScreen(redesign: false)` |
| `screens/customer_home_screen.dart` (and everything it opens) | `customer_shell.dart` `customerRootScreen(redesign: false)` |
| `screens/employee_home_screen.dart` (and everything it opens) | `home_screen.dart` → `courierRootScreen(legacy: …)` |
| `HomeScreen._buildOwnerShell` (EmployeeScreen, OwnerHistoryScreen, SettingsScreen, WalletScreen, SubscriptionScreen, KycDocumentUploadScreen, OwnerReconciliationQueueScreen, OwnerFleetMapScreen, OwnerConfigurationScreen, …) | `ownerRootScreen(legacy: …)`, `runLegacyOwnerDashboardFetch()` |
| `core/update_gate.dart` → `screens/update_required_screen.dart` | `main.dart` `onUpdateRequired` when `kRedesignAuth` is off |
| Every other file in `lib/screens/` and `lib/widgets/` | Reached only from the files above |

`lib/services/push_notification_service.dart` opens no screen (FCM token registration only).

## Items status
- 0 inventory — done (above).
- 1 replace what is still old — done: one NotificationsPage for every role with role-checked links (customer → My orders / tickets; owner → order detail by job id from the body, else Orders; team for `employee_*`, plan for `subscription_*` (no backend type emits these yet), verification for `kyc_*`; courier → Task tab for `job_offer` / `job_alert` / declined cancellation, My jobs for approved cancellation / dispute, verification); VerificationRejectedHost (redesigned dialog, same SSE trigger, button to the verification page); LaunchSplash; update page "Download the update" opens the link (url_launcher via openOrCopy), copies it as fallback; UnsupportedRolePage for staff roles (was the old generic dashboard).
- 2 app-wide theme — done: MaterialApp theme/darkTheme = qdLightTheme/qdDarkTheme; QdThemeScope, CustomerTheme, customerRoute removed (qdPageRoute → MaterialPageRoute). Dark review: 6 new dark goldens; WCAG matrix of all tokens computed; no text/background pair used by the pages is below 4.5:1. Failing combinations exist only unused (dark textSecondary on warningBg 3.57, dangerBg 3.95, successBg 3.59; light textMuted on fills ~4.0–4.4) — not fixed because nothing renders them; new used pairs added to test/ui/tokens_test.dart.
- 3 flags removed — done: core/feature_flags.dart, core/update_gate.dart deleted; RoleHome (role → shell, profile refresh on open) replaces HomeScreen routing; AuthGate / UpdateGate renamed from Redesign*; flag tests became routing tests (test/features/auth/role_home_test.dart, auth_gate_test.dart).
- 4 old UI deleted — done: 72 lib files, 29839 lines (all lib/screens 33 files incl. ComponentLibraryScreen + route, all lib/widgets 37 files, core/theme.dart, utils/logout_helper.dart); 59 test files 21808 lines (+609 old-screen test cases removed from 13 mixed files, provider/model cases kept); 63 PNGs in test/goldens; 801 unused ARB keys (EN+AR); 5 Poppins TTFs (780 KB) and the GoogleFonts switch; docs/frontend/DESIGN_SYSTEM.md (old system, 312 lines) → pointer. /qd-gallery kept.
- 5 version and APK — done: pubspec 2.0.0+1; lib/core/app_version.dart (`APP_VERSION` dart-define, default 2.0.0) now feeds X-App-Version (it was hard-coded `1.0.0+1` in ApiClient); build-apk.yml pinned to Flutter 3.44.6, `--split-per-abi`, `--build-number=${{ github.run_number }}`, uploads the 3 ABI APKs plus `app-release.apk` (copy of arm64-v8a, so `releases/latest/download/app-release.apk` — the gateway default download_url and the in-app fallback — keeps working); app-release.json keeps `apk_url` (arm64-v8a), adds `apk_urls`, `full_version`, `build_number`; website step and `logiclink` unchanged.
- 5b universal APK — done (owner decision: `apk_url` stays arm64-v8a; the legacy `app-release.apk` must install on any phone): build-apk.yml first runs a plain `flutter build apk --release` (universal, kept as build/universal/app-release.apk), then the `--split-per-abi` build; the release uploads the 3 ABI APKs + the universal `app-release.apk`; app-release.json `apk_urls` gains `universal`. Version codes: universal = build number, split = ABI offset + build number (arm64 2000+n), so a phone with a split APK cannot then install the universal APK of the same run (documented in CI_CD.md).
- 6 docs — done: docs/frontend/STATUS.md (2.0.0 banner; file index without screens/widgets/theme/logout_helper, with core/app_version.dart and lib/ui; features table without flags, incl. courier and verification rows; three gap bullets about deleted code removed, one 2.0.0 gaps bullet added; old phase entries kept as marked history), 00-SCREEN-MAP status column (29 rows: "in the app (2.0.0)", action simulator "removed", wallet + plan "in the app, read-only"; first column header "old screen, removed in 2.0.0"), docs/design/DESIGN_SYSTEM.md (theme app-wide, dark wired, contrast note, golden paths), frontend/docs/CI_CD.md (pinned Flutter, version/build number, universal + split APKs, app-release.json shape, version codes, downloads), frontend/README.md (golden paths, release build, manual split build, design system section), CONNECTING_TO_BACKEND.md (flag dart-define removed).
- 7 unused deps — done: google_fonts and flutter_svg removed from pubspec.yaml; pubspec.lock drops them plus path_parsing, petitparser, vector_graphics, vector_graphics_codec, vector_graphics_compiler, xml. Proof (literal):
  ```
  $ grep -rn "google_fonts\|GoogleFonts\|flutter_svg\|SvgPicture" lib test linux android ios macos windows web
  test/ui/tokens_test.dart:130:        expect(f.readAsStringSync(), isNot(contains('google_fonts')),
  (end)
  ```
  (the one hit is a negative assertion). assets/branding/qd_logo.svg stays declared (only the old OTP screen showed it).
- 8 gate tooling — done: changed-scope.sh prints the first 20 paths with `sed -n '1,20s/^/scope:   /p'` (reads all input) instead of `head -n 20` (closed the pipe early → SIGPIPE → exit 141 under pipefail). scripts/test_changed_scope.sh feeds 1500 paths (~180 KB listing) through `--paths`: before the fix `FAIL exit 0 with 1500 paths: exit 141` (4 checks failed), after `all changed-scope checks passed`. regen-goldens.yml: the deleted test/golden_screens_test.dart step and the frontend/test/goldens/ upload are gone; one step `flutter test --update-goldens test/ui/ test/features/` and one artifact `ci-rendered-goldens` (test/ui/goldens/ + test/features/**/goldens/). Same command run locally: `00:27 +996: All tests passed!`, no PNG changed.

## Changes per commit (message only — NO SHAs)
1. `FE-CLEANUP: item 0 - inventory of old UI reachable with the flags on`
2. `FE-CLEANUP: item 1 - notifications for every role, new rejection dialog, splash and update download`
3. `FE-CLEANUP: drop golden failure images committed by mistake; ignore them`
4. `FE-CLEANUP: item 2 - redesign theme app-wide, theme wrappers removed, dark review goldens`
5. `FE-CLEANUP: item 3 - remove the QD_REDESIGN flags; RoleHome routes to the new shells`
6. `FE-CLEANUP: item 4 - delete the old UI, its tests, goldens and ARB keys`
7. `FE-CLEANUP: item 5 - version 2.0.0, real X-App-Version, split-per-ABI release APKs`
8. `FE-CLEANUP: worklog`
9. `FE-CLEANUP: item 5b - legacy app-release.apk is a universal APK (owner decision)`
10. `FE-CLEANUP: item 6 - docs for 2.0.0 (status, screen map, design system, CI/CD, README)`
11. `FE-CLEANUP: item 7 - drop unused google_fonts and flutter_svg`
12. `FE-CLEANUP: item 8 - changed-scope SIGPIPE fix with a 1500-path test; regen-goldens covers test/ui and test/features only`
13. `FE-CLEANUP: worklog` (this update)

## Verification (literal lines)
- item 1: `No issues found! (ran in 1.2s)`; `01:12 +1847: All tests passed!`; `== pre-push gate: all checks passed (scope: docs infra-tests docgen frontend) ==`
- item 2: `No issues found! (ran in 1.1s)`; `01:39 +1852: All tests passed!`
- item 3: `No issues found! (ran in 1.1s)`; `01:04 +1834: All tests passed!`
- item 4: `No issues found! (ran in 1.0s)`; `00:35 +1219: All tests passed!`; make ci-full `== pre-push gate: all checks passed (scope: full) ==`
- item 5: make ci-full `No issues found! (ran in 2.5s)`, `00:37 +1221: All tests passed!`, `== pre-push gate: all checks passed (scope: full) ==`
- api-gateway (read-only run): `ok  	github.com/project/gateway/internal/version	0.048s`, `ok  	github.com/project/gateway/internal/middleware	0.003s` — ParseSemVer strips `+build`, so 2.0.0+N passes and 1.0.0+1 keeps working while the minimum is 1.0.0.
- `flutter build apk --release --split-per-abi --build-number=1 --dart-define=APP_VERSION=2.0.0+1`:
  `✓ Built build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk (18.8MB)`
  `✓ Built build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (21.1MB)`
  `✓ Built build/app/outputs/flutter-apk/app-x86_64-release.apk (22.6MB)`
  aapt2: `versionCode='2001' versionName='2.0.0'` (arm64; ABI offset + build number). Before: one 62 MB APK (task prompt figure, not re-measured).

- item 5b: make ci-full `No issues found! (ran in 2.5s)`, `00:34 +1221: All tests passed!`; local universal + split build:
  `✓ Built build/app/outputs/flutter-apk/app-release.apk (59.7MB)` (aapt2: `versionCode='1' versionName='2.0.0'`, `native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'`)
  `✓ Built build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk (18.8MB)`
  `✓ Built build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (21.1MB)`
  `✓ Built build/app/outputs/flutter-apk/app-x86_64-release.apk (22.6MB)`
- item 6: make ci-full `== pre-push gate: all checks passed (scope: full) ==`
- item 7: `No issues found! (ran in 3.2s)`; `00:31 +1221: All tests passed!`; make ci-full passed
- item 8: make check (full scope, now runs without SIGPIPE) `No issues found! (ran in 1.5s)`, `00:31 +1221: All tests passed!`

## Goldens
- Changed: test/features/auth/goldens/auth_update_{ar_rtl,en_ltr}_360x800.png (download + copy buttons).
- New: cour_idle_dark_en_ltr, cour_active_deliver_dark_en_ltr, cust_home_dark_en_ltr, ord_active_dark_en_ltr, own_shell_dark_en_ltr, own_order_dark_en_ltr (360x800).
- Deleted: all 63 PNGs in test/goldens/ (old screens). No other feature golden changed under the app-wide theme.

## Manual test plan (owner)
- Customer: launch → new splash → sign in → shell; bell → notifications; tap an order notification → My orders; dark mode toggle on sign-in page → whole app dark.
- Owner: Today bell → new notifications page; cancellation-request notification → that order's detail; KYB rejection while online → new dialog → "Fix my documents" opens verification.
- Courier: offer notification → Task tab; approved cancellation → My jobs; KYE rejection dialog.
- Any: server minimum above 2.0.0 → update page; "Download the update" opens the browser; staff account → unsupported-role page with sign out.

## Unverified
- No device/emulator run; all checks are widget tests, goldens and the local release build.
- build-apk.yml not run on GitHub (validated by YAML parse and test/core/app_version_test.dart only).
- New dark goldens not yet rendered on CI.

## Follow-ups / out-of-lane findings
- The SIGPIPE in changed-scope.sh (fixed in item 8) made `make check` / `make commit` fail on this branch; items 4–7 went through `make ci-full`. scripts/test_changed_scope.sh is not wired into the gate (pre-push / Makefile are hot paths outside the item 8 extension).
- .github/workflows/ci.yml line ~225 comment still mentions frontend/test/goldens/ (outside the item 8 extension).
- Root DESIGN.md still says Poppins; assets/branding/qd_logo.svg is still declared but unused.
- Other old docs (docs/frontend/ARCHITECTURE.md, UI/UX audits) describe the deleted screens; only STATUS.md was in scope.
- Owner/courier notification bodies are English server text (titles are localized); a job_id in the notification payload would replace body parsing.

## Open questions
- none (both earlier questions answered by the owner: universal legacy APK, keep the team / plan links).
