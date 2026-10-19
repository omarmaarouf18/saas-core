# Quick Delivery design system — redesign A

This is the design system for the rebuilt UI layer (FE-DS onward). It replaces
the look described in [docs/frontend/DESIGN_SYSTEM.md](../frontend/DESIGN_SYSTEM.md)
screen by screen as FE-CUST-1, FE-CUST-2, FE-COURIER and FE-OWNER land. Until
then both systems live side by side: the old one in `frontend/lib/core/theme.dart`
+ `frontend/lib/widgets/`, the new one in `frontend/lib/ui/`.

- Approved mockups: [redesign-a/](redesign-a/) (Arabic RTL, 390 px phone). Start
  with [00-SCREEN-MAP.html](redesign-a/00-SCREEN-MAP.html): old screen → new
  screen, known bugs, data gaps.
- Brand source: [docs/frontend/BRAND_IDENTITY.md](../frontend/BRAND_IDENTITY.md)
  (navy `#0D1321`, gold `#FFC107`, success / warning / danger).
- Code: `frontend/lib/ui/tokens.dart` (tokens), `frontend/lib/ui/qd_theme.dart`
  (`ThemeData`), `frontend/lib/ui/components/` (widgets, all prefixed `Qd`).
- Debug gallery: route `/qd-gallery` (debug builds only) renders every component
  in every state; goldens in `frontend/test/goldens/qd_gallery_*`.

## Rules

1. **Surfaces are white.** Subtle fills `#F9FAFB` / `#F3F4F6`. Borders are 1 px
   `#E5E7EB`; input borders `#D1D5DB`. Cards use borders, never shadows.
2. **Text is navy** `#0D1321`. Secondary text `#4B5563`, never lighter for body
   text. `#6B7280` / `#9CA3AF` are allowed only for strike-through prices and
   decorative marks (upcoming timeline dot), never for readable copy.
3. **Gold `#FFC107` is only:** the primary button fill (navy text on it), the
   active bottom-nav indicator, the selected-option tint `#FFF8E1`, the primary
   service icon tile, and the count-down ring. Gold is never text on white.
4. **Status colors:** success `#15803D` on `#DCFCE7`; warning `#B45309` on
   `#FEF3C7`; danger `#BA1A1A` text (on `#FEE2E2` for chips) for cancelled and
   destructive; neutral `#374151` on `#F3F4F6`.
5. **Radii:** 12 inputs / small buttons / icon tiles; 14 primary button and
   banners; 16 cards and list groups; 24 top corners of a sheet; 999 chips.
6. **Spacing:** 4 / 8 / 12 / 16 / 20 / 24. Screen side padding 20.
7. **Type:** IBM Plex Sans Arabic, bundled (`frontend/assets/fonts/`, OFL
   license next to it), never fetched at runtime. Latin uses the same family.
8. **One primary (gold) button per screen.** Sentence case everywhere, no ALL
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
| `fillSubtle` | `#F9FAFB` | highlighted card (current order, price summary) |
| `fillMuted` | `#F3F4F6` | icon tile, segmented track, neutral chip, divider in groups |
| `border` | `#E5E7EB` | card / group / nav borders, track of progress bars |
| `borderInput` | `#D1D5DB` | text field, secondary button, sheet handle |
| `textPrimary` | `#0D1321` | all primary text, icons |
| `textSecondary` | `#4B5563` | secondary text, inactive nav label |
| `textMuted` | `#6B7280` | strike-through old price only |
| `decorative` | `#9CA3AF` | upcoming timeline dot only |
| `gold` | `#FFC107` | primary button, nav indicator, primary icon tile, countdown |
| `onGold` | `#0D1321` | text and icons on gold |
| `goldTint` | `#FFF8E1` | selected option background |
| `navy` | `#0D1321` | avatar fill, done timeline dot, route marks, progress fill |
| `onNavy` | `#FFC107` | initial on navy avatar |
| `success` / `successBg` | `#15803D` / `#DCFCE7` | success chip |
| `warning` / `warningBg` | `#B45309` / `#FEF3C7` | warning chip, warning banner |
| `danger` / `dangerBg` | `#BA1A1A` / `#FEE2E2` | danger text, danger chip / banner |
| `neutral` / `neutralBg` | `#374151` / `#F3F4F6` | neutral chip, disabled button text |
| `disabledFill` | `#E5E7EB` | disabled primary button |

### Color — dark (`QdColors.dark`)

Defined but **not wired into the app** in FE-DS. Same gold rules.

| Token | Hex |
|---|---|
| `surface` | `#0D1321` |
| `fillSubtle` | `#161D2E` |
| `fillMuted` | `#1F2738` |
| `border` | `#273047` |
| `borderInput` | `#3A4560` |
| `textPrimary` | `#F9FAFB` |
| `textSecondary` | `#9CA3AF` |
| `gold` / `onGold` | `#FFC107` / `#0D1321` |
| `goldTint` | `#3A2E0A` |
| `navy` / `onNavy` | `#F9FAFB` / `#0D1321` |
| `success` / `successBg` | `#86EFAC` / `#14532D` |
| `warning` / `warningBg` | `#FCD34D` / `#78350F` |
| `danger` / `dangerBg` | `#FCA5A5` / `#7F1D1D` |
| `neutral` / `neutralBg` | `#D1D5DB` / `#273047` |

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
| `#0D1321` | `#FFFFFF` | 18.55 | body text |
| `#0D1321` | `#F9FAFB` | 17.75 | text on subtle card |
| `#0D1321` | `#F3F4F6` | 16.85 | segmented selected / tile |
| `#4B5563` | `#FFFFFF` | 7.56 | secondary text |
| `#4B5563` | `#F9FAFB` | 7.23 | secondary on subtle card |
| `#4B5563` | `#F3F4F6` | 6.87 | segmented unselected |
| `#0D1321` | `#FFC107` | 11.38 | primary button |
| `#0D1321` | `#FFF8E1` | 17.46 | selected option |
| `#15803D` | `#DCFCE7` | 4.57 | success chip |
| `#B45309` | `#FEF3C7` | 4.51 | warning chip |
| `#BA1A1A` | `#FEE2E2` | 5.29 | danger chip |
| `#374151` | `#F3F4F6` | 9.37 | neutral chip |
| `#BA1A1A` | `#FFFFFF` | 6.46 | destructive text button, field error |
| `#374151` | `#E5E7EB` | 8.33 | disabled primary button |
| `#FFC107` | `#0D1321` | 11.38 | avatar initial |
| `#0D1321` | `#FEF3C7` | 16.66 | warning banner text |
| `#0D1321` | `#FEE2E2` | 15.18 | danger banner text |
| `#F9FAFB` | `#0D1321` | 17.75 | dark: text |
| `#9CA3AF` | `#0D1321` | 7.31 | dark: secondary |
| `#9CA3AF` | `#161D2E` | 6.62 | dark: secondary on card |
| `#86EFAC` | `#14532D` | 6.49 | dark: success chip |
| `#FCD34D` | `#78350F` | 6.29 | dark: warning chip |
| `#FCA5A5` | `#7F1D1D` | 5.28 | dark: danger chip |
| `#D1D5DB` | `#273047` | 8.91 | dark: neutral chip |

The success (4.57) and warning (4.51) chips are the tightest pairs. Do not
lighten their text or darken their fills.
