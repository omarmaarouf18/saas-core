# UI Visual Audit — Token Compliance, Reuse & Identity Gaps (2026-09)

> **Date**: September 26, 2026
> **Branch**: `logic-exploitation`
> **Method**: Static read-through of `docs/frontend/DESIGN_SYSTEM.md` (full) + `frontend/lib/core/theme.dart` (full, 613 lines) + targeted `grep` sweeps over all 31 production screens and 34→36 shared widgets + two parallel subagent consistency sweeps + golden-suite verification (`flutter test test/golden_screens_test.dart`, local Flutter 3.44.6 == CI pin).
> **Scope**: visual design ONLY — colors/spacing/radius/elevation/motion/iconography/typography token compliance, shared-widget reuse, cross-screen visual consistency, identity gaps. Behavior, loading/error/confirmation logic explicitly OUT (closed pass: `UI_UX_AUDIT_2026-09.md`, 62/62 fixed; `UX_PATTERNS.md` Rules 1–21 not re-flagged here).
> **Palette constraint**: `AppColors` values are FROZEN. Every fix below works within existing tokens; inconsistent *usage* is flagged, token values never changed (verified: `git diff` on `theme.dart` adds one scale step, alters zero color values).
> **stitch-export exclusion**: `design/stitch-export/` (nocturne_amber-dark, kinetic_logistics-light, etc.) contains exploratory concepts, NOT the shipped identity — ignored throughout; nothing was borrowed from it.

---

## 1. Doc-vs-code drift (DESIGN_SYSTEM.md lags the shipped code)

| # | Drift | Disposition |
|---|---|---|
| D1 | Color table omits the container ramp (`surfaceDim`, `surfaceContainerLowest/Low/Container/High/Highest`), `onPrimaryContainer`/`onSecondaryContainer`/`onErrorContainer`, `background`/`onBackground`, `scrim`, the full `Dark` twin set, and the `AppSemanticColors` extension | **Fixed** — table rows + note added (V4) |
| D2 | Radius table assigns "floating dialogs" to `xl` (24), but EVERY dialog in the app uses `md` (12); large map pickers use `lg` (16) | **Fixed** — doc corrected to the shipped standard: dialogs → `md` row, `lg` keeps large map cards, `xl` is bottom-sheets-only (V4) |
| D3 | Component catalog: 26 of 34 param cells stale (`ConfirmActionDialog.confirmText`→`confirmLabel`, `ListScreenTemplate` itemCount-API, `FormScreenTemplate` children-API, `ThemedEmptyState.action`, `ThemedPanel.backgroundColor`, `StatusBadge`/`StatCard`/`InfoListTile`/`RouteTimeline`/`DashboardScreenTemplate`/`RatingSummaryCard`/button/dialog params, `EmailChangeDialog`/`DepositFundsDialog`/`PayoutRequestDialog` phantom params, `CreateTicketDialog` reference params, `InfoAlertDialog.buttonText`, `KycRejectionDialogHost` reason-API); catalog count said 34 after 2 widgets were added (CI `TestDocsCountsVerification` failed the push until fixed) | **Fixed** — all 26 rows corrected, count 34→36, 2 new rows (V4) |
| D4 | Debt table references deleted `service_screen.dart` (2 rows) | **Fixed** — rows dropped, 55→53 renumbered (V4) |
| D5 | Typography table omits `labelUppercase` + `uppercaseLabel()` helper despite theme.dart mandating them as the ONLY sanctioned uppercase path | **Fixed** — rows added (V4) |
| D6 | Icon scale jumps 16→24→32 while the codebase consistently needs in-between sizes (35× `size: 20`, 22× `size: 18`) | **Fixed (gap token)** — `AppIconSize.smMd = 20.0` added (mirrors `AppRadius.smMd` precedent), all 38 `size: 20` sites migrated value-identically (V1) |

## 2. Token-compliance findings (all value-identical, zero golden churn)

