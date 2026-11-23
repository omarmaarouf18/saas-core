# Worklog: REBRAND-THEME — Waddify colour tokens, the Readex Pro font and the in-app brand mark

## Task and scope
- Task ID: REBRAND-THEME
- Item IDs covered: GitHub #57 (tracker #54), priority P0
- Allowed paths (lane from task prompt):
  - `frontend/lib/ui/tokens.dart`, `frontend/lib/ui/qd_theme.dart`
  - `frontend/lib/ui/components/**` only where a colour or font is hard-coded instead of read from the tokens (shared widgets: call each out in its own commit and in the report, per CLAUDE.md "Shared Widget Changes")
  - `frontend/assets/fonts/**` (add Readex Pro + its OFL licence; remove IBM Plex Sans Arabic once nothing uses it)
  - `frontend/lib/core/app_version.dart` (default version only)
  - `frontend/lib/ui/components/qd_brand_mark.dart` (new) and `frontend/lib/ui/gallery/qd_gallery_screen.dart` (add the mark to the gallery)
  - `frontend/lib/features/auth/launch_splash.dart` and `frontend/lib/features/auth/login_page.dart` — the brand tile only (today a boxed Icons.inventory_2_outlined in gold on navy)
  - `frontend/lib/services/local_notifications.dart` — the hard-coded Color(0xFFFFC107) notification accent only
  - `frontend/lib/features/courier/active_job_page.dart` — the hard-coded Color(0x260D1321) shadow only
  - any other file under `frontend/lib/features/**` or `frontend/lib/ui/components/**` only to point a `.gold` / `.goldTint` / `.onGold` read at the right token (rating, sun, or another palette token; see "Audit every gold use"), each listed in the worklog
  - golden PNGs under `frontend/test/**/goldens/`
  - `docs/design/DESIGN_SYSTEM.md`, `docs/worklog/REBRAND-THEME.md`
  - Hot path granted: `frontend/pubspec.yaml` — the `fonts:` block and the `version:` line only.
- Agent branch: agent/REBRAND-THEME-tokens-font, created from logic-exploitation (d97bd841), rebased onto logic-exploitation (40f650fd) after owner folded changelog fix for TestChangelogCommitSHAs.

## Decisions taken
- Rebased branch onto logic-exploitation (40f650fd) after upstream changelog SHA format fix.
- Values first, names later: preserved token property names (`gold`, `onGold`, `goldTint`, `navy`, `onNavy`) and mapped their values to the Waddify palette per ADR-0029, documenting historical naming in doc comments.
- Added token pairs `rating` / `onRating` (fixed-meaning gold `#FFC107` / onRating `#0D1321`) and `sun` / `onSun` (warm brand accent Sun `#F2A541` / onSun Ink `#10233F`).
- Audited all 47 `.gold` / `.onGold` / `.goldTint` reads and 2 hardcoded colors in `frontend/lib/`. Fixed-meaning rating star read in `rating_page.dart:280` migrated to `c.rating`.

## Audit of every gold use

