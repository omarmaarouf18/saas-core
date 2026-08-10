# QuickDelivery Frontend Design System Specification

> [!IMPORTANT]
> **Single Source of Truth**: All tokens, themes, and design rules documented here are directly backed by executable Dart constants defined in [`frontend/lib/core/theme.dart`](../../frontend/lib/core/theme.dart). Developers must use these tokens exclusively rather than introducing hardcoded magic numbers or raw hex values.

---

## 1. Overview & Usage Guidelines

This design system provides the visual architecture and component spec for QuickDelivery's Flutter frontend. It ensures brand consistency, WCAG AA accessibility compliance, and rapid UI development across mobile and desktop viewports.

### Architectural Rules
1. **Never Hardcode Visual Values**: Use `AppColors`, `AppSpacing`, `AppRadius`, `AppElevation`, `AppMotion`, `AppIconSize`, and `AppTypography`.
2. **Component Reuse First**: Use existing widgets in `frontend/lib/widgets/`. If a required pattern is missing, propose a new shared widget in `frontend/lib/widgets/` rather than writing inline ad-hoc layout logic in screen files.
3. **RTL-First Layouts**: Use `EdgeInsetsDirectional` and `AlignmentDirectional` to support Arabic (RTL) and English (LTR) seamlessly.

---

## 2. Complete Design Token Reference

### 2.1 Color Tokens (`AppColors`)

| Token Name | Hex Code / Value | Usage & Meaning | WCAG Contrast (on White) |
| :--- | :--- | :--- | :--- |
| `AppColors.primary` | `#0D1321` | Deep Navy brand color for headers, primary buttons, dark mode surfaces | N/A (Dark Surface) |
| `AppColors.secondary` | `#FFC107` | Amber Gold accent for key focal points, badges, active states | 1.34:1 (Requires dark text) |
| `AppColors.scaffoldBackground` | `#E5E7EB` | Cool gray background for app scaffold | N/A |
| `AppColors.surface` | `#FFFFFF` | Pure white surface for cards and container backgrounds | N/A |
| `AppColors.onPrimary` | `#FFFFFF` | Primary text color on dark navy backgrounds | 17.5:1 (AAA) |
| `AppColors.onSecondary` | `#0D1321` | Deep navy text on gold secondary containers | 13.0:1 (AAA) |
| `AppColors.onSurface` | `#1A1C1C` | Charcoal body text on light surface containers | 15.8:1 (AAA) |
| `AppColors.onSurfaceVariant` | `#45464C` | Slate gray text for secondary captions and subtitles | 9.2:1 (AAA) |
| `AppColors.success` | `#15803D` | Dark green for completed badges, positive trends, verified tags | 5.02:1 (AA) |
| `AppColors.danger` | `#BA1A1A` | Dark red for errors, destructive buttons, cancelled statuses | 10.1:1 (AAA) |
| `AppColors.warning` | `#B45309` | Warm amber-700 for pending reviews, warnings, hold alerts | 5.02:1 (AA) |
| `AppColors.outline` | `#57585E` | Dark gray for active input borders and icon outlines | 7.09:1 (AAA) |
| `AppColors.outlineVariant` | `#8E8F95` | Mid gray for subtle card dividers and passive borders | 3.34:1 (UI Component) |

### 2.2 Spacing Scale (`AppSpacing`)

