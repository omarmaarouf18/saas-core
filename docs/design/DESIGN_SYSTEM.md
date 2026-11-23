# Quick Delivery design system — redesign A

This is the design system of the app (FE-DS onward). Since 2.0.0 (FE-CLEANUP)
it is the only one: the old system (`frontend/lib/core/theme.dart`,
`frontend/lib/widgets/`, described in
[docs/frontend/DESIGN_SYSTEM.md](../frontend/DESIGN_SYSTEM.md), now a pointer
here) was deleted with the old screens.

**The theme is app-wide.** `main.dart` sets `MaterialApp.theme: qdLightTheme`
and `darkTheme: qdDarkTheme` (`themeMode` from `ThemeProvider`: light, dark or
system). Every page, dialog, sheet and snackbar gets the `QdColors` theme
extension from there; there are no per-feature theme wrappers any more
(`QdThemeScope`, `CustomerTheme` and `customerRoute` were removed) and pages are
pushed with a plain `MaterialPageRoute`. `QdColors.of(context)` falls back to
the light set only when a bare test app has no Qd theme.

- Approved mockups: [redesign-a/](redesign-a/) (Arabic RTL, 390 px phone). Start
  with [00-SCREEN-MAP.html](redesign-a/00-SCREEN-MAP.html): old screen → new
  screen, known bugs, data gaps.
