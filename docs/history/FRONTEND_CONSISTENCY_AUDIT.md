# Frontend Consistency Audit & Remediation Plan

> **Date**: August 16, 2026  
> **Status**: COMPLETED & 100% IMPLEMENTED (All 5 Remediation Batches Landed & Verified)  
> **Scope**: All 28 screens (`frontend/lib/screens/`) and all 20 reusable widgets (`frontend/lib/widgets/`) against design tokens in `frontend/lib/core/theme.dart`.

---

## 1. Executive Summary

A comprehensive, line-by-line audit of the entire Flutter frontend application was conducted to identify usages of raw Material components, un-tokenized styling, pattern divergences, missing tap-debounce safeguards, or dialog sizing risks. All 48 catalogued findings across 25 target files were fully resolved across 5 implementation batches (Batches 1–5), verified via 267/267 passing Flutter tests and clean `flutter analyze`.

### Implementation & Verification Status

*   **Batch 1: Shared Widgets & Foundation Hardening** — **[VERIFIED]** (Commit `4f4623c`, 216/216 tests pass)
*   **Batch 2: High-Traffic Customer & Auth Experience** — **[VERIFIED]** (Commit `0742970`, 223/223 tests pass)
*   **Batch 3: Settings, Account & Notifications Center** — **[VERIFIED]** (Commit `6b5be11`, 234/234 tests pass)
*   **Batch 4: Owner Operations & Service Management** — **[VERIFIED]** (Commit `8c864e4`, 254/254 tests pass)
*   **Batch 5: Real-Time Communication, Map Tracking & Job Details** — **[VERIFIED]** (Commit `b65b8a1`, 267/267 tests pass)

### Summary Metrics

*   **Total Screens Audited**: 28
*   **Total Reusable Widgets Audited**: 20
*   **Initial Compliant Screens/Widgets**: 23
*   **Screens/Widgets Remediated**: 25
*   **Total Inconsistency Findings Catalogued & Resolved**: 48 (100% remediated)

### Findings Breakdown by Category

| Category | Finding Count | Description & Risk Profile |
| :--- | :---: | :--- |
| **`raw-widget-usage`** | 16 | Usages of raw `ElevatedButton`, `OutlinedButton`, `TextButton`, `TextField`, `CircularProgressIndicator`, or raw `SnackBar` where standardized design system equivalents exist (`PrimaryButton`, `SecondaryButton`, `ThemedTextField`, `ThemedLoadingIndicator`, `ThemedSnackBar`). |
| **`hardcoded-values`** | 15 | Hardcoded font sizes (`fontSize: 10/12/13/18`), custom `TextStyle` definitions, un-tokenized spacing or border radii instead of canonical `AppTypography`, `AppSpacing`, `AppRadius`, and `AppColors` design tokens. |
| **`pattern-divergence`** | 9 | Hand-rolled dialogs (`showDialog(builder: (ctx) => AlertDialog(...))`), bespoke modal layouts, or divergent styling for conceptually identical flows (e.g. action confirmations, booking modals, service creation, and cash operations). |
| **`missing-debounce-protection`** | 6 | Interactive `GestureDetector`, `InkWell`, or raw text button actions that trigger async network calls (e.g., OTP resend, email change requests, map confirm) without benefiting from `PrimaryButton`/`SecondaryButton`'s 600ms tap-debounce safeguard (`AppMotion.debounceGuard`), creating duplicate-request or 429 rate-limit risks. |
| **`dialog-sizing-risk`** | 2 | Handcrafted dialogs using fixed dimensions or legacy bounds that risk viewport overflow on small mobile displays (< 360dp width). |

---

## 2. Design System Inventory & Compliance Standard (Step 1 Checklist)

This inventory establishes the authoritative checklist for what constitutes correct design system compliance.

### A. Design Tokens (`frontend/lib/core/theme.dart`)

1.  **`AppColors` (Palette & Contrast Roles)**:
    *   *Brand Accents*: `primary` (`#0D1321` Deep Navy), `secondary` (`#FFC107` Amber Gold), `scaffoldBackground` (`#E5E7EB`), `surface` (`#FFFFFF`).
    *   *On-Colors*: `onPrimary` (`#FFFFFF`), `onSecondary` (`#0D1321`), `onSurface` (`#1A1C1C`), `onSurfaceVariant` (`#45464C`).
    *   *Surface Containers*: `surfaceContainerLowest` (`#FFFFFF`), `surfaceContainerLow` (`#F3F3F4`), `surfaceContainer` (`#EEEEEE`), `surfaceContainerHigh` (`#E8E8E8`), `surfaceContainerHighest` (`#E2E2E2`), `surfaceDim` (`#DADADA`).
    *   *WCAG AA Status Accents*: `success` (`#15803D` Dark Green, 5.02:1), `error` / `danger` (`#BA1A1A` Dark Red, 10.1:1), `warning` (`#B45309` Amber-700, 5.02:1).
    *   *Outlines*: `outline` (`#57585E`), `outlineVariant` (`#8E8F95`).
2.  **`AppTypography` (Poppins Type Scale)**:
    *   `displayLg` (48pt bold, line-height 56/48) — Hero stat numbers & splash titles.
    *   `headlineLg` (32pt w600, line-height 40/32) — Primary screen titles (desktop/tablet).
    *   `headlineLgMobile` (24pt w600, line-height 32/24) — Primary screen titles (mobile).
    *   `titleMd` (18pt w600, line-height 24/18) — Section headers, card titles, dialog titles.
    *   `bodyLg` (16pt regular, line-height 24/16) — Prominent body text, lead paragraphs.
    *   `bodyMd` (14pt regular, line-height 20/14) — Standard body text, form inputs.
    *   `bodySm` (13pt regular, line-height 18/13) — Secondary descriptions, captions.
    *   `labelLg` (12pt w600, letter-spacing +5%) — Input labels, button titles, pill badges.
    *   `labelMd` (11pt w500, line-height 14/11) — Metadata timestamps, status badges, chips.