| Token Name | Value (dp) | Usage Rule |
| :--- | :--- | :--- |
| `AppSpacing.xxs` | `2.0` | Micro badge padding, tight vertical chip insets |
| `AppSpacing.xs` | `4.0` | Micro spacing (icon-to-text gap, badge internal padding) |
| `AppSpacing.base` | `8.0` | Standard grid unit (list item padding, tight row gaps) |
| `AppSpacing.baseSm` | `10.0` | Intermediate dialog/banner padding, status pill insets |
| `AppSpacing.sm` | `12.0` | Small container inset, compact card interior padding |
| `AppSpacing.md` | `16.0` | Standard page margin (mobile), card interior padding |
| `AppSpacing.lg` | `24.0` | Large section gap, spacing between distinct card groups |
| `AppSpacing.xl` | `32.0` | Major screen division gap, header-to-content separation |
| `AppSpacing.xxl` | `40.0` | Large empty state vertical spacing |
| `AppSpacing.xxxl` | `100.0` | Screen empty state placeholder top spacer |
| `AppSpacing.gutter` | `16.0` | Standard grid gutter width between multi-column cards |
| `AppSpacing.marginMobile` | `16.0` | Horizontal scaffold edge margin on mobile viewports |
| `AppSpacing.marginDesktop` | `48.0` | Horizontal scaffold edge margin on desktop viewports |

### 2.3 Border Radius Scale (`AppRadius`)

| Token Name | Value (dp) | Helper Property | Usage Rule |
| :--- | :--- | :--- | :--- |
| `AppRadius.xxs` | `3.0` | `AppRadius.xxsBorder` | Mini progress track indicators |
| `AppRadius.xs` | `2.0` | `AppRadius.xsBorder` | Micro tags, progress bar indicators |
| `AppRadius.sm` | `4.0` | `AppRadius.smBorder` | Status badges, chip elements, tooltips |
| `AppRadius.defaultValue` | `8.0` | `AppRadius.defaultBorder` | Buttons, text fields, small alert banners |
| `AppRadius.smMd` | `10.0` | `AppRadius.smMdBorder` | Unread notification badge pill radius |
| `AppRadius.md` | `12.0` | `AppRadius.mdBorder` | Standard surface cards (`ThemedCard`), metric tiles |
| `AppRadius.lg` | `16.0` | `AppRadius.lgBorder` | Large modal cards, hero summary banners |
| `AppRadius.lgXl` | `20.0` | `AppRadius.lgXlBorder` | Pill category badge radius |
| `AppRadius.xl` | `24.0` | `AppRadius.xlBorder` | Bottom sheet top corners, floating dialogs |
| `AppRadius.full` | `9999.0` | `AppRadius.fullBorder` | Circular avatars (`EntityAvatar`), pill buttons |

### 2.4 Elevation & Shadow Scale (`AppElevation`)

| Level Name | Elevation (dp) | BoxShadow Configuration | Usage Rule |
| :--- | :--- | :--- | :--- |
| `AppElevation.level0` | `0.0` | `color: transparent, blur: 0` | Flat cards, inline input fields, bordered rows |
| `AppElevation.level1` | `1.0` | `color: rgba(13,19,33,0.08), blur: 8, offset: (0,2)` | `shadowLevel1List`: Resting/static content cards (`ThemedCard`), empty containers, read-only detail panels, audit log tiles |
| `AppElevation.level2` | `3.0` | `color: rgba(13,19,33,0.12), blur: 16, offset: (0,4)` | `shadowLevel2List`: Interactive/tappable cards, service booking cards, price counter-offer cards, form containers, dropdowns |
| `AppElevation.level3` | `6.0` | `color: rgba(13,19,33,0.16), blur: 24, offset: (0,8)` | Sticky action bars, bottom sheets, snackbars |
| `AppElevation.level4` | `12.0` | `color: rgba(13,19,33,0.24), blur: 32, offset: (0,16)` | Modal dialogs (`AlertDialog`), full screen overlays |

### 2.5 Motion & Animation Tokens (`AppMotion`)

