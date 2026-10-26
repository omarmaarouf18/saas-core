# Worklog: FE-CLEANUP — redesign A becomes the app; old UI deleted; 2.0.0

## Task and scope
- Task ID: FE-CLEANUP
- Item IDs covered: 0 (inventory), 1 (replace what is still old), 2 (app-wide theme + dark review), 3 (remove the QD_REDESIGN_* flags), 4 (delete the old UI), 5 (version 2.0.0 + split APKs), 6 (docs)
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