3.  **`AppSpacing` (8pt Standard Grid)**:
    *   `xxs` (2.0), `xs` (4.0), `base` (8.0), `baseSm` (10.0), `sm` (12.0), `md` (16.0), `lg` (24.0), `xl` (32.0), `xxl` (40.0), `xxxl` (100.0), `gutter` (16.0), `marginMobile` (16.0), `marginDesktop` (48.0).
4.  **`AppRadius` (Curvature Scale)**:
    *   `xxs` (3.0), `xs` (2.0), `sm` (4.0), `defaultValue` (8.0), `smMd` (10.0), `md` (12.0), `lg` (16.0), `lgXl` (20.0), `xl` (24.0), `full` (9999.0).
    *   Getters: `xxsBorder`, `xsBorder`, `smBorder`, `defaultBorder`, `smMdBorder`, `mdBorder`, `lgBorder`, `lgXlBorder`, `xlBorder`, `fullBorder`.
5.  **`AppElevation` (Shadow System)**:
    *   `level0` (0.0 flat), `level1` (1.0 resting cards), `level2` (3.0 interactive cards/menus), `level3` (6.0 bottom sheets/snackbars), `level4` (12.0 modal dialogs).
    *   Presets: `shadowLevel1List`, `shadowLevel2List`, `shadowLevel3List`, `shadowLevel4List`.
6.  **`AppMotion` (Durations, Curves & Logic Guards)**:
    *   Durations: `durationFast` (150ms), `durationMedium` (300ms), `durationMediumSlow` (400ms), `durationSlow` (500ms), `snackBarDisplay` (2s).
    *   Curves: `curveEntrance` (`easeOutCubic`), `curveExit` (`easeInCubic`), `curveStateChange` (`easeInOut`), `curveBounce` (`elasticOut`).
    *   Guards: `debounceGuard` (600ms button tap double-submit threshold).
7.  **`AppIconSize` (Iconography Scale)**:
    *   `xs` (14.0), `sm` (16.0), `md` (24.0), `lg` (32.0), `xl` (48.0).

### B. Standard Themed Component Library (`frontend/lib/widgets/`)

| Component | Standard Usage & Capabilities |
| :--- | :--- |
| **`PrimaryButton`** | Primary filled action button with built-in 600ms tap-debounce guard (`AppMotion.debounceGuard`), micro-interaction scale feedback (`0.96`), `isLoading` spinner state, `isDestructive` state, and in-row compact (`isFullWidth: false`) or full-width sizing. |
| **`SecondaryButton`** | Secondary outlined (`isOutlined: true`) or tinted action button with 600ms tap-debounce guard, micro-scale feedback, `isLoading`, `isDestructive`, and compact sizing. |
| **`ThemedCard`** | Container card with tokenized padding (`AppSpacing.md`), radius (`AppRadius.defaultValue`), border colors (`AppColors.outlineVariant`), and variant elevations (`ThemedCardVariant.normal`, `highlighted`, `elevated`). |
| **`ThemedTextField`** | Standardized input field with floating/top labels, tokenized borders (`AppRadius.defaultBorder`), focused/error states, and interactive password visibility toggling (`isPasswordField: true`). |
| **`ThemedLoadingIndicator`** | Standardized center loading indicator with brand color (`AppColors.primary`) and optional message. |
| **`ThemedErrorBanner` / `ThemedBanner`** | Standardized inline alert banner for error, warning, success, and info states with icon, message, optional dismiss, and retry action. |
| **`ThemedSuccessBanner` / `ThemedSnackBar`** | Reusable success banners and floating standardized SnackBars (`ThemedSnackBar.showSuccess`, `showError`, `showWarning`, `showInfo`) with 2s timeout and icons. |
| **`ThemedEmptyState`** | Standardized zero-data placeholder with graphic icon (`AppIconSize.xl`), bold title, subtitle, and optional secondary action button. |
| **`ThemedSectionHeader`** | Section title and subtitle header with optional trailing widget. |
| **`StatusBadge`** | Status pill badge supporting job, KYC, worker, and payout statuses with icon, color-mapping, and compact/standard variants. |
| **`ConfirmActionDialog`** | Reusable modal dialog (`ConfirmActionDialog.show`) with title, message, icon, confirm label, cancel label, and destructive mode. |
| **`CancelJobDialog`** | Standardized job cancellation dialog (`CancelJobDialog.show`) with mandatory reason input and double-submit prevention. |
| **`LocationPickerMap`** | Reusable interactive OpenStreetMap picker dialog widget. |
| **`SkeletonLoader`** | Shimmer skeleton loader primitive and screen card skeletons (`MarketplaceCardSkeleton`, `HomeDashboardSkeleton`, `EmployeeJobCardSkeleton`, `WalletScreenSkeleton`). |

---

## 3. Comprehensive Finding-by-Finding Catalog

### Batch A: High-Visibility Customer & Auth Screens