| Token Category | Token Name | Value | Usage Rule |
| :--- | :--- | :--- | :--- |
| **Duration** | `AppMotion.durationFast` | `150 ms` | Micro-interactions, button presses, switch toggles |
| **Duration** | `AppMotion.durationMedium` | `300 ms` | Bottom sheet slides, tab transitions, expand/collapse |
| **Duration** | `AppMotion.durationMediumSlow` | `400 ms` | Hero summary banners, welcome card entrance animations |
| **Duration** | `AppMotion.durationSlow` | `500 ms` | Screen entrance animations, full hero fade-ins |
| **Duration** | `AppMotion.snackBarDisplay` | `2.0 s` | Toast notification / SnackBar display duration |
| **Curve** | `AppMotion.curveEntrance` | `Curves.easeOutCubic` | Elements entering the viewport from off-screen |
| **Curve** | `AppMotion.curveExit` | `Curves.easeInCubic` | Elements exiting the viewport |
| **Curve** | `AppMotion.curveStateChange` | `Curves.easeInOut` | Smooth in-place transitions (color fades, size shifts) |
| **Curve** | `AppMotion.curveBounce` | `Curves.elasticOut` | Playful status tick pops and badge highlights |
| **Logic Guard** | `AppMotion.debounceGuard` | `600 ms` | Double-tap debounce threshold for interactive buttons |

### 2.6 Iconography Scale (`AppIconSize`)

| Token Name | Size (dp) | Usage Rule |
| :--- | :--- | :--- |
| `AppIconSize.xs` | `14.0` | Compact status badge icons, micro inline indicators |
| `AppIconSize.sm` | `16.0` | Inline text icons, small button leading icons |
| `AppIconSize.md` | `24.0` | Standard list tile leading icons, app bar action icons |
| `AppIconSize.lg` | `32.0` | Featured metric card icons, stat summary badge icons |
| `AppIconSize.xl` | `48.0` | Empty state visual graphic icons, dialog header highlights |

### 2.7 Typography Scale (`AppTypography`)

| Method Name | Size (pt) | Weight | Height | Usage Role |
| :--- | :--- | :--- | :--- | :--- |
| `AppTypography.displayLg` | 48 | Bold (700) | 56/48 | Hero stat numbers, large marketing headlines |
| `AppTypography.headlineLg` | 32 | SemiBold (600) | 40/32 | Primary screen headers (desktop/tablet) |
| `AppTypography.headlineLgMobile` | 24 | SemiBold (600) | 32/24 | Primary screen headers (mobile viewports) |
| `AppTypography.titleMd` | 18 | SemiBold (600) | 24/18 | Section headers, card titles, dialog titles |
| `AppTypography.bodyLg` | 16 | Regular (400) | 24/16 | Prominent body text, lead paragraph text |
| `AppTypography.bodyMd` | 14 | Regular (400) | 20/14 | Standard body paragraphs, text input text |
| `AppTypography.labelLg` | 12 | SemiBold (600) | 16/12 | Input labels, primary button text, section tags |
| `AppTypography.labelMd` | 11 | Medium (500) | 14/11 | Metadata timestamps, status badge text, captions |

---

## 3. Shared Component Library Reference

All shared widgets are located in `frontend/lib/widgets/`. Below is the complete catalog:

| Widget Class Name | File Path | Visual Role & Purpose | Key Constructor Parameters | Primary Screen Usages |
| :--- | :--- | :--- | :--- | :--- |
| `CancelJobDialog` | `cancel_job_dialog.dart` | Job cancellation modal dialog with preset reason radios & custom input | `jobId`, `onCancelled` | `home_screen.dart`, `job_status_screen.dart` |
| `ConfirmActionDialog` | `confirm_action_dialog.dart` | Reusable modal confirmation for destructive or financial operations | `title`, `message`, `confirmText`, `isDestructive` | `employee_jobs_screen.dart`, `owner_reconciliation_queue_screen.dart` |
| `CreateTicketDialog` | `create_ticket_dialog.dart` | Customer/owner complaint ticket submission modal | `referenceId`, `referenceType` | `job_status_screen.dart`, `settings_screen.dart` |
| `DocumentViewerDialog` | `document_viewer_dialog.dart` | Full-screen interactive viewer for KYB/KYE document review | `documentUrl`, `title` | `kyb_kye_review_screen.dart` |
| `EntityAvatar` | `entity_avatar.dart` | Circular avatar widget rendering photo or initial initials with border | `imageUrl`, `name`, `radius` | `rating_screen.dart` |
| `InfoListTile` | `info_list_tile.dart` | Key-value information list row with leading icon and optional subtitle | `label`, `value`, `icon`, `trailing` | `wallet_screen.dart` |
| `LocationPickerMap` | `location_picker_map.dart` | Interactive OpenStreetMap coordinate picker for pickup/dropoff | `initialLocation`, `onLocationSelected` | `customer_marketplace_screen.dart` |
| `PrimaryButton` | `primary_button.dart` | Full-width high-contrast action button with loading spinner state | `text`, `onPressed`, `isLoading`, `icon` | Used across 16 screens |
| `RatingSummaryCard` | `rating_summary_card.dart` | Rating breakdown card displaying star average, progress bars & counts | `averageRating`, `totalReviews` | `home_screen.dart` |
| `SecondaryButton` | `secondary_button.dart` | Tonal / outlined secondary action button for non-primary choices | `text`, `onPressed`, `isLoading`, `icon` | Used across 9 screens |
| `SkeletonLoader` | `skeleton_loader.dart` | Reusable shimmer-animated block & per-screen card geometry loaders | `width`, `height`, `borderRadius`, `margin` | `customer_marketplace_screen.dart`, `home_screen.dart`, `employee_jobs_screen.dart`, `wallet_screen.dart` |
| `StatCard` | `stat_card.dart` | Metric card with icon, title, bold value, and trend indicator | `title`, `value`, `icon`, `subtitle` | `home_screen.dart`, `wallet_screen.dart` |
| `StatusBadge` | `status_badge.dart` | Localized pill badge mapping job/kyc/payout status to color/icon | `status` | Used across 10 screens |
| `ThemedCard` | `themed_card.dart` | Surface card container with radius, ambient elevation & border | `child`, `padding`, `margin`, `onTap` | Used across 23 screens |
| `ThemedEmptyState` | `themed_empty_state.dart` | Centered graphic placeholder for empty lists with action button | `icon`, `title`, `description`, `action` | Used across 12 screens |
| `ThemedErrorBanner` | `themed_error_banner.dart` | Dismissible alert card displaying operational errors or warnings | `message`, `onDismiss`, `onRetry` | Used across 12 screens |
| `ThemedLoadingIndicator` | `themed_loading_indicator.dart` | Brand-tinted progress spinner with optional progress label | `message` | Used across 12 screens |
| `ThemedSectionHeader` | `themed_section_header.dart` | Section header row with title and optional trailing action button | `title`, `actionText`, `onActionTap` | Used across 10 screens |
| `ThemedTextField` | `themed_text_field.dart` | Input field with floating label, validation error text & prefix icon | `label`, `controller`, `validator`, `prefixIcon` | Used across 13 screens |

> [!RULE]
> **Component Propose Rule**: If a developer requires a visual pattern not fulfilled by the 18 shared widgets above, they must propose and implement a new shared widget under `frontend/lib/widgets/` rather than adding custom inline container styling inside a screen file.

---

## 4. Screen Composition Patterns

### Pattern 1: Transparent Material-3 Header
AppBar uses transparent background and surface tinting to seamlessly blend with gradient summary cards.

```dart
AppBar(
  backgroundColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  surfaceTintColor: Colors.transparent,
  title: Text(l10n.screenTitle, style: AppTypography.titleMd),
  actions: [ /* Header Action Icons */ ],
)
```

### Pattern 2: Bottom Navigation with `IndexedStack`
Preserves visited tab state across navigation items without re-triggering network requests on tab change.

```dart
Scaffold(
  body: IndexedStack(
    index: _currentTab,
    children: _screens,
  ),
  bottomNavigationBar: NavigationBar(
    selectedIndex: _currentTab,
    onDestinationSelected: (index) => setState(() => _currentTab = index),
    destinations: const [ /* NavigationBarDestination items */ ],
  ),
)
```