| # | Finding | Sites | Disposition |
|---|---|---|---|
| V-T1 | Raw icon sizes with token equivalents (`14→xs`, `16→sm`, `24→md`, `32→lg`, `48→xl`) | 39 sites across 20 files (enumerated in commit) | **Fixed** (V1) |
| V-T2 | `size: 20` with no token | 38 sites incl. shared `PrimaryButton`/`SecondaryButton`/`InfoListTile` icons | **Fixed** via D6 `smMd` (V1) |
| V-T3 | `Colors.white` map-marker border | `owner_fleet_map_screen.dart:281` | **Fixed** → `AppColors.onPrimary` (same `#FFFFFF`) (V1) |
| V-T4 | `AppColors.surface` as map-pin border color | `customer_job_map_screen.dart:193,254` | **Fixed** → `AppColors.onPrimary` (same value, dark-proof semantics; map canvas stays light so pins read identically) (V1) |
| V-T5 | Raw `SizedBox(2/4)` | `employee_jobs_screen.dart:529`, `ticket_chat_screen.dart:370,379,394,444` | **Fixed** → `xxs`/`xs` (V1) |
| V-T6 | Raw `vertical: 2` tag paddings | `notifications_screen.dart` type tag, `customer_marketplace_screen.dart` category tag, `owner_fleet_map_screen.dart:383` + `wallet_screen.dart:573` count chips (caught by the new compliance test mid-task) | **Fixed** → `xxs` (V1) |
| V-T7 | Token arithmetic (`AppSpacing.xs / 2`) | `job_status_screen.dart:1346` | **Fixed** → `xxs` (V1) |
| V-T8 | Raw 300ms durations / `Curves.easeInOut` with token equivalents | `employee_screen.dart:322-323`, `ticket_chat_screen.dart:172-173`, `themed_panel.dart:161` | **Fixed** → `durationMedium`/`curveStateChange` (V1) |
| V-T9 | `StatusBadge` hand-rolled `.toUpperCase()` (2 sites) against the theme.dart mandate | `status_badge.dart:173,230` | **Fixed** → `uppercaseLabel()` helper, output-identical (V1) |
| V-T10 | Custom scrim shadows bypassing `AppElevation` (chat input, chat bubble, job-map sheet) | 3 sites | **Documented exception** — all use sanctioned `AppColors.scrim`; geometries are upward/top-edge with no token equivalent; single shared token cannot fit three geometries |
| V-T11 | `horizontal: 6` count-chip paddings (no token) | `owner_fleet_map_screen.dart:381`, `wallet_screen.dart:572` | **Documented remainder** — vertical halves fixed (V-T6); 6px horizontal has no token and is left raw rather than inventing a one-off token |
| V-T12 | Icon sizes 18/22/28/36 with no token (22 + 6 + 2 + 3 sites) | widespread (button/tile/status/file icons) | **Open proposal** — snap to `smMd` (20) in a future visual pass WITH golden regen; deliberately NOT snuck into this pixel-safe batch |