#### 1. `customer_marketplace_screen.dart`
*   **Finding 1.1** [`raw-widget-usage`]: Lines 203–225 — Uses raw `OutlinedButton.icon` with manual `OutlinedButton.styleFrom` for "Choose Location on Map" instead of `SecondaryButton(isOutlined: true, icon: Icons.map_outlined, isFullWidth: false)`.
    *   *Remediation*: Replace with `SecondaryButton(isOutlined: true, icon: Icons.map_outlined, isFullWidth: false, text: l10n.customerMarketplaceChooseMap, onPressed: ...)`.
    *   *Effort*: Trivial single-widget swap.
*   **Finding 1.2** [`hardcoded-values`]: Lines 578–582 — Handcrafted `TextStyle(fontSize: 18, fontWeight: FontWeight.bold)` inside location picker dialog title.
    *   *Remediation*: Replace with `AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold)`.
    *   *Effort*: Trivial token replacement.
*   **Finding 1.3** [`pattern-divergence`]: Lines 641–850 — `_BookingDialog` is hand-rolled inside the screen with custom `AlertDialog`, raw warning box, and inline layout instead of a dedicated reusable dialog component.
    *   *Remediation*: Extract into `frontend/lib/widgets/booking_confirmation_dialog.dart`, use `ThemedWarningBanner` for deferred escrow notice, and wire with `PrimaryButton` and `SecondaryButton`.
    *   *Effort*: Moderate refactor.
*   **Finding 1.4** [`hardcoded-values`]: Line 467 — `fontSize: 12` hardcoded in category chip label.
    *   *Remediation*: Replace with `AppTypography.labelLg`.
    *   *Effort*: Trivial token replacement.

#### 2. `customer_home_screen.dart`
*   **Finding 2.1** [`hardcoded-values`]: Line 128 — `fontSize: 10` inside `AppTypography.labelMd.copyWith(fontSize: 10)` on unread notification badge.
    *   *Remediation*: Replace with `AppTypography.labelMd` (11pt) or define canonical compact badge token `AppTypography.labelXs` (10pt).
    *   *Effort*: Trivial token replacement.
*   **Finding 2.2** [`raw-widget-usage`]: Line 364 — Raw `TextButton.icon` used for "Browse All" header action instead of standard link / `SecondaryButton`.
    *   *Remediation*: Apply `AppTypography.labelLg.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)` with standard touch target.
    *   *Effort*: Trivial single-widget swap.
*   **Finding 2.3** [`missing-debounce-protection`]: Lines 501–525 — Raw `InkWell` on service category quick-access cards (`_buildCategoryTile`) triggers tab navigation without debounce guard.
    *   *Remediation*: Ensure tab switching handles multiple rapid taps idempotently without animation stutter.
    *   *Effort*: Trivial.

#### 3. `customer_jobs_screen.dart`
*   **Finding 3.1** [`raw-widget-usage`]: Lines 73–78 — Raw `ElevatedButton.icon` used for "Retry" action below `ThemedErrorBanner`.
    *   *Remediation*: Remove redundant button since `ThemedErrorBanner` provides native `onRetry: _loadCustomerJobs`, or swap to `PrimaryButton(text: l10n.retry, icon: Icons.refresh, isFullWidth: false)`.
    *   *Effort*: Trivial single-widget swap.
*   **Finding 3.2** [`hardcoded-values`]: Lines 160 & 199 — `fontSize: 12` inside `AppTypography.bodyMd.copyWith(fontSize: 12)` for payment method and cancellation reason.
    *   *Remediation*: Replace with `AppTypography.labelLg` or `AppTypography.bodySm`.
    *   *Effort*: Trivial token replacement.
*   **Finding 3.3** [`hardcoded-values`]: Line 180 — `padding: const EdgeInsets.all(AppSpacing.xs + 2)` arithmetic instead of `AppSpacing.base` or `AppSpacing.sm`.
    *   *Remediation*: Replace with `const EdgeInsets.all(AppSpacing.sm)`.
    *   *Effort*: Trivial token replacement.

#### 4. `login_screen.dart`
*   **Finding 4.1** [`hardcoded-values`]: Lines 114–119 — Handcrafted `TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.onPrimary, letterSpacing: 1.0)` in QD logo wordmark.
    *   *Remediation*: Replace with `AppTypography.titleMd.copyWith(fontWeight: FontWeight.w800, color: AppColors.onPrimary, letterSpacing: 1.0)`.
    *   *Effort*: Trivial token replacement.
*   **Finding 4.2** [`raw-widget-usage` & `missing-debounce-protection`]: Lines 207 & 232 — Raw `TextButton` used for "Forgot Password?" and "Sign Up" navigation links.
    *   *Remediation*: Style with `AppTypography.bodyMd.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)` with tap-debounce protection to prevent double route pushes.
    *   *Effort*: Trivial.

#### 5. `signup_screen.dart`
*   **Finding 5.1** [`raw-widget-usage`]: Line 247 — Raw `TextButton` for "Already have an account? Sign in".
    *   *Remediation*: Align with `LoginScreen` link typography and tokenized touch target.
    *   *Effort*: Trivial.

#### 6. `otp_screen.dart`
*   **Finding 6.1** [`raw-widget-usage` & `missing-debounce-protection`]: Line 204 — Raw `TextButton` for `_resendCode` triggers async network request without `PrimaryButton`/`SecondaryButton` debounce protection, risking duplicate SMS/email OTP dispatches and 429 rate limit triggers.
    *   *Remediation*: Replace with `SecondaryButton(text: l10n.otpResendButton, icon: Icons.refresh, isLoading: auth.isLoading, isOutlined: true, onPressed: _resendCode)`.
    *   *Effort*: Trivial single-widget swap.

---

### Batch B: Settings, Profile & Notification Centers

