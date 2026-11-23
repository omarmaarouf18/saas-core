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

## Changes per commit (message only — NO SHAs)
1. REBRAND-THEME: audit gold use, add rating and sun tokens, repoint rating stars

## Verification
- `flutter test test/ui/tokens_test.dart test/features/customer/order/rating_page_test.dart` — PASS
- `make check` — PASS

## Unverified
- none

## Follow-ups / out-of-lane findings
- Tech debt issue: rename historical token fields across the codebase (`gold` -> `primaryAction` / `nile`, `onGold` -> `onPrimaryAction`, `goldTint` -> `actionTint` / `nileTint`, `navy` -> `ink`, `onNavy` -> `onInk`).

## Open questions
- none