### Pattern 3: Card-Based Dashboard Summary
Groups high-level operational metrics in a 2-column grid of `StatCard` widgets above detailed `ThemedCard` lists.

```dart
Column(
  crossAxisAlignment: CrossAlignment.start,
  children: [
    ThemedSectionHeader(title: l10n.dashboardSummary),
    const SizedBox(height: AppSpacing.sm),
    Row(
      children: [
        Expanded(child: StatCard(title: l10n.activeJobs, value: '$activeCount', icon: Icons.work_outline)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: StatCard(title: l10n.earnings, value: '$earnings EGP', icon: Icons.payments_outlined)),
      ],
    ),
  ],
)
```

---

## 5. Tracked Design Debt Backlog

> [!NOTE]
> **Status**: **[100% RESOLVED IN PHASE 1]** All 55 catalogued instances of hardcoded values have been replaced with canonical `AppColors`, `AppSpacing`, `AppRadius`, and `AppTypography` design tokens. Automated audit via `scratch/audit_debt.py` returns **0** findings.

The following 55 catalogued instances of hardcoded values were remediated in Phase 1:

| # | Screen File | Line | Debt Category | Raw Value | Context |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `chat_screen.dart` | 85 | Raw Material Color | `Colors.red` | `backgroundColor: Colors.red.shade800` |
| 2 | `chat_screen.dart` | 117 | Hardcoded SizedBox Dimension | `SizedBox(width: 4)` | `const SizedBox(width: 4)` |
| 3 | `chat_screen.dart` | 136 | Hardcoded SizedBox Dimension | `SizedBox(width: 4)` | `const SizedBox(width: 4)` |
| 4 | `chat_screen.dart` | 153 | Hardcoded SizedBox Dimension | `SizedBox(width: 4)` | `const SizedBox(width: 4)` |
| 5 | `customer_home_screen.dart` | 113 | Hardcoded EdgeInsets | `EdgeInsets.all(2)` | `padding: const EdgeInsets.all(2)` |
| 6 | `customer_home_screen.dart` | 116 | Hardcoded BorderRadius | `BorderRadius.circular(10)` | `borderRadius: BorderRadius.circular(10)` |
| 7 | `customer_home_screen.dart` | 171 | Hardcoded TextStyle | `TextStyle(color: ...)` | `style: TextStyle(color: Theme.of(context)...)` |
| 8 | `customer_job_map_screen.dart` | 96 | Hardcoded BorderRadius | `BorderRadius.circular(4)` | `borderRadius: BorderRadius.circular(4)` |
| 9 | `customer_job_map_screen.dart` | 132 | Hardcoded BorderRadius | `BorderRadius.circular(4)` | `borderRadius: BorderRadius.circular(4)` |
| 10 | `customer_job_map_screen.dart` | 184 | Hardcoded BorderRadius | `BorderRadius.circular(8)` | `borderRadius: BorderRadius.circular(8)` |
| 11 | `customer_job_map_screen.dart` | 186 | Hardcoded EdgeInsets | `EdgeInsets.all(12)` | `padding: const EdgeInsets.all(12)` |
| 12 | `customer_job_map_screen.dart` | 189 | Hardcoded BorderRadius | `BorderRadius.circular(8)` | `borderRadius: BorderRadius.circular(8)` |
| 13 | `customer_job_map_screen.dart` | 195 | Hardcoded SizedBox Dimension | `SizedBox(width: 8)` | `SizedBox(width: 8)` |
| 14 | `customer_job_map_screen.dart` | 199 | Hardcoded TextStyle | `TextStyle(fontSize: 13)` | `style: TextStyle(fontSize: 13)` |
| 15 | `customer_job_map_screen.dart` | 216 | Hardcoded BorderRadius | `BorderRadius.circular(8)` | `borderRadius: BorderRadius.circular(8)` |
| 16 | `customer_job_map_screen.dart` | 218 | Hardcoded EdgeInsets | `EdgeInsets.all(10)` | `padding: const EdgeInsets.all(10)` |
| 17 | `customer_job_map_screen.dart` | 223 | Hardcoded BorderRadius | `BorderRadius.circular(8)` | `borderRadius: BorderRadius.circular(8)` |
| 18 | `customer_job_map_screen.dart` | 234 | Hardcoded SizedBox Dimension | `SizedBox(width: 8)` | `const SizedBox(width: 8)` |
| 19 | `customer_marketplace_screen.dart` | 93 | Hardcoded EdgeInsets | `EdgeInsets.all(2)` | `padding: const EdgeInsets.all(2)` |
| 20 | `customer_marketplace_screen.dart` | 96 | Hardcoded BorderRadius | `BorderRadius.circular(10)` | `borderRadius: BorderRadius.circular(10)` |
| 21 | `customer_marketplace_screen.dart` | 176 | Hardcoded TextStyle | `TextStyle(fontWeight: ...)` | `style: const TextStyle(fontWeight: ...)` |
| 22 | `customer_marketplace_screen.dart` | 852 | Hardcoded SizedBox Dimension | `SizedBox(width: 4)` | `const SizedBox(width: 4)` |
| 23 | `employee_jobs_screen.dart` | 222 | Hardcoded EdgeInsets | `EdgeInsets.all(2)` | `padding: const EdgeInsets.all(2)` |
| 24 | `employee_jobs_screen.dart` | 225 | Hardcoded BorderRadius | `BorderRadius.circular(10)` | `borderRadius: BorderRadius.circular(10)` |
| 25 | `employee_jobs_screen.dart` | 316 | Hardcoded EdgeInsets | `EdgeInsets.symmetric(...)` | `padding: const EdgeInsets.symmetric(...)` |
| 26 | `home_screen.dart` | 120 | Hardcoded EdgeInsets | `EdgeInsets.all(2)` | `padding: const EdgeInsets.all(2)` |
| 27 | `home_screen.dart` | 123 | Hardcoded BorderRadius | `BorderRadius.circular(10)` | `borderRadius: BorderRadius.circular(10)` |
| 28 | `home_screen.dart` | 197 | Hardcoded TextStyle | `TextStyle(color: ...)` | `style: TextStyle(color: ...)` |
| 29 | `home_screen.dart` | 301 | Hardcoded TextStyle | `TextStyle(color: ...)` | `style: TextStyle(color: ...)` |
| 30 | `job_status_screen.dart` | 639 | Hardcoded SizedBox Dimension | `SizedBox(width: 4)` | `const SizedBox(width: 4)` |
| 31 | `kyb_kye_review_screen.dart` | 346 | Hardcoded SizedBox Dimension | `SizedBox(width: 4)` | `const SizedBox(width: 4)` |
| 32 | `notifications_screen.dart` | 107 | Hardcoded TextStyle | `TextStyle(color: ...)` | `style: const TextStyle(...)` |
| 33 | `owner_fleet_map_screen.dart` | 110 | Hardcoded BorderRadius | `BorderRadius.circular(4)` | `borderRadius: BorderRadius.circular(4)` |
| 34 | `owner_fleet_map_screen.dart` | 146 | Hardcoded BorderRadius | `BorderRadius.circular(8)` | `borderRadius: BorderRadius.circular(8)` |
| 35 | `owner_fleet_map_screen.dart` | 148 | Hardcoded EdgeInsets | `EdgeInsets.all(12)` | `padding: const EdgeInsets.all(12)` |
| 36 | `owner_fleet_map_screen.dart` | 151 | Hardcoded BorderRadius | `BorderRadius.circular(8)` | `borderRadius: BorderRadius.circular(8)` |
| 37 | `owner_fleet_map_screen.dart` | 156 | Hardcoded SizedBox Dimension | `SizedBox(width: 8)` | `SizedBox(width: 8)` |
| 38 | `owner_fleet_map_screen.dart` | 160 | Hardcoded TextStyle | `TextStyle(fontSize: 13)` | `style: TextStyle(fontSize: 13)` |
| 39 | `owner_fleet_map_screen.dart` | 177 | Hardcoded BorderRadius | `BorderRadius.circular(8)` | `borderRadius: BorderRadius.circular(8)` |
| 40 | `owner_fleet_map_screen.dart` | 179 | Hardcoded EdgeInsets | `EdgeInsets.all(10)` | `padding: const EdgeInsets.all(10)` |
| 41 | `owner_fleet_map_screen.dart` | 184 | Hardcoded BorderRadius | `BorderRadius.circular(8)` | `borderRadius: BorderRadius.circular(8)` |
| 42 | `owner_fleet_map_screen.dart` | 195 | Hardcoded SizedBox Dimension | `SizedBox(width: 8)` | `const SizedBox(width: 8)` |
| 43 | `owner_history_screen.dart` | 409 | Raw Material Color | `Colors.teal` | `color = Colors.teal;` |
| 44 | `owner_reconciliation_queue_screen.dart` | 240 | Hardcoded TextStyle | `TextStyle(color: ...)` | `style: const TextStyle(...)` |
| 45 | `owner_reconciliation_queue_screen.dart` | 293 | Hardcoded EdgeInsets | `EdgeInsets.symmetric(...)` | `padding: const EdgeInsets.symmetric(...)` |
| 46 | `rating_screen.dart` | 106 | Raw Material Color | `Colors.red` | `backgroundColor: Colors.red` |
| 47 | `rating_screen.dart` | 134 | Raw Material Color | `Colors.green` | `backgroundColor: Colors.green` |
| 48 | `rating_screen.dart` | 149 | Raw Material Color | `Colors.red` | `backgroundColor: Colors.red` |
| 49 | `rating_screen.dart` | 461 | Hardcoded BorderRadius | `BorderRadius.circular(3)` | `borderRadius: BorderRadius.circular(3)` |
| 50 | `rating_screen.dart` | 471 | Hardcoded BorderRadius | `BorderRadius.circular(3)` | `borderRadius: BorderRadius.circular(3)` |
| 51 | `service_screen.dart` | 83 | Hardcoded SizedBox Dimension | `SizedBox(height: 100)` | `const SizedBox(height: 100)` |
| 52 | `service_screen.dart` | 143 | Hardcoded BorderRadius | `BorderRadius.circular(20)` | `BorderRadius.circular(20)` |
| 53 | `subscription_screen.dart` | 242 | Hardcoded EdgeInsets | `EdgeInsets.symmetric(...)` | `const EdgeInsets.symmetric(...)` |
| 54 | `wallet_screen.dart` | 269 | Hardcoded SizedBox Dimension | `SizedBox(height: 4)` | `const SizedBox(height: 4)` |
| 55 | `wallet_screen.dart` | 321 | Raw Material Color | `Colors.teal` | `color = Colors.teal;` |

---

## 6. RTL & Localization Design Rules

1. **Directional Insets & Padding**: Use `EdgeInsetsDirectional.only()`, `EdgeInsetsDirectional.fromSTEB()`, or `EdgeInsetsDirectional.symmetric()` so horizontal padding automatically flips when switching between LTR (English) and RTL (Arabic).
2. **Directional Alignment**: Use `AlignmentDirectional.centerStart` or `AlignmentDirectional.centerEnd` instead of `Alignment.centerLeft` or `Alignment.centerRight`.
3. **Directional Borders**: Use `BorderRadiusDirectional.horizontal()` for leading/trailing rounded corners.
4. **Localization Strings**: Access strings via `context.l10n` or `AppLocalizations.of(context)!`. Never hardcode raw display strings in widget constructors.