#### 7. `settings_screen.dart`
*   **Finding 7.1** [`hardcoded-values`]: Lines 21–45 — Handcrafted `_segmentedButtonStyle` with raw `fontSize: 12`, raw hex colors (`Color(0xFF1E293B)`, `Color(0xFF0F172A)`), bypassing `quickDeliveryTheme.segmentedButtonTheme` defined in `theme.dart`.
    *   *Remediation*: Remove bespoke `_segmentedButtonStyle` helper and inherit canonical `SegmentedButtonThemeData` from `Theme.of(context)`.
    *   *Effort*: Trivial cleanup.
*   **Finding 7.2** [`hardcoded-values`]: Lines 118, 134, 149, 164, 187, 203, 218, 229 — Multiple raw `TextStyle(fontSize: 14/12, fontWeight: ...)` instances on settings section labels and language/theme button segments.
    *   *Remediation*: Replace with `AppTypography.titleMd`, `AppTypography.labelLg`, and `AppTypography.bodyMd`.
    *   *Effort*: Trivial token replacement.
*   **Finding 7.3** [`raw-widget-usage`]: Lines 378–399 — Raw `ElevatedButton.icon` with manual `styleFrom` used for Logout button instead of `PrimaryButton(text: l10n.settingsLogout, icon: Icons.logout, isDestructive: true, ...)`.
    *   *Remediation*: Replace with `PrimaryButton(text: l10n.settingsLogout, icon: Icons.logout, isDestructive: true, onPressed: () => logoutAndClearProviders(context))`.
    *   *Effort*: Trivial single-widget swap.

#### 8. `my_account_screen.dart`
*   **Finding 8.1** [`raw-widget-usage`]: Lines 208–219 — Raw `OutlinedButton.icon` with custom `styleFrom` for "Change Email" button.
    *   *Remediation*: Replace with `SecondaryButton(text: l10n.changeEmailButton, icon: Icons.email_outlined, isOutlined: true, isFullWidth: false, onPressed: ...)`.
    *   *Effort*: Trivial single-widget swap.
*   **Finding 8.2** [`raw-widget-usage`]: Lines 274–281 — Raw `ElevatedButton` for "+ Add Address" button.
    *   *Remediation*: Replace with `PrimaryButton(text: l10n.add, isFullWidth: false, onPressed: _addAddress)`.
    *   *Effort*: Trivial single-widget swap.
*   **Finding 8.3** [`pattern-divergence`]: Lines 359–570 — `EmailChangeDialog` is defined as a large, hand-rolled multi-step `Dialog` within the screen file.
    *   *Remediation*: Extract `EmailChangeDialog` into `frontend/lib/widgets/email_change_dialog.dart` with standard `Dialog` layout, using `ThemedTextField`, `ThemedErrorBanner`, `ThemedSuccessBanner`, and `PrimaryButton`.
    *   *Effort*: Moderate refactor.

#### 9. `notifications_screen.dart`
*   **Finding 9.1** [`pattern-divergence` & `raw-widget-usage`]: Lines 88–124 — Hand-rolled `AlertDialog` with raw `TextButton` and `ElevatedButton` for clearing all notifications.
    *   *Remediation*: Replace with `ConfirmActionDialog.show(context, title: l10n.notificationsClear, message: ..., confirmLabel: l10n.notificationsClear, isDestructive: true)`.
    *   *Effort*: Trivial refactor.

---

### Batch C: Owner Operations & Service Management

#### 10. `wallet_screen.dart`
*   **Finding 10.1** [`hardcoded-values`]: Line 385 — `fontSize: 10` hardcoded inside `AppTypography.labelMd.copyWith(fontSize: 10)` in transaction ledger job chip.
    *   *Remediation*: Replace with `AppTypography.labelMd` (11pt).
    *   *Effort*: Trivial token replacement.
*   **Finding 10.2** [`pattern-divergence`]: Lines 419–610 — `_showPayoutRequestDialog` is a large (200-line) hand-rolled `AlertDialog` embedded directly in `wallet_screen.dart`.
    *   *Remediation*: Extract into `frontend/lib/widgets/payout_request_dialog.dart` using `ThemedCard`, `ThemedTextField`, `SegmentedButton`, and `PrimaryButton`.
    *   *Effort*: Moderate refactor.
*   **Finding 10.3** [`pattern-divergence`]: Lines 700–790 — `_showDepositDialog` is a hand-rolled `AlertDialog` embedded directly in `wallet_screen.dart`.
    *   *Remediation*: Extract into `frontend/lib/widgets/deposit_funds_dialog.dart` using `ThemedTextField`, `ThemedWarningBanner`, and `PrimaryButton`.
    *   *Effort*: Moderate refactor.

#### 11. `owner_configuration_screen.dart`
*   **Finding 11.1** [`hardcoded-values`]: Lines 168–171 — `TextStyle(fontSize: 18, fontWeight: FontWeight.bold)` inside map dialog header.
    *   *Remediation*: Replace with `AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold)`.
    *   *Effort*: Trivial token replacement.
*   **Finding 11.2** [`raw-widget-usage`]: Lines 454–469 — Raw `OutlinedButton.icon` for location picker.
    *   *Remediation*: Replace with `SecondaryButton(text: l10n.customerMarketplaceChooseMap, icon: Icons.map_outlined, isOutlined: true, isFullWidth: false, onPressed: ...)`.
    *   *Effort*: Trivial single-widget swap.