- Brand source: [docs/design/WADDIFY_BRAND.md](WADDIFY_BRAND.md) and
  [ADR-0029](../adr/0029-rebrand-to-waddify.md) (Waddify palette: Ink `#10233F`,
  Nile `#0E7C7B`, Nile Light `#2FB5B3`, Sun `#F2A541`, Sand `#F7F6F2`). The
  tokens and Readex Pro font were implemented in REBRAND-THEME (#57).
  The historical Quick Delivery identity ([docs/frontend/BRAND_IDENTITY.md](../frontend/BRAND_IDENTITY.md))
  is superseded.
- Code: `frontend/lib/ui/tokens.dart` (tokens), `frontend/lib/ui/qd_theme.dart`
  (`ThemeData`), `frontend/lib/ui/components/` (widgets, all prefixed `Qd`).
- Debug gallery: route `/qd-gallery` (debug builds only) renders every component
  in every state; goldens in `frontend/test/ui/goldens/qd_gallery_*`. Page
  goldens live in `frontend/test/features/**/goldens/`, light AR-RTL / EN-LTR,
  plus one dark golden per role shell and per order / job page
  (`*_dark_en_ltr_360x800.png`).

## Rules

1. **Surfaces are white.** Subtle fills Sand `#F7F6F2` (`fillSubtle`) / `#F3F4F6` (`fillMuted`).
   Borders are 1 px `#E5E7EB`; input borders `#D1D5DB`. Cards use borders, never shadows.
2. **Text is Ink** `#10233F`. Secondary text `#4B5563`, never lighter for body
   text. `#5C6470` is allowed for strike-through prices (`textMuted`); `#9CA3AF`
   for decorative marks (upcoming timeline dot), never for readable copy.
3. **Primary action is Nile `#0E7C7B` (dark Nile Light `#2FB5B3`):** the primary
   button fill (white text on it, 4.56:1 AA), active bottom-nav indicator, selected-option
   tint `#E3F4F3` (`goldTint`), primary service icon tile, and count-down ring.
   Nile is never text on white. Rating stars use the fixed-meaning `rating` token
   (`#FFC107`). Warm accents use Sun `#F2A541` (`sun` / `onSun`).
4. **Status colors:** success `#15803D` on `#DCFCE7`; warning `#B45309` on
   `#FEF3C7`; danger `#BA1A1A` text (on `#FEE2E2` for chips) for cancelled and
   destructive; neutral `#374151` on `#F3F4F6`.
5. **Radii:** 12 inputs / small buttons / icon tiles; 14 primary button and
   banners; 16 cards and list groups; 24 top corners of a sheet; 999 chips.
6. **Spacing:** 4 / 8 / 12 / 16 / 20 / 24. Screen side padding 20.
7. **Type:** Readex Pro, bundled static TTFs (`frontend/assets/fonts/`, weights
   400, 500, 600, 700; SIL OFL 1.1 license next to it), never fetched at runtime.
   Arabic and Latin use the same family.
8. **One primary (Nile) button per screen.** Sentence case everywhere, no ALL
   CAPS, no Title Case in new strings.
9. **Touch targets ≥ 48 dp** (list rows 52–64, primary button 54).
10. **RTL first**, every component also renders LTR. Phone and email fields are
    LTR inside RTL. Use `EdgeInsetsDirectional` / `AlignmentDirectional` only.
11. **Money** is always `<amount> ج.م` (Arabic) / `EGP <amount>` (English) via
    `QdMoney` (intl), never `$` or a bare number.
12. **Every user-visible string** in a component comes from ARB (EN + Egyptian
    Arabic). Component strings are prefixed `qd` in the ARB files.

## Tokens

### Color — light (`QdColors.light`)

| Token | Hex | Use |
|---|---|---|
| `surface` | `#FFFFFF` | screens, cards, sheets |
| `fillSubtle` | `#F7F6F2` | highlighted card (Sand; current order, price summary) |
| `fillMuted` | `#F3F4F6` | icon tile, segmented track, neutral chip, divider in groups |
| `border` | `#E5E7EB` | card / group / nav borders, track of progress bars |
| `borderInput` | `#D1D5DB` | text field, secondary button, sheet handle |
| `textPrimary` | `#10233F` | all primary text, icons (Ink) |
| `textSecondary` | `#4B5563` | secondary text, inactive nav label |
| `textMuted` | `#5C6470` | strike-through old price only |
| `decorative` | `#9CA3AF` | upcoming timeline dot only |
| `gold` | `#0E7C7B` | primary action fill (Nile); historical field name |
| `onGold` | `#FFFFFF` | text and icons on primary action fill |
| `goldTint` | `#E3F4F3` | selected option background tint |
| `navy` | `#10233F` | avatar fill, trust surfaces (Ink); historical field name |
| `onNavy` | `#F2A541` | warm accent on dark surfaces (Sun); historical field name |
| `rating` | `#FFC107` | fixed-meaning rating star color |
| `onRating` | `#0D1321` | text on rating fill |
| `sun` | `#F2A541` | warm brand accent (Sun) |
| `onSun` | `#10233F` | text on warm accent (Ink) |
| `success` / `successBg` | `#15803D` / `#DCFCE7` | success chip |
| `warning` / `warningBg` | `#B45309` / `#FEF3C7` | warning chip, warning banner |
| `danger` / `dangerBg` | `#BA1A1A` / `#FEE2E2` | danger text, danger chip / banner |
| `neutral` / `neutralBg` | `#374151` / `#F3F4F6` | neutral chip, disabled button text |
| `disabledFill` | `#E5E7EB` | disabled primary button |
| `scrim` | `0x6610233F` | modal scrim overlay |

### Color — dark (`QdColors.dark`)

Wired app-wide since FE-CLEANUP (`qdDarkTheme`, picked by the app's theme
mode). Derived from Ink `#10233F`. The pairs in use are asserted in
`frontend/test/ui/tokens_test.dart` and pass WCAG AA (≥ 4.5:1).

| Token | Hex |
|---|---|
| `surface` | `#10233F` |
| `fillSubtle` | `#172C4C` |
| `fillMuted` | `#20385E` |
| `border` | `#27426D` |
| `borderInput` | `#385685` |
| `textPrimary` | `#F9FAFB` |
| `textSecondary` | `#9CA3AF` |
| `textMuted` | `#9CA3AF` |
| `decorative` | `#6B7280` |
| `gold` / `onGold` | `#2FB5B3` (Nile Light) / `#10233F` (Ink) |
| `goldTint` | `#0E3B43` |
| `navy` / `onNavy` | `#F9FAFB` / `#10233F` |
| `rating` / `onRating` | `#FFC107` / `#0D1321` |
| `sun` / `onSun` | `#F2A541` / `#10233F` |
| `success` / `successBg` | `#86EFAC` / `#14532D` |
| `warning` / `warningBg` | `#FCD34D` / `#78350F` |
| `danger` / `dangerBg` | `#FCA5A5` / `#7F1D1D` |
| `neutral` / `neutralBg` | `#D1D5DB` / `#27426D` |
| `disabledFill` | `#27426D` |
| `scrim` | `0x99000000` |

### Spacing (`QdSpace`)

`x1 = 4`, `x2 = 8`, `x3 = 12`, `x4 = 16`, `x5 = 20`, `x6 = 24`. Screen gutter
`QdSpace.gutter = 20`.

### Radii (`QdRadius`)

`sm = 12` (input, small button, icon tile), `button = 14` (primary button,
banner), `card = 16` (card, list group), `sheet = 24` (sheet top corners),
`pill = 999` (chip).

### Type (`QdText`)

| Style | Size / weight | Use |
|---|---|---|
| `screenTitle` | 26 bold (28 on auth screens via `screenTitleLg`) | `h1` on a tab root |
| `sheetTitle` | 22 bold | sheet / state hero title |
| `header` | 18 bold | app-bar title on pushed screens |
| `rowTitle` | 16 semibold | service row, list tile title |
| `rowTitleSm` | 15 semibold | card title, list row |
| `body` | 14 regular | body copy, labels |
| `secondary` | 13 regular, `textSecondary` | subtitles, notes |
| `caption` | 12 regular, `textSecondary` | captions, nav labels |
| `chip` | 12 semibold | status chips |
| `amountLg` | 24 bold | price hero |

Line height 1.4 for Arabic legibility (mockups use 1.35–1.6).

## Components

All under `frontend/lib/ui/components/`. Each has a widget test in
`frontend/test/ui/`.

| Component | What it is | Mockups |
|---|---|---|
| `QdButton` | primary gold / secondary outlined / text / destructive text; loading, disabled, full width, small | every screen; A-Login, C-Offer, A-Book (disabled), A-Searching (destructive), A-Owner (small) |
| `QdTextField` | label above, hint, error, password toggle, LTR field in RTL | A-Login, A-Signup, O-Service, A-Picker |
| `QdCard` | bordered 16-radius container, optional fill and tap | A-Home, A-Orders, A-Negotiate, A-Searching, C-Offer |
| `QdListGroup` + `QdListTile` | bordered group, inset dividers; tile with leading icon / avatar, title, subtitle, trailing value / chevron / switch / badge | A-Settings, A-Owner, O-Team, A-Book |
| `QdStatusChip` + `qdJobStatusChips` | tone chip; single job-status → label + tone mapping | A-Home, A-Orders, A-Owner, O-Team, O-Orders, A-Tickets, O-Recon, A-Courier |
| `QdSegmented` | 2–3 option tabs, no mid-word wrap | A-Orders, O-Team, A-Tickets, O-Orders |
| `QdBottomNav` | 3–4 items, gold indicator, semantics | A-Home, A-Orders, A-Settings, A-Owner, O-Team, C-History |
| `QdRouteLines` | pickup ring / drop-off square with addresses | A-Orders, C-Offer, A-Searching, A-Book, A-Courier |
| `QdStepProgress` | segmented bar, N steps | A-Home |
| `QdTimeline` | vertical done / current / upcoming with time | A-Track |
| `QdAvatarInitial` | circle with one initial; navy or muted | A-Settings, A-Track, A-Negotiate, A-Owner, O-Team |
| `QdSectionHeader` | title + optional action link | A-Owner, A-Settings, A-Orders |
| `QdEmptyState` / `QdErrorState` | icon, title, body, optional action / retry | A-Tickets (empty), pattern for all lists |
| `QdBanner` | info / warning / danger with optional action link | C-History (KYC pending); suspended, location denied, offline |
| `QdCountdown` | mm:ss + shrinking bar or ring from an expiry, fires on expiry | C-Offer (ring), A-Negotiate (bar) |
| `QdBottomSheet` | handle, title, content, one primary action | A-Track, O-Fleet; add-courier sheet (O-Team) |
| `QdMoney` | EGP formatter, AR / EN | every price |
| `QdBrandMark` | Waddify 55° diving pigeon mark; full / onDark / mono variants | Splash, Login, debug gallery |

## Job status chips

One mapping, `qdJobStatusChips(status, cancellationRequestStatus)` in
`frontend/lib/ui/components/qd_status_chip.dart`. Unknown status → neutral
chip with "Unknown status", never a crash. A pending cancellation request is an
extra warning chip shown after the status chip.

| Backend status | EN | AR | Tone |
|---|---|---|---|
| `pending` | Waiting for courier | مستني مندوب | warning |
| `pending_dispatch` | Finding a courier | بندور على مندوب | warning |
| `unavailable` | No courier available | مفيش مندوب متاح | danger |
| `awaiting_price_response` | New price offered | فيه عرض سعر | warning |
| `assigned` | Courier assigned | المندوب قبل | success |
| `active` | On the way | في الطريق | success |
| `completed` | Delivered | اتسلم | neutral |
| `cancelled` / `canceled` | Cancelled | اتلغى | danger |
| `escrow_reconciliation_required` / `reconciliation_required` | Under review | بيتراجع | warning |
| `cancellation_request_status == "pending"` | Cancellation requested | طلب إلغاء | warning |
| anything else | Unknown status | حالة مش معروفة | neutral |

## Contrast

Ratios computed with the WCAG 2.1 relative-luminance formula. Every pair used for
text under 24 px is ≥ 4.5:1.

| Text | Background | Ratio | Where |
|---|---|---|---|
| `#10233F` (Ink) | `#FFFFFF` | 15.06 | body text |
| `#10233F` | `#F7F6F2` (Sand) | 13.92 | text on subtle card |
| `#10233F` | `#F3F4F6` | 13.68 | segmented selected / tile |
| `#4B5563` | `#FFFFFF` | 7.56 | secondary text |
| `#4B5563` | `#F7F6F2` | 6.99 | secondary on subtle card |
| `#4B5563` | `#F3F4F6` | 6.87 | segmented unselected |
| `#5C6470` | `#FFFFFF` | 5.98 | struck old price |
| `#FFFFFF` | `#0E7C7B` (Nile) | 4.56 | primary action button |
| `#10233F` | `#E3F4F3` | 12.87 | selected option tint |
| `#10233F` | `#F2A541` (Sun) | 7.67 | warm accent text / icon |
| `#0D1321` | `#FFC107` (rating) | 11.38 | rating star fill |
| `#15803D` | `#DCFCE7` | 5.02 | success chip |
| `#B45309` | `#FEF3C7` | 5.02 | warning chip |
| `#BA1A1A` | `#FEE2E2` | 5.29 | danger chip |
| `#374151` | `#F3F4F6` | 9.37 | neutral chip |
| `#BA1A1A` | `#FFFFFF` | 6.46 | destructive text button, field error |
| `#374151` | `#E5E7EB` | 8.33 | disabled primary button |
| `#F2A541` | `#10233F` | 7.67 | avatar initial / sun on ink |
| `#10233F` | `#FEF3C7` | 13.53 | warning banner text |
| `#10233F` | `#FEE2E2` | 12.33 | danger banner text |
| `#F9FAFB` | `#10233F` | 15.06 | dark: text on surface |
| `#F9FAFB` | `#172C4C` | 13.39 | dark: text on subtle |
| `#9CA3AF` | `#10233F` | 6.20 | dark: secondary |
| `#9CA3AF` | `#172C4C` | 5.51 | dark: secondary on card |
| `#10233F` | `#2FB5B3` (Nile Light) | 6.28 | dark: text on gold |
| `#86EFAC` | `#14532D` | 6.49 | dark: success chip |
| `#FCD34D` | `#78350F` | 6.29 | dark: warning chip |
| `#FCA5A5` | `#7F1D1D` | 5.28 | dark: danger chip |
| `#D1D5DB` | `#27426D` | 6.83 | dark: neutral chip |

The success (4.57) and warning (4.51) chips are the tightest pairs. Do not
lighten their text or darken their fills.