Verified clean (zero remaining): raw `Color(0x`, bare palette `Colors.*` (only sanctioned `Colors.transparent` per the doc's own Pattern-1 snippet), raw `BorderRadius.circular(n)`, `fontSize:`, `TextStyle(`, `withOpacity`, `TextButton(`, `Card(`, `Chip(`, `Scaffold(`/`AppBar(` in screens (100% AppShell/templates), skeleton bypass (only sanctioned shimmer + pulse dot), `showModalBottomSheet` (zero uses).

## 3. Reuse findings (DESIGN_SYSTEM.md rule #2)

| # | Finding | Disposition |
|---|---|---|
| V-R1 | Location-picker dialog shell copy-pasted ×4 (home, marketplace ×2, owner-config) — same width-cap formula, `lg` radius, `md` inset/padding, title row, `md`-clipped map, confirm button | **Fixed** — new shared `LocationPickerDialog` (−300 lines), per-site keys preserved, owner-config size normalized to majority (V2) |
| V-R2 | Bounded busy spinners hand-rolled ×5/3 sizes while `ThemedLoadingIndicator` cannot serve small bounds (Rule 4 size exception) | **Fixed** — new shared `ThemedInlineSpinner` (`size`/`color`/size-ruled strokeWidth), adopted at all 6 sites incl. S10 progress (V2) |
| V-R3 | Marketplace unread badge raw `ClipRRect+ColoredBox` vs `ThemedPanel` badges on home/customer-home/employee-home | **Fixed** — rebuilt on `ThemedPanel`, pixel-parity (V1) |
| V-R4 | Subscription `availablePlansHeader` raw `Text` — the only top-level section title bypassing `ThemedSectionHeader` (19 uses elsewhere) | **Fixed** — adopted, pixel-identical (V1) |
| V-R5 | Fleet-map filter pills hand-roll the `PillFilterBar` pattern (own counts, `GestureDetector` without ripple, `labelMd` vs `labelLg`, raw 6/2 count padding) | **Documented intentional variant** — floating map-overlay styling (selected `primary`, unselected `surface`) differs deliberately from the bar's surface aesthetic; adopting would restyle the overlay. Count padding halves fixed (V-T6/V-T11) |
| V-R6 | 4 ad-hoc `CircleAvatar`s bypassing `EntityAvatar` (marketplace category tile, job-status placeholder, my-account initial, notification type tile) | **Documented** — category/type tiles are not person avatars (different semantics); my-account single-initial differs from the 2-char rule (visual change, deferred with V-T12 class) |
| V-R7 | Booking `_BookingDialog` raw `AlertDialog` | **OK as-is** — single-use rich dialog, follows dialog styling (surface/`md`/titleMd) |
| V-R8 | Inline spinner sizes now unified; `ThemedInlineSpinner` demoed in `component_library_screen.dart` Loading States | **Fixed** (V2 follow-up) |

## 4. Cross-screen consistency (subagent-verified, suggestions unless noted)

| # | Finding | Disposition |
|---|---|---|
| V-C1 | History-card radius/padding matrix: 8 vs 12 vs 16 radius, 12/16/24/32 padding, wrapped-vs-bare empties, 4 outer-spacing conventions across 5 list screens | **Suggestion** — per-screen designs are individually coherent; unifying needs design sign-off + mass golden regen. NOT restyled here |
| V-C2 | Money formatting: `titleMd` vs `bodyMd` vs `labelLg`, semantic vs `primary` vs `onSurface`, signed vs unsigned, `toFixed(0)` vs `toFixed(2)` ( incl. `toFixed(0)` vs `toFixed(2)` on the SAME employee-history card) | **Attempted then REVERTED** — the `toFixed(2)` fix exposed a genuine 70px metrics-row overflow at 360dp; the `Flexible`+ellipsis rescue was then proven (via golden diff) to TRUNCATE previously-fitting labels — rejected. Proper fix needs a metrics-row redesign; recorded here as deferred with rationale, not silently dropped |
| V-C3 | Timestamp formatting: `labelMd` full datetime vs `caption` time-only vs absent | **Suggestion** — propose central `formatMoney`/`formatDateTime` helpers in a follow-up |
| V-C4 | Hero cards: wallet/home share `lg/lg/topAccent:3`; customer-home uses glow/no-accent, subscription no-accent, job-status `md/md` — 4 variants of the dark-hero pattern | **Suggestion** — standardize on the wallet/home treatment or bless variants |
| V-C5 | Subscription tier pill uses `xl` (24) radius vs doc's `lgXl` (20) pill-badge standard | **Suggestion** — one-line snap with 2-golden regen in a visual pass |
| V-C6 | Notifications filter: no counts + capitalized values vs counts + lowercase everywhere else; recon queue hides filters when empty | **Suggestion/observation** — counts are provider data (feature-adjacent); casing is l10n copy |
| V-C7 | `StatusBadge` text sizes (`labelMd`/`labelLg` bold) vs sanctioned `labelUppercase` (10pt) | **Suggestion** — aligning shrinks badge text; needs visual pass with regen. Transform routed through helper meanwhile (V-T9) |
| V-C8 | Dividers inside cards on 2/5 history screens only | **Observation** — both uses token-correct; no action |

## 5. Gaps built (new shared widgets)

- **G1 `LocationPickerDialog`** (`frontend/lib/widgets/location_picker_dialog.dart`): responsive width-cap dialog shell unifying 4 call sites. Tests: `test/location_picker_dialog_test.dart` (4/4).
- **G2 `ThemedInlineSpinner`** (`frontend/lib/widgets/themed_inline_spinner.dart`): bounded square spinner unifying 6 ad-hoc sites. Tests: `test/themed_inline_spinner_test.dart` (3/3).
- Supporting token: `AppIconSize.smMd = 20.0` (+ DESIGN_SYSTEM.md row).

## 6. Better-practice notes (flagged, not built)

- P1: Unify history-card geometry + money/time formatting behind central helpers (V-C1–C3) — design sign-off + golden regen required.
- P2: Bless or unify the 4 hero-card variants (V-C4).
- P3: Snap 18/22/28/36 icon sizes to the scale (V-T12) and tier pill to `lgXl` (V-C5) in one visual pass.
- P4: Align `StatusBadge` text sizing with `labelUppercase` (V-C7).
- P5: Upward-shadow token pair if a 4th custom shadow ever appears (V-T10 stays exception until then).

## 7. Explicitly verified as already-OK

Zero raw `Card`/`Chip`/`TextButton`/`Scaffold`/`AppBar` in screens; zero raw `BorderRadius`/`fontSize`/`TextStyle`/`withOpacity`; zero `showModalBottomSheet`; zero skeleton bypass; `Colors.transparent` only where the doc itself sanctions it; dark-mode discipline via `colorScheme`/`semanticColors` everywhere except map-pin chrome (fixed to semantically-correct identical values); dialogs consistently `md` (doc fixed to match); AppBars 100% template-driven; `component_library_screen.dart` remains the live catalog (spinner demo added).

## 8. Fix→commit map & tally

- V1 token migration (V-T1–V-T9, V-R3, V-R4): fix `9cedc0b` + changelog `203fb40` + `design_token_compliance_test.dart` (5/5, incl. source-scan regression guard)
- V2 shared widgets (G1, G2, V-R1, V-R2, V-R8): fix `4951fe4` + changelog `d5fa4f1` (dialog 4/4 + spinner 3/3 tests)
- V3 attempted decimals fix (V-C2): **reverted** — `toFixed(2)` overflows the metrics row; `Flexible` rescue truncates fitting labels (proven by golden diff, then dropped; no such commit survives)
- V4 docs (D1–D6): docs commit + changelog commit (this pass)
- Full suite 695+12 new tests green via pre-push gate; goldens byte-identical except intentional component-library addition (registry below).

**Tally**: 9 fixed findings groups (V-T1–V-T9 minus documented remainders, V-R1–V-R4, V-R8, D1–D6, G1–G2) + 1 reverted-with-rationale (V-C2) + 9 documented suggestions/observations (V-T10–V-T12, V-R5–V-R7, V-C1, V-C3–V-C8, P1–P5). Palette: zero token values changed (one scale step added). stitch-export: untouched and unborrowed-from.