*   **Finding 11.3** [`raw-widget-usage`]: Lines 622–637 — Raw `OutlinedButton.icon` for image picker.
    *   *Remediation*: Replace with `SecondaryButton(text: l10n.tooltipPickImage, icon: Icons.upload_file_outlined, isOutlined: true, isFullWidth: false, onPressed: ...)`.
    *   *Effort*: Trivial single-widget swap.

#### 12. `service_screen.dart`
*   **Finding 12.1** [`pattern-divergence`]: Lines 231–430 — `Create New Service` dialog is a monolithic (200-line) handrolled `AlertDialog` embedded in the screen.
    *   *Remediation*: Extract into `frontend/lib/widgets/create_service_dialog.dart` using `ThemedTextField`, `ThemedCard`, `PrimaryButton`, and `SecondaryButton`.
    *   *Effort*: Moderate refactor.

#### 13. `employee_screen.dart`
*   **Finding 13.1** [`raw-widget-usage`]: Line 223 — Raw `CircleAvatar` used for worker initials avatar instead of `EntityAvatar`.
    *   *Remediation*: Replace with `EntityAvatar(name: username, radius: 20)`.
    *   *Effort*: Trivial single-widget swap.
*   **Finding 13.2** [`hardcoded-values`]: Lines 229, 249, 635 — Raw `TextStyle(color: AppColors.onPrimary)` and `fontSize: 12` on worker email and IP address tags.
    *   *Remediation*: Replace with `AppTypography.labelLg` and `AppTypography.labelMd`.
    *   *Effort*: Trivial token replacement.
*   **Finding 13.3** [`pattern-divergence` & `raw-widget-usage`]: Lines 648–662 — `_showSuccessDialog` uses hand-rolled `AlertDialog` with raw `TextButton` instead of `ThemedSnackBar.showSuccess`.
    *   *Remediation*: Replace with `ThemedSnackBar.showSuccess(context, message)`.
    *   *Effort*: Trivial refactor.

#### 14. `owner_reconciliation_queue_screen.dart`
*   **Finding 14.1** [`raw-widget-usage`]: Lines 127–130 — Raw `ElevatedButton` for error retry state instead of `ThemedErrorBanner(message: provider.error!, onRetry: () => provider.fetchQueue())`.
    *   *Remediation*: Replace with `ThemedErrorBanner(message: provider.error!, onRetry: () => provider.fetchQueue())`.
    *   *Effort*: Trivial single-widget swap.

---

### Batch D: Real-Time Communication, Map Tracking & Job Details

#### 15. `job_status_screen.dart`
*   **Finding 15.1** [`raw-widget-usage`]: Lines 821–835 — Raw `TextField` with inline `InputDecoration(border: OutlineInputBorder())` used for price counter-offer input instead of `ThemedTextField`.
    *   *Remediation*: Replace with `ThemedTextField(key: const Key('counter_offer_input'), controller: _counterOfferController, keyboardType: const TextInputType.numberWithOptions(decimal: true), hintText: ..., prefixIcon: const Icon(Icons.attach_money))`.
    *   *Effort*: Trivial single-widget swap.

#### 16. `rating_screen.dart`
*   **Finding 16.1** [`hardcoded-values`]: Lines 398 & 438 — `AppTypography.bodyMd.copyWith(fontSize: 13)` used for blind rating explanation texts.
    *   *Remediation*: Replace with `AppTypography.bodySm`.
    *   *Effort*: Trivial token replacement.

#### 17. `owner_history_screen.dart`
*   **Finding 17.1** [`hardcoded-values`]: Lines 97 & 99 — `AppTypography.titleMd.copyWith(fontSize: 13)` in TabBar label styling.
    *   *Remediation*: Replace with `AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold)`.
    *   *Effort*: Trivial token replacement.

#### 18. `customer_job_map_screen.dart` & `owner_fleet_map_screen.dart`
*   **Finding 18.1** [`hardcoded-values`]: Lines 104 & 143 (`customer_job_map_screen.dart`), Line 122 (`owner_fleet_map_screen.dart`) — `fontSize: 10` inside `AppTypography.labelMd.copyWith(fontSize: 10)` in map marker labels.
    *   *Remediation*: Replace with `AppTypography.labelMd` (11pt) or canonical compact marker typography token.
    *   *Effort*: Trivial token replacement.
*   **Finding 18.2** [`hardcoded-values`]: Line 131 (`customer_job_map_screen.dart`) — `horizontal: 6` hardcoded padding number.
    *   *Remediation*: Replace with `AppSpacing.xs` (4dp) or `AppSpacing.base` (8dp).
    *   *Effort*: Trivial token replacement.

#### 19. `employee_home_screen.dart` & `employee_jobs_screen.dart`
*   **Finding 19.1** [`hardcoded-values`]: Line 135 (`employee_home_screen.dart`), Line 226 (`employee_jobs_screen.dart`) — `fontSize: 10` inside `AppTypography.labelMd.copyWith(fontSize: 10)` on unread notification bell badge.
    *   *Remediation*: Standardize across all role navigation headers using a shared `NotificationBellBadge` widget or `AppTypography.labelMd`.
    *   *Effort*: Trivial.

---

### Batch E: Widget Library Internal Consistency (`frontend/lib/widgets/`)

#### 20. `create_ticket_dialog.dart`
*   **Finding 20.1** [`hardcoded-values`]: Line 110 — `fontSize: 12` inside `AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant, fontSize: 12)`.
    *   *Remediation*: Replace with `AppTypography.labelLg` or `AppTypography.bodySm`.
    *   *Effort*: Trivial token replacement.