| File:Line | Token Read | What it paints | Classification | New Token / Mapping |
| :--- | :--- | :--- | :--- | :--- |
| `frontend/lib/features/account/notifications/announcement_detail_sheet.dart:74` | `c.gold` | Announcement header icon tile fill | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/features/account/notifications/announcement_detail_sheet.dart:77` | `c.onGold` | Announcement header icon | Brand accent | `c.onGold` (#FFFFFF) |
| `frontend/lib/features/account/notifications/notifications_page.dart:335` | `c.gold` | Admin announcement notification badge background | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/features/account/notifications/notifications_page.dart:336` | `c.onGold` | Admin announcement notification badge icon | Brand accent | `c.onGold` (#FFFFFF) |
| `frontend/lib/features/account/notifications/notifications_page.dart:340` | `c.gold` | Job alert notification badge background | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/features/account/notifications/notifications_page.dart:341` | `c.onGold` | Job alert notification badge icon | Brand accent | `c.onGold` (#FFFFFF) |
| `frontend/lib/features/account/notifications/notifications_page.dart:388` | `c.goldTint` | Unread notification item card background tint | Action / State | `c.goldTint` (#E3F4F3) |
| `frontend/lib/features/auth/launch_splash.dart:34` | `QdColors.light.gold` | Splash brand tile box icon | Brand mark (replaced) | Replaced with `QdBrandMark(variant: onDark)` |
| `frontend/lib/features/auth/login_page.dart:234` | `QdColors.light.gold` | Login brand tile box icon | Brand mark (replaced) | Replaced with `QdBrandMark(variant: onDark)` |
| `frontend/lib/features/auth/update_required_page.dart:98` | `c.gold` | Force-update hero tile background | Action / Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/features/auth/update_required_page.dart:102` | `c.onGold` | Force-update hero tile icon | Action / Brand accent | `c.onGold` (#FFFFFF) |
| `frontend/lib/features/courier/courier_map.dart:89` | `c.gold` | Drop-off map marker fill | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/features/courier/courier_map.dart:158` | `c.gold` | Courier self position indicator center dot | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/features/courier/courier_route.dart:78` | `c.gold` | Route drop-off stop mark fill | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/features/customer/chat/chat_page.dart:488` | `c.goldTint` | Own outgoing message bubble background | Brand accent / State | `c.goldTint` (#E3F4F3) |
| `frontend/lib/features/customer/chat/chat_page.dart:489` | `c.gold` | Own outgoing message bubble border | Brand accent / State | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/features/customer/home_page.dart:287` | `QdIconTileTone.gold` | Primary delivery service icon tile | Brand accent | `c.gold` / `c.onGold` (Nile/White) |
| `frontend/lib/features/customer/order/rating_page.dart:280` | `c.gold` | Rating star active fill | Fixed-meaning | **`c.rating`** (#FFC107) |
| `frontend/lib/features/customer/order/track_map.dart:92` | `c.gold` | Track map drop-off marker fill | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/features/customer/orders_page.dart:217` | `QdIconTileTone.gold` | Ongoing order category tile tone | Brand accent | `c.gold` / `c.onGold` (Nile/White) |
| `frontend/lib/features/owner/fleet_map_page.dart:359` | `c.gold` | On-job courier marker border | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/features/owner/fleet_map_page.dart:490` | `c.gold` | Legend on-job courier dot border | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/features/owner/service_photo_section.dart:245` | `QdIconTileTone.gold` | Service photo upload tile tone | Brand accent | `c.gold` / `c.onGold` (Nile/White) |
| `frontend/lib/features/owner/service_setup_page.dart:661` | `c.goldTint` | Selected service category tile background | Action / State | `c.goldTint` (#E3F4F3) |
| `frontend/lib/ui/components/qd_bottom_nav.dart:97` | `c.gold` | Active bottom nav item pill indicator | Action | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/components/qd_button.dart:87` | `c.gold` | Primary button enabled fill | Action | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/components/qd_button.dart:88` | `c.onGold` | Primary button enabled text/icon foreground | Action | `c.onGold` (#FFFFFF) |
| `frontend/lib/ui/components/qd_countdown.dart:142` | `c.gold` | Countdown ring progress arc fill | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/components/qd_icon_tile.dart:54` | `c.gold` | Primary icon tile background | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/components/qd_icon_tile.dart:54` | `c.onGold` | Primary icon tile foreground | Brand accent | `c.onGold` (#FFFFFF) |
| `frontend/lib/ui/components/qd_map_overlay.dart:25` | `c.gold` | Map center pin head container fill | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/components/qd_option_card.dart:33` | `c.goldTint` | Selected option card background fill | Action / State | `c.goldTint` (#E3F4F3) |
| `frontend/lib/ui/components/qd_otp_input.dart:116` | `c.gold` | Active focused OTP cell border | Action / Focus | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/components/qd_otp_input.dart:135` | `c.goldTint` | Active focused OTP cell background fill | Action / Focus | `c.goldTint` (#E3F4F3) |
| `frontend/lib/ui/components/qd_progress.dart:85` | `c.gold` | Current timeline step dot fill | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/components/qd_rings.dart:30` | `c.goldTint` | Outer ring background | Brand accent | `c.goldTint` (#E3F4F3) |
| `frontend/lib/ui/components/qd_rings.dart:33` | `c.goldTint`, `c.gold` | Middle ring background lerp | Brand accent | `c.goldTint`, `c.gold` |
| `frontend/lib/ui/components/qd_rings.dart:36` | `c.gold` | Center ring disc fill | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/components/qd_rings.dart:37` | `c.onGold` | Center ring icon | Brand accent | `c.onGold` (#FFFFFF) |
| `frontend/lib/ui/components/qd_route_lines.dart:48` | `c.gold` | Route drop-off stop indicator fill | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/components/qd_route_stops.dart:65` | `c.gold` | Route stop drop-off indicator fill | Brand accent | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/gallery/qd_gallery_screen.dart:562` | `QdIconTileTone.gold` | Gallery icon tile demo | Action / Demo | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/qd_theme.dart:15` | `c.gold` | ColorScheme.primary | Action | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/qd_theme.dart:16` | `c.onGold` | ColorScheme.onPrimary | Action | `c.onGold` (#FFFFFF) |
| `frontend/lib/ui/qd_theme.dart:17` | `c.goldTint` | ColorScheme.primaryContainer | Action / State | `c.goldTint` (#E3F4F3) |
| `frontend/lib/ui/qd_theme.dart:102` | `c.gold` | FilledButtonThemeData.backgroundColor | Action | `c.gold` (Nile #0E7C7B) |
| `frontend/lib/ui/qd_theme.dart:103` | `c.onGold` | FilledButtonThemeData.foregroundColor | Action | `c.onGold` (#FFFFFF) |

### Hardcoded color audit
| File:Line | Old Value | What it paints | New Value |
| :--- | :--- | :--- | :--- |
| `frontend/lib/services/local_notifications.dart:130` | `Color(0xFFFFC107)` | Notification accent color | `Color(0xFF0E7C7B)` (Waddify Nile) |
| `frontend/lib/features/courier/active_job_page.dart:413` | `Color(0x260D1321)` | Active job status pill shadow | `Color(0x2610233F)` (Ink 15% shadow) |

## WCAG AA Contrast Verification

### Light Palette (all >= 4.5:1 body text)
| Pair Label | Foreground | Background | Ratio | Status |
| :--- | :--- | :--- | :--- | :--- |
| primary on surface | `#10233F` (Ink) | `#FFFFFF` | 15.74:1 | PASS (AAA) |
| primary on subtle | `#10233F` (Ink) | `#F7F6F2` (Sand) | 14.55:1 | PASS (AAA) |
| primary on muted | `#10233F` (Ink) | `#F3F4F6` | 14.30:1 | PASS (AAA) |
| secondary on surface | `#4B5563` | `#FFFFFF` | 7.56:1 | PASS (AAA) |
| secondary on subtle | `#4B5563` | `#F7F6F2` (Sand) | 6.99:1 | PASS (AA) |
| secondary on muted | `#4B5563` | `#F3F4F6` | 6.87:1 | PASS (AA) |
| on gold (CTA text) | `#FFFFFF` | `#0E7C7B` (Nile) | 5.01:1 | PASS (AA) |
| primary on gold tint | `#10233F` (Ink) | `#E3F4F3` | 13.87:1 | PASS (AAA) |
| secondary on gold tint | `#4B5563` | `#E3F4F3` | 6.66:1 | PASS (AA) |
| neutral on gold tint | `#374151` | `#E3F4F3` | 9.08:1 | PASS (AAA) |
| success chip | `#15803D` | `#DCFCE7` | 4.57:1 | PASS (AA) |
| warning chip | `#B45309` | `#FEF3C7` | 4.51:1 | PASS (AA) |
| danger chip | `#BA1A1A` | `#FEE2E2` | 5.29:1 | PASS (AA) |
| neutral chip | `#374151` | `#F3F4F6` | 9.37:1 | PASS (AAA) |
| danger on surface | `#BA1A1A` | `#FFFFFF` | 6.46:1 | PASS (AA) |
| disabled button | `#374151` | `#E5E7EB` | 8.33:1 | PASS (AAA) |
| avatar initial (Sun on Ink) | `#F2A541` (Sun) | `#10233F` (Ink) | 7.67:1 | PASS (AAA) |
| on sun (Ink on Sun) | `#10233F` (Ink) | `#F2A541` (Sun) | 7.67:1 | PASS (AAA) |
| on rating | `#0D1321` | `#FFC107` | 11.38:1 | PASS (AAA) |
| warning banner | `#10233F` (Ink) | `#FEF3C7` | 14.13:1 | PASS (AAA) |
| danger banner | `#10233F` (Ink) | `#FEE2E2` | 12.88:1 | PASS (AAA) |
| success on tone card | `#10233F` (Ink) | `#DCFCE7` | 14.33:1 | PASS (AAA) |
| success text on surface | `#15803D` | `#FFFFFF` | 5.02:1 | PASS (AA) |
| warning text on surface | `#B45309` | `#FFFFFF` | 5.02:1 | PASS (AA) |
| struck old price | `#5C6470` | `#FFFFFF` | 5.98:1 | PASS (AA) |

### Dark Palette (all >= 4.5:1 body text)
| Pair Label | Foreground | Background | Ratio | Status |
| :--- | :--- | :--- | :--- | :--- |
| primary on surface | `#F9FAFB` | `#10233F` (Ink) | 15.06:1 | PASS (AAA) |
| primary on subtle | `#F9FAFB` | `#172C4C` | 13.39:1 | PASS (AAA) |
| primary on muted | `#F9FAFB` | `#20385E` | 11.23:1 | PASS (AAA) |
| secondary on surface | `#9CA3AF` | `#10233F` (Ink) | 6.20:1 | PASS (AA) |
| secondary on subtle | `#9CA3AF` | `#172C4C` | 5.51:1 | PASS (AA) |
| secondary on muted | `#9CA3AF` | `#20385E` | 4.62:1 | PASS (AA) |
| on gold (Ink on Nile Light) | `#10233F` (Ink) | `#2FB5B3` (Nile Light) | 6.28:1 | PASS (AA) |
| primary on gold tint | `#F9FAFB` | `#0E3B43` | 11.65:1 | PASS (AAA) |
| secondary on gold tint | `#9CA3AF` | `#0E3B43` | 4.79:1 | PASS (AA) |
| neutral on gold tint | `#D1D5DB` | `#0E3B43` | 8.26:1 | PASS (AAA) |
| success chip | `#86EFAC` | `#14532D` | 6.49:1 | PASS (AA) |
| warning chip | `#FCD34D` | `#78350F` | 6.29:1 | PASS (AA) |
| danger chip | `#FCA5A5` | `#7F1D1D` | 5.28:1 | PASS (AA) |
| neutral chip | `#D1D5DB` | `#27426D` | 6.83:1 | PASS (AA) |
| danger on surface | `#FCA5A5` | `#10233F` (Ink) | 8.29:1 | PASS (AAA) |
| disabled button | `#D1D5DB` | `#27426D` | 6.83:1 | PASS (AA) |
| avatar initial | `#10233F` | `#F9FAFB` | 15.06:1 | PASS (AAA) |
| warning banner | `#F9FAFB` | `#78350F` | 8.68:1 | PASS (AAA) |
| danger banner | `#F9FAFB` | `#7F1D1D` | 9.59:1 | PASS (AAA) |
| success on tone card | `#F9FAFB` | `#14532D` | 8.72:1 | PASS (AAA) |
| success text on surface | `#86EFAC` | `#10233F` (Ink) | 11.21:1 | PASS (AAA) |
| warning text on surface | `#FCD34D` | `#10233F` (Ink) | 10.92:1 | PASS (AAA) |
| struck old price | `#9CA3AF` | `#10233F` (Ink) | 6.20:1 | PASS (AA) |
| on sun (Ink on Sun) | `#10233F` | `#F2A541` (Sun) | 7.67:1 | PASS (AAA) |
| on rating | `#0D1321` | `#FFC107` | 11.38:1 | PASS (AAA) |

## Changes per commit (message only — NO SHAs)
1. REBRAND-THEME: audit gold use, add rating and sun tokens, repoint rating stars
2. REBRAND-THEME: Waddify palette, Readex Pro font, QdBrandMark, 2.2.0+1, and updated goldens

## Verification
- `flutter analyze` — PASS (No issues found)
- `flutter test` — PASS (1451 tests passed, zero failures)
- `make check` — PASS (scope: docs infra-tests docgen frontend)
- WCAG AA contrast verification: all light and dark text/background pairs pass >= 4.5:1
- Arabic glyph coverage: verified across all 4 weights of Readex Pro against all unique characters in `app_ar.arb` (including shadda, Arabic-Indic digits, ٪, punctuation) — 0 missing characters

## Unverified
- Not run on a physical device at merge time: launcher and themed icons, native and in-app splash, login tile, dark mode, Readex Pro text fit on real screens. Owner device check follows before release (tracker #54).
- Goldens were spot-checked by eye in the owner review (login, home light/dark, rating, courier offer, active order dark, brand gallery), not all 230.
- Owner notes added at merge: app version 2.2.0+1 confirmed by the owner; ADR-0029 §5 small-size threshold lowered to 32 px so the 32 px login tile matches the rule; the task report's "white on Nile 4.56:1" was a typo, the table above (5.01:1) is correct.

## Follow-ups / out-of-lane findings
- Tech debt issue: rename historical token fields across the codebase (`gold` -> `primaryAction` / `nile`, `onGold` -> `onPrimaryAction`, `goldTint` -> `actionTint` / `nileTint`, `navy` -> `ink`, `onNavy` -> `onInk`).

## Open questions
- none