*   **Finding 20.2** [`raw-widget-usage`]: Line 71 — Raw `ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.primary...))` instead of `ThemedSnackBar.showSuccess`.
    *   *Remediation*: Replace with `ThemedSnackBar.showSuccess(context, "Ticket submitted successfully! (Ticket ID: ${res['id'] ?? ''})")`.
    *   *Effort*: Trivial single-widget swap.
*   **Finding 20.3** [`dialog-sizing-risk`]: Lines 153–169 — Action buttons wrapped in fixed `SizedBox(width: 100)` and `SizedBox(width: 130)` instead of utilizing `SecondaryButton(isFullWidth: false)` and `PrimaryButton(isFullWidth: false)`.
    *   *Remediation*: Remove hardcoded width boxes and use `isFullWidth: false`.
    *   *Effort*: Trivial single-widget swap.

#### 21. `entity_avatar.dart`
*   **Finding 21.1** [`hardcoded-values`]: Lines 52 & 70 — Raw `TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: radius * 0.8)` instead of deriving from `AppTypography`.
    *   *Remediation*: Use `GoogleFonts.poppins(color: fg, fontWeight: FontWeight.bold, fontSize: radius * 0.8)`.
    *   *Effort*: Trivial token replacement.
*   **Finding 21.2** [`missing-debounce-protection`]: Line 90 — Raw `GestureDetector(onTap: onTap)` without debounce protection if avatar is interactive.
    *   *Remediation*: Wrap with standard debounce guard when `onTap` is provided.
    *   *Effort*: Trivial.

#### 22. `rating_summary_card.dart`
*   **Finding 22.1** [`hardcoded-values`]: Line 28 (`size: 20`), Line 62 (`height: 2`), Lines 74 & 79 (`AppSpacing.base + 2`), Line 83 (`fontSize: 13`).
    *   *Remediation*: Replace with `AppIconSize.md`, `AppSpacing.xxs`, `AppSpacing.baseSm`, and `AppTypography.bodySm`.
    *   *Effort*: Trivial token replacement.

#### 23. `stat_card.dart`
*   **Finding 23.1** [`hardcoded-values`]: Line 51 (`size: 24`), Line 72 (`size: 14`), Line 75 (`const SizedBox(width: 4)`).
    *   *Remediation*: Replace with `AppIconSize.md`, `AppIconSize.xs`, and `AppSpacing.xs`.
    *   *Effort*: Trivial token replacement.

#### 24. `status_badge.dart`
*   **Finding 24.1** [`hardcoded-values`]: Line 171 (`compact ? AppSpacing.xs / 2 : AppSpacing.xs`), Line 172 (`compact ? AppSpacing.base / 2 : AppSpacing.sm`), Line 173 (`iconSize = compact ? 14.0 : 16.0`).
    *   *Remediation*: Replace with `AppSpacing.xxs : AppSpacing.xs`, `AppSpacing.xs : AppSpacing.sm`, and `AppIconSize.xs : AppIconSize.sm`.
    *   *Effort*: Trivial token replacement.

#### 25. `location_picker_map.dart`
*   **Finding 25.1** [`raw-widget-usage`]: Lines 73 & 84 — Raw `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` instead of `ThemedSnackBar.showError`.
    *   *Remediation*: Replace with `ThemedSnackBar.showError(context, ...)`.
    *   *Effort*: Trivial single-widget swap.
*   **Finding 25.2** [`hardcoded-values`]: Line 166 — Raw `TextStyle(fontWeight: FontWeight.bold)` inside FAB label.
    *   *Remediation*: Replace with `AppTypography.labelLg.copyWith(color: AppColors.onPrimary)`.
    *   *Effort*: Trivial token replacement.

---

## 4. Fully Compliant Screens & Components (Audit Trail)

The following 23 screens and widgets were audited and verified as **100% compliant** with zero remaining design system or token inconsistencies:

### Screens
1.  **`subscription_screen.dart`**: Migrated in commit `de9f1e9` using `ThemedCard`, `ThemedSectionHeader`, `StatusBadge`, `PrimaryButton`, `SecondaryButton`, `ThemedWarningBanner`, `AppElevation`, and `AppColors`.
2.  **`update_required_screen.dart`**: Migrated in commit `0091b8e` using `ThemedCard`, `ThemedSectionHeader`, `PrimaryButton`, `SecondaryButton`, `ThemedBanner`, `AppRadius`, and `AppSpacing`.
3.  **`kyc_document_upload_screen.dart`**: Migrated in commit `95ec302` using `ThemedCard`, `ThemedSectionHeader`, `StatusBadge`, `PrimaryButton`, `SecondaryButton`, `ThemedBanner`, and `ThemedErrorBanner`.
4.  **`employee_history_screen.dart`**: Verified clean, utilizing `ThemedCard`, `ThemedEmptyState`, `ThemedErrorBanner`, `StatusBadge`, `SkeletonLoader`, `AppElevation`, `AppRadius`, and `AppSpacing`.
5.  **`forgot_password_screen.dart`**: Verified clean, utilizing `ThemedTextField`, `ThemedCard`, `ThemedErrorBanner`, `ThemedSnackBar`, `PrimaryButton`, `SecondaryButton`, `AppRadius`, and `AppSpacing`.

### Widgets
6.  **`cancel_job_dialog.dart`**: Migrated in commit `0091b8e` with `ThemedTextField`, `ThemedErrorBanner`, `PrimaryButton`, `SecondaryButton`, and tokenized responsive sizing.
7.  **`confirm_action_dialog.dart`**: Migrated in commit `0091b8e` with `AppRadius.mdBorder`, `AppColors.surface`, `PrimaryButton`, and `SecondaryButton`.
8.  **`primary_button.dart`**: Fully compliant with `AppMotion.debounceGuard`, scale micro-interaction, `AppTypography.bodyLg`, and `AppRadius.defaultBorder`.
9.  **`secondary_button.dart`**: Fully compliant with `AppMotion.debounceGuard`, scale micro-interaction, `AppTypography.bodyLg`, and `AppRadius.defaultBorder`.
10. **`themed_card.dart`**: Master container card with `ThemedCardVariant`, `AppElevation`, and `AppRadius`.
11. **`themed_text_field.dart`**: Standardized text input with password toggle and token borders.
12. **`themed_loading_indicator.dart`**: Standardized loading spinner with brand tokens.
13. **`themed_empty_state.dart`**: Standardized zero-data layout with `AppIconSize.xl` and `SecondaryButton`.
14. **`themed_error_banner.dart`**: Direct tokenized wrapper over `ThemedBanner`.
15. **`themed_section_header.dart`**: Standardized layout header with `AppTypography.titleMd`.
16. **`themed_banner.dart`**: Unified inline alert banner system (`ThemedBannerType`).
17. **`themed_success_banner.dart`**: Inline success banner and `ThemedSnackBar` toast utility.
18. **`skeleton_loader.dart`**: Shimmer loaders and screen card skeleton primitives.
19. **`info_list_tile.dart`**: Reusable list tile inside `ThemedCard`.

---

## 5. Prioritized Remediation Plan

To execute these corrections safely without monolithic regressions, the work is organized into **5 discrete, dependency-ordered batches**. Each batch matches the scoped commit pattern used for earlier migrations.

```mermaid
graph TD
    B1[Batch 1: Shared Widgets & Foundation Hardening] --> B2[Batch 2: High-Traffic Customer & Auth Experience]
    B1 --> B3[Batch 3: Settings, Account & Notifications Center]
    B1 --> B4[Batch 4: Owner Operations & Service Dialogs]
    B2 --> B5[Batch 5: Real-Time Chat, Maps & Job Details]
    B3 --> B5
    B4 --> B5
```

### Batch 1: Shared Widgets & Foundation Hardening
*   **Rationale**: Fix shared widgets first so subsequent screen migrations inherit clean, consistent components.
*   **Target Files**:
    *   `frontend/lib/widgets/create_ticket_dialog.dart` (remove fixed button widths, wire `ThemedSnackBar`)
    *   `frontend/lib/widgets/entity_avatar.dart` (typography alignment, debounce protection)
    *   `frontend/lib/widgets/rating_summary_card.dart` (tokenized icon size, spacing arithmetic cleanup)
    *   `frontend/lib/widgets/stat_card.dart` (tokenized icon sizes and spacing)
    *   `frontend/lib/widgets/status_badge.dart` (tokenized padding and icon sizes)
    *   `frontend/lib/widgets/location_picker_map.dart` (wire `ThemedSnackBar`, tokenized label)
*   **Verification Gate**: `flutter test test/shared_widgets_test.dart` & `flutter analyze`.

### Batch 2: High-Traffic Customer & Auth Experience
*   **Rationale**: Highest end-user visibility. Replaces raw buttons, custom textfields, and handrolled booking dialogs.
*   **Target Files**:
    *   `frontend/lib/screens/customer_marketplace_screen.dart` (replace raw buttons, extract `BookingConfirmationDialog`)
    *   `frontend/lib/screens/customer_home_screen.dart` (header action link, unread badge token)
    *   `frontend/lib/screens/customer_jobs_screen.dart` (remove redundant retry button, tokenized labels)
    *   `frontend/lib/screens/login_screen.dart` (tokenized QD logo, link typography)
    *   `frontend/lib/screens/signup_screen.dart` (link typography)
    *   `frontend/lib/screens/otp_screen.dart` (wire `SecondaryButton` for OTP resend debounce protection)
*   **Verification Gate**: `flutter test test/customer_home_screen_test.dart test/customer_jobs_screen_test.dart test/widget_test.dart` & `flutter analyze`.

### Batch 3: Settings, Account & Notifications Center
*   **Rationale**: Centralized user settings and profile management flows.
*   **Target Files**:
    *   `frontend/lib/screens/settings_screen.dart` (remove divergent `_segmentedButtonStyle`, replace Logout `ElevatedButton` with destructive `PrimaryButton`, tokenized labels)
    *   `frontend/lib/screens/my_account_screen.dart` (replace raw buttons, extract `EmailChangeDialog` to `widgets/`)
    *   `frontend/lib/screens/notifications_screen.dart` (replace handrolled clear dialog with `ConfirmActionDialog`)
*   **Verification Gate**: `flutter test test/settings_screen_test.dart test/my_account_screen_test.dart` & `flutter analyze`.

### Batch 4: Owner Operations & Service Management
*   **Rationale**: Financial operations, cash reconciliation, service directory configuration, and employee roster.
*   **Target Files**:
    *   `frontend/lib/screens/wallet_screen.dart` (extract `PayoutRequestDialog` and `DepositFundsDialog` to `widgets/`, tokenized chips)
    *   `frontend/lib/screens/owner_configuration_screen.dart` (replace raw `OutlinedButton.icon` for location and photo pickers, tokenized header)
    *   `frontend/lib/screens/service_screen.dart` (extract `CreateServiceDialog` to `widgets/`)
    *   `frontend/lib/screens/employee_screen.dart` (replace `CircleAvatar` with `EntityAvatar`, replace success dialog with `ThemedSnackBar.showSuccess`, tokenized tags)
    *   `frontend/lib/screens/owner_reconciliation_queue_screen.dart` (replace raw `ElevatedButton` with `ThemedErrorBanner`)
*   **Verification Gate**: `flutter test test/owner_payout_test.dart test/owner_configuration_screen_test.dart test/owner_employees_test.dart test/reconciliation_queue_test.dart` & `flutter analyze`.

### Batch 5: Real-Time Communication, Map Tracking & Job Details
*   **Rationale**: Real-time WebSocket job tracking, live GPS map markers, blind ratings, and history tabs.
*   **Target Files**:
    *   `frontend/lib/screens/job_status_screen.dart` (replace raw `TextField` with `ThemedTextField` for price negotiation)
    *   `frontend/lib/screens/rating_screen.dart` (replace `bodyMd.copyWith(fontSize: 13)` with `AppTypography.bodySm`)
    *   `frontend/lib/screens/owner_history_screen.dart` (replace TabBar `titleMd.copyWith(fontSize: 13)` with `AppTypography.bodySm`)
    *   `frontend/lib/screens/customer_job_map_screen.dart` & `owner_fleet_map_screen.dart` (tokenized map marker typography and padding)
    *   `frontend/lib/screens/employee_home_screen.dart` & `employee_jobs_screen.dart` (standardize notification bell unread badge)
*   **Verification Gate**: `flutter test test/negotiable_transport_pricing_test.dart test/employee_home_screen_test.dart test/owner_history_screen_test.dart` & `flutter analyze`.

---

## 6. Audit Trail & Verification Log

| File Checked | Lines | Status | Findings Summary |
| :--- | :---: | :---: | :--- |
| `frontend/lib/screens/chat_screen.dart` | 313 | Compliant | Minor 8x8 connecting spinner; standard chat bubble corner styling. |
| `frontend/lib/screens/customer_home_screen.dart` | 532 | Remediation (Batch 2) | Badge font size, header text button link. |
| `frontend/lib/screens/customer_job_map_screen.dart` | 227 | Remediation (Batch 5) | Marker font size (10pt) & padding (6dp). |
| `frontend/lib/screens/customer_jobs_screen.dart` | 222 | Remediation (Batch 2) | Redundant retry button, font size (12pt). |
| `frontend/lib/screens/customer_marketplace_screen.dart` | 919 | Remediation (Batch 2) | Map picker button, handrolled booking dialog. |
| `frontend/lib/screens/employee_history_screen.dart` | 255 | **Compliant** | 100% tokenized and component-aligned. |
| `frontend/lib/screens/employee_home_screen.dart` | 242 | Remediation (Batch 5) | Badge font size (10pt). |
| `frontend/lib/screens/employee_jobs_screen.dart` | 933 | Remediation (Batch 5) | Badge font size (10pt); already uses `ConfirmActionDialog`. |
| `frontend/lib/screens/employee_screen.dart` | 666 | Remediation (Batch 4) | `CircleAvatar` swap, success dialog, typography. |
| `frontend/lib/screens/forgot_password_screen.dart` | 305 | **Compliant** | 100% tokenized, single-step layout. |
| `frontend/lib/screens/home_screen.dart` | 972 | Remediation (Batch 5) | Badge font size (10pt); uses `CancelJobDialog.show`. |
| `frontend/lib/screens/job_status_screen.dart` | 971 | Remediation (Batch 5) | Raw `TextField` on counter-offer input. |
| `frontend/lib/screens/kyc_document_upload_screen.dart` | 635 | **Compliant** | Migrated in `95ec302`. |
| `frontend/lib/screens/login_screen.dart` | 260 | Remediation (Batch 2) | Logo typography, link buttons. |
| `frontend/lib/screens/my_account_screen.dart` | 572 | Remediation (Batch 3) | Raw action buttons, embedded `EmailChangeDialog`. |
| `frontend/lib/screens/notifications_screen.dart` | 333 | Remediation (Batch 3) | Handrolled clear dialog. |
| `frontend/lib/screens/otp_screen.dart` | 226 | Remediation (Batch 2) | Resend code debounce safeguard. |
| `frontend/lib/screens/owner_configuration_screen.dart` | 663 | Remediation (Batch 4) | Map/image picker buttons, header typography. |
| `frontend/lib/screens/owner_fleet_map_screen.dart` | 189 | Remediation (Batch 5) | Marker font size (10pt). |
| `frontend/lib/screens/owner_history_screen.dart` | 566 | Remediation (Batch 5) | TabBar typography (13pt). |
| `frontend/lib/screens/owner_reconciliation_queue_screen.dart` | 313 | Remediation (Batch 4) | Raw `ElevatedButton` on error state. |
| `frontend/lib/screens/rating_screen.dart` | 515 | Remediation (Batch 5) | Explanation typography (13pt). |
| `frontend/lib/screens/service_screen.dart` | 446 | Remediation (Batch 4) | Embedded `Create New Service` dialog. |
| `frontend/lib/screens/settings_screen.dart` | 407 | Remediation (Batch 3) | Custom segmented style, raw logout button. |
| `frontend/lib/screens/signup_screen.dart` | 271 | Remediation (Batch 2) | Link button. |
| `frontend/lib/screens/subscription_screen.dart` | 298 | **Compliant** | Migrated in `de9f1e9`. |
| `frontend/lib/screens/update_required_screen.dart` | 193 | **Compliant** | Migrated in `0091b8e`. |
| `frontend/lib/screens/wallet_screen.dart` | 831 | Remediation (Batch 4) | Embedded payout and deposit dialogs. |
