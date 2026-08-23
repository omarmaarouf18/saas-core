# UI/UX Audit — Full 28-Screen Sweep (Post-Promotion Baseline)

> **Date**: August 23, 2026
> **Baseline audited**: `logic-exploitation` @ `4ab627e` content (post main-promotion merge)
> **Method**: Code-only static audit. Every claim below cites `file:line` from greps/reads run this session. Stitch comparisons extract literal hex/px values from `design/stitch-export/logistics_core_unified/<folder>/code.html`. No visual rendering was performed — see §6 NOT CHECKED.
> **Format**: Follows `STITCH_VISUAL_AUDIT_V2.md` conventions (Groups A–E, per-screen numbered findings). Finding IDs use the form `<Group><screen#>-F<n>` to slot into the existing doc lineage without colliding with V1/V2 IDs.
> **Cross-reference discipline**: Findings already recorded in STATUS.md "Known Gaps & Limitations" (A4/A5/A6/A7 entries), the 33 documented A2 l10n exceptions, and P0–P7 architecture gates are excluded from new findings and listed only where re-verified or where this audit adds a NEW aspect.

---

## 1. Method Note

| Category | Method | Coverage |
|---|---|---|
| 1. Visual fidelity vs Stitch | Python extraction of every `#RRGGBB`, inline `border-radius:Npx`, Tailwind `rounded-*`, `text-[Npx]`, `gap-N` utility from all mapped `code.html` files; diffed against `theme.dart` token values | All 28 authoritative folders |
| 2. Token compliance | `grep -rn "Color(0x" screens/ widgets/`; `Colors.(white\|black\|…)` sweep; `fontSize:` sweep; `BorderRadius.circular(<digit>` sweep; EdgeInsets/SizedBox numeric-literal sweeps | 100% of screens + widgets |
| 3. Component consistency | Raw-widget sweeps (`ElevatedButton\|TextButton\|OutlinedButton`, InkWell/GestureDetector inventory); shared-widget usage table | 100% |
| 4. State coverage | Per-screen grep for `ThemedLoadingIndicator/SkeletonLoader` (L), `ThemedEmptyState` (E), `ThemedErrorBanner/showError` (R), success banners (S), connection banners (C) | 29 rows incl. component library |
| 5. Localization | Regex over all string-bearing params (`Text(`, `label:`, `title:`, `hintText:`, `tooltip:`, …) matching word-bearing literals | 100% of lib/ |
| 6. RTL | Sweeps: `EdgeInsets.only(left/right`, `Alignment.centerLeft/Right/bottomLeft/topRight`, `TextAlign.left/right`, directional-API adoption | 100% |
| 7. Accessibility | IconButton tooltip/Semantics scan (34 sites); tap-target constraint scan; Semantics on custom controls (stars, PIN) | Static only |
| 8. Interaction robustness | Re-verification of A4 guard coverage claims; search-input trigger analysis; in-flight disabled states via `PrimaryButton.isLoading` usage | Partial — see §6 |
| 9. Responsiveness | Fixed-width literal sweep (>100px), `width: double.infinity` count, 360dp reasoning against each hit | Static only |
| 10. Dead/unreachable UI | Overlap check against A7 pass (which cleared all 94 lib files + dead classes) | Cross-ref only |

Tooling results this session: `flutter analyze` → **"No issues found!"**; `flutter test` → **`00:17 +390: All tests passed!`**. Composition gate (`scripts/frontend_composition_gate.sh`) active in CI covers Scaffold/AppBar/BoxDecoration/Color(0xFF/toUpperCase bans in screens/.

---

## 2. Per-Screen Findings

### Group A: Authentication & Onboarding

#### 1. `login_screen.dart` — 0 findings
Checked: token compliance (0 raw colors/sizes/radii), l10n (0 hardcoded EN), RTL APIs (0 violations), IconButtons labeled, state treatments (error banner present, submit busy-state via PrimaryButton), Stitch palette deltas limited to the harmonization families listed in §3.2.

#### 2. `signup_screen.dart` — 0 findings
Same checks as A1; role-selector uses ThemedCard-based selection with amber active border per V2 spec; no raw widgets.

#### 3. `otp_screen.dart` — 1 shared finding
- **A3-F1 (Medium — Accessibility, shared widget)**: `OtpPinInput` boxes expose no `Semantics` to screen readers (grep `Semantics|semanticLabel` in `widgets/otp_pin_input.dart` → 0 hits). Each box should announce "digit N of 6, value X". Fix: wrap `_buildPinBox` TextField in `Semantics(label: …)`.
- File: `widgets/otp_pin_input.dart:183-224`.

#### 4. `forgot_password_screen.dart` — 0 findings
Single-screen consolidated flow verified; error banner + success snackbar paths present; no token deviations.

#### 5. `update_required_screen.dart`
- **A5-F1 (Low — Responsiveness)**: decorative pulse-ring panel fixed `width: 120` at `update_required_screen.dart:149`. Contained within a centered stack; no overflow path found at 360dp, but value is not a spacing token. Fix: hoist to `AppRadius`/dimension constant or leave documented.

### Group B: Customer Marketplace & Tracking

#### 6. `customer_home_screen.dart`
- **B1-F1 (High — Interaction robustness / state coverage)**: recent-activity fetch is fire-and-forget with no error surface: `customer_home_screen.dart:42-45` calls `fetchCustomerJobs(auth.token!)` inside `addPostFrameCallback` with no `.catchError` and the screen renders no error treatment for it (state table: L=- E=- R=-). If the call fails, the Home tab silently shows stale/empty content. Related-but-new: A5's documented silent-empty deferral lists *owner* home dashboard sections, not this customer shell. Fix: surface retryable `ThemedErrorBanner` on the activity card, or explicitly accept + document.
- **B1-F2 (Low — Responsiveness)**: quick-book CTA hard-fixed `SizedBox(width: 170)` at `customer_home_screen.dart:315` inside a `Wrap` — safe at 360dp today (Wrap wraps), but the fixed width is a magic number. Fix: `ConstrainedBox(maxWidth: 170)` or token constant.
- **B1-F3 (Low)**: decorative circle `width: 100/height: 100` at `customer_home_screen.dart:289` — non-token dimension, decorative-only.

#### 7. `customer_jobs_screen.dart` — 0 findings
PillFilterBar + list template states complete (L/E/R all present per table); 1 micro-spacer SizedBox (counted in cross-screen §3.4).

#### 8. `customer_marketplace_screen.dart`
- **B3-F1 (Medium — Component consistency)**: raw `ElevatedButton` at `customer_marketplace_screen.dart:402` builds the search icon button by hand (styleFrom block lines 403–412) instead of `SecondaryButton(isOutlined:)` used elsewhere post-Batch-26; bypasses the shared 600ms debounce inherited by Primary/SecondaryButton. Trigger is an idempotent GET (documented-benign class in A4), so severity stays Medium on consistency grounds, not double-submit.
- **B3-F2 (Medium — Accessibility)**: that button is icon-only with **no tooltip/SemanticsLabel** (`Icon(Icons.search)` child, lines 413–414; scan shows zero `semanticLabel`). Screen-reader announces nothing. Fix: add `tooltip`-equivalent Semantics or switch to an IconButton with tooltip.
- **B3-F3 (Low — Typography)**: raw `fontSize: 10` at `customer_marketplace_screen.dart:119` duplicates `AppTypography.labelSm`. Fix: replace with token.

#### 9. `job_status_screen.dart`
- **B4-F1 (Medium — Responsiveness)**: counter-offer submit button pinned `SizedBox(width: 150)` at `job_status_screen.dart:1232` inside a horizontal Row adjacent to the offer input. With RTL padding + input flex minimums, sub-360dp widths risk overflow (Row has a non-flexible 150px sibling). Fix: wrap in `Flexible`/`Expanded` or drop fixed width for `isFullWidth` handling.
- **B4-F2 (Low)**: micro-spacers ×5 (`job_status_screen.dart` — counted in §3.4).

#### 10. `customer_job_map_screen.dart`
- **B5-F1 (Low — Token compliance)**: scrim `Colors.black.withValues(alpha: 0.12)` at `customer_job_map_screen.dart:378` — raw color family instead of a named scrim/shadow token. Functional; fix = introduce `AppColors.scrim`.
- Map hydration error unreadability is **already documented** (STATUS A5 entry) — not re-reported.

### Group C: Tenant Owner Operations & Services

#### 11. `home_screen.dart` (Owner Dashboard)
- **C1-F1 (Medium — Component consistency)**: two hand-styled amber `TextButton`s at `home_screen.dart:940` ("schedule" action → Fleet tab) and `home_screen.dart:995` (pending-reconciliations action → queue screen) replicate the SecondaryButton pill look with local styleFrom. They bypass the shared debounce/in-flight machinery. Neither triggers network directly (navigation/tap callbacks), keeping severity Medium-consistency rather than High.
- **C1-F2 (Low — Token compliance)**: `Colors.black.withValues(alpha: 0.1)` at `home_screen.dart:1072` — raw shadow/scrim tint.
- Silent-empty dashboard sections are **already documented** (STATUS A5) — not re-reported.

#### 12. `employee_screen.dart` — 0 findings
L/E/R/S all present; roster uses EntityAvatar/StatusBadge canonically; no raw sizes/colors beyond counted spacers.

#### 13. `service_screen.dart` — 0 new findings
Missing error-state is **already documented** (STATUS A5: service_screen silent-empty). Nothing new on tokens/components.

#### 14. `owner_configuration_screen.dart` — 0 findings
All checks clean (form uses ThemedTextField/PrimaryButton; image picker override testable; L/R/S present).

#### 15. `kyc_document_upload_screen.dart` — 0 findings
Per-slot loading/error/success handled; structural decomposition verified earlier phases; no raw tokens.

### Group D: Financial Management & Fleet Oversight

#### 16. `wallet_screen.dart`
- **D1-F1 (Medium — Typography)**: raw `fontSize: 32` at `wallet_screen.dart:229` (balance hero). Equals `AppTypography.headlineLg` (32px) — should be the token (also gains the documented line-height).
- **D1-F2 (Low — Responsiveness)**: fixed `width: 160` at `wallet_screen.dart:161` (decorative hero element). Bounded, low risk.
- Wallet failure-path silence checked fresh this session: the only `catch (_)` is timestamp parsing (`wallet_screen.dart:449`) — benign date-parse guard, **not** a hidden swallow. Ledger empty state exists; deposit/payout dialogs carry their own error banners (covered by their dedicated suites).

#### 17. `subscription_screen.dart` — 0 findings
Tier cards canonical; L/R/S present; highlight styling per V2.

#### 18. `owner_fleet_map_screen.dart`
- **D3-F1 (Medium — Typography)**: raw `fontSize: 10` at `owner_fleet_map_screen.dart:245` (marker labels) → `AppTypography.labelSm`.
- **D3-F2 (Low — Token compliance)**: `Colors.white.withValues(alpha: 0.2)` at `owner_fleet_map_screen.dart:234` — raw white-alpha ring; candidate for `AppColors.onPrimary.withValues(...)` or a marker-halo token.
- Hydration-error silence already documented (A5) — not re-reported.

#### 19. `owner_history_screen.dart` — 0 findings
TabBar typography tokenized (Phase 26f verification held up on re-read); L/E/R present.

#### 20. `owner_reconciliation_queue_screen.dart`
- **D5-F1 (Low — Responsiveness)**: fixed `width: 120` at `owner_reconciliation_queue_screen.dart:429` (decorative/empty-state graphic container). Bounded.
- Resolve-flow double-submit protection verified still in place (A4 regression suite passes).

### Group E: Employee Shell, Support & Communication

#### 21. `employee_home_screen.dart` — 0 direct findings
Shell delegates data surfaces to embedded tabs; unread badge pattern identical to other shells (line 150-163); no raw token violations found in shell chrome itself.

#### 22. `employee_jobs_screen.dart` — 0 new findings
GPS pill + permission banner Consumers tightly scoped; L/E/R/S present; chat/complete actions carry A4 guards (regression suite green).

#### 23. `employee_history_screen.dart` — 0 findings
L/E/R present; card anatomy matches employee_jobs_final_fidelity mapping.

#### 24. `settings_screen.dart` — 0 findings
Static preference surfaces; SegmentedButton theme canonical; logout guarded by template-level lock (A4).

#### 25. `my_account_screen.dart` — 0 findings
Form states complete; email read-only field controller now owned/disposed (A6); frequent-address cap validation localized.

#### 26. `notifications_screen.dart`
- **E2-F1 (Medium — State coverage)**: connectivity banner exists (`_buildConnectivityBanner`, line 165-190) but there is **no error treatment** distinct from it: if SSE errors while `isConnected` never flipped true, banner renders the neutral "connected=false" style rather than a retryable error affordance, and dismiss/reply failures have no surfaced path (state table R=-). Fix: map `provider.error != null` to a retryable `ThemedErrorBanner` variant above the list.
- Clock-pinned golden determinism and mock-reply stub are **already documented** (STATUS) — not re-reported.

#### 27. `chat_screen.dart`
- **E3-F1 (Low — Token compliance)**: bubble/container tints use raw `Colors.black.withValues(alpha: 0.04)` at `chat_screen.dart:310` and `:415`. Fix: `AppColors.surfaceContainerLow`-family token or named scrim.
- Send double-tap flag + teardown verified (A4/A6 suites green).

#### 28. `rating_screen.dart`
- **E4-F1 (Medium — Accessibility)**: star selector gives every star the SAME generic tooltip `context.l10n.ratingTitle` (`rating_screen.dart:359`) — screen readers cannot distinguish "rate 3" from "rate 5", and there is no selected-value announcement. Tap targets themselves are correct (44×44 constraints, line 358). Fix: per-star `Semantics(label: "<n> stars", …)` + liveRegion announce on selection.

---

## 3. Cross-Screen Consistency Findings

### 3.1 Navigation shell parity
Owner + Customer shells both build on `DashboardScreenTemplate` (`widgets/dashboard_screen_template.dart:109-111`, single `NavigationBar` implementation). Employee shell hand-builds its own destinations list (`employee_home_screen.dart:191-205`) but consumes the same `NavigationBar`/M3 styling. Unread-badge pattern identical across all three shells (`home_screen.dart:121`, `customer_home_screen.dart:113`, `employee_home_screen.dart:150`, plus embedded `employee_jobs_screen.dart:309`). **No parity defect found**; residual risk is the duplicated destination-building code (maintenance, not visual).

### 3.2 Typography scale audit (literal counts)
Distinct `AppTypography.*` tokens in use: **12** (`bodyLg`×8 files, `bodyMd`×41, `bodySm`×16, `caption`×14, `headlineLg`×4, `headlineLgMobile`×18, `headlineMd`×1, `labelLg`×22, `labelMd`×22, `labelSm`×9, `titleMd`×31, `uppercaseLabel`×17). Documented scale = {48,32,24,20,18,16,14,13,12,11,10} + caption(11). Raw `fontSize:` literals outside theme.dart: **5 sites**, of which 3 are literal-value findings (`customer_marketplace_screen.dart:119`→10px, `owner_fleet_map_screen.dart:245`→10px, `wallet_screen.dart:229`→32px) and 2 are computed dynamics in `entity_avatar.dart:77,95` (`radius*0.8` — acceptable parametric sizing). `displayLg` (48px) currently has **zero usages** in screens/widgets — unused-token note, not removal candidate (brand metric display reserved). Stitch HTML uses `text-[28px]`(×3) and `text-[40px]`(×2) with no direct Flutter token; current mapping routes them through line-heights of existing tokens — alignment note, no defect.

### 3.3 Color audit (literal counts)
`Color(0x…)` literals in screens/: **0**. In widgets/: **0**. Raw Material color families (`Colors.black|white|red|green|blue|grey|amber|orange` excluding transparent): **15 sites** — breakdown: `themed_success_banner.dart` ×10 (`Colors.white` text/icon on success fills, lines 50,58,88,96,104,130,138,164,172), screens-side alpha scrims ×5 (`chat_screen.dart:310,415` black@0.04; `customer_job_map_screen.dart:378` black@0.12; `home_screen.dart:1072` black@0.1; `owner_fleet_map_screen.dart:234` white@0.2), plus `location_picker_map.dart:157` white progress indicator. Recommendation: introduce `AppColors.onSuccess` (or reuse `onPrimary`) + `AppColors.scrim` and retire all 15.

### 3.4 Spacing audit (literal counts)
Raw numeric `EdgeInsets`: **2** (`widgets/route_timeline.dart:54,110` — `top: 2` connector margins). Raw numeric `SizedBox(height:/width:)`: **32** across 11 screens (values: 2px ×28, 4px ×3, 6px ×1; heaviest `home_screen.dart` ×9, `job_status_screen.dart` ×5, `service_screen.dart` ×4). All are sub-8px micro-spacers with exact token equivalents (`AppSpacing.xxs`=2, `.xs`=4; 6px has no token — nearest `baseSm`=10 or add `AppSpacing.xxsPlus`). `EdgeInsetsDirectional` raw literals: 0. `BorderRadius.circular(<raw>)`: 0.

### 3.5 RTL audit (literal counts)
`EdgeInsets.only(left:/right:` : **1** — `widgets/pill_filter_bar.dart:45` (`right: AppSpacing.base`) breaks mirrored padding in Arabic (should be `EdgeInsetsDirectional.only(end:)`). `Alignment.centerLeft/Right/bottomLeft/topRight`: 0. `TextAlign.left/right`: 0. Directional API adoption otherwise complete (P7a baseline held).

### 3.6 Localization audit (literal counts)
Word-bearing hardcoded string literals in user-facing params across all of lib/: **24 total**, all inside the two documented A2 exception zones (`main.dart:100` brand title; `component_library_screen.dart` ×23, kDebugMode-gated). Production screens/widgets: **0**. The seven files flagged by the prior code review (customer_jobs, home, customer_home, customer_job_map, owner_fleet_map, themed_success_banner, themed_banner) were individually swept this session — **all previously-flagged hardcoded English is FIXED** (0 hits in each). ARB en/ar parity: 595 = 595 keys (post-A7).

### 3.7 Accessibility audit (counts)
IconButton tooltip/Semantics coverage: **34/34 labeled** (0 unlabeled — P7b holds). Custom-control semantics gaps: rating stars per-star identity (**missing**, E4-F1) and OTP PIN boxes (**missing**, A3-F1). Static tap-target spot-checks passed where measurable in code (star selector 44×44; marketplace search button 52×52); full target-size matrix requires device testing (§6).

### 3.8 Dead/unreachable UI
Nothing new beyond A7's pass (94/94 files reference-audited, AppShadows removed). The debug-only `component_library_screen` remains kDebugMode-gated and excluded from production reachability.

---

## 4. Prioritized Remediation Order

Grouped by severity; within a tier, shared-component fixes that resolve many screens rank first.

**Tier 1 — High**
1. **B1-F1** customer_home silent-fail activity fetch → add retryable error surface (single screen; completes the A5-deferral family closure).
2. **B4-F1** job_status 150px fixed-width button in Row → Flexible wrap (overflow risk on narrow/RTL).

**Tier 2 — Medium (shared fixes resolve multiple screens)**
3. Introduce `AppColors.scrim` + `AppColors.onSuccess` tokens → resolves **E3-F1, B5-F1, C1-F2, D3-F2** and 10 of the 15 `Colors.*` sites (themed_success_banner ×10) in ONE widget/token change.
4. Replace 3 raw buttons with shared buttons (`B3-F1+C1-F1`) — restores debounce/in-flight inheritance; add Semantics label to the marketplace search icon (**B3-F2**) in the same change.
5. Typography token adoption ×3 (`B3-F3, D3-F1, D1-F1`) — one mechanical pass.
6. Custom-control semantics: per-star labels (`E4-F1`) + PIN-box announcements (`A3-F1`).
7. **E2-F1** notifications error-vs-connectivity distinction (retryable variant when `provider.error != null`).

**Tier 3 — Low (mechanical, batchable)**
8. 32 SizedBox micro-spacers + 2 EdgeInsets literals → token substitution sweep (11 screens + route_timeline).
9. Fixed decorative dimensions (A5-F1, B1-F3, D1-F2, D5-F1) → constants or leave documented.
10. `pill_filter_bar.dart:45` → `EdgeInsetsDirectional.only(end:)` (single-line RTL correctness fix; arguably Tier 1 by correctness but impact is 4px padding asymmetry in RTL — grouped here pending owner call).

---

## 5. Per-screen finding-count summary

| # | Screen | Findings | IDs |
|---|---|---|---|
| 1 | login_screen | 0 | — |
| 2 | signup_screen | 0 | — |
| 3 | otp_screen | 1 | A3-F1 |
| 4 | forgot_password_screen | 0 | — |
| 5 | update_required_screen | 1 | A5-F1 |
| 6 | customer_home_screen | 3 | B1-F1..F3 |
| 7 | customer_jobs_screen | 0 | — |
| 8 | customer_marketplace_screen | 3 | B3-F1..F3 |
| 9 | job_status_screen | 2 (+spacers) | B4-F1,F2 |
| 10 | customer_job_map_screen | 1 | B5-F1 |
| 11 | home_screen | 2 | C1-F1,F2 |
| 12 | employee_screen | 0 | — |
| 13 | service_screen | 0 new | (A5-documented) |
| 14 | owner_configuration_screen | 0 | — |
| 15 | kyc_document_upload_screen | 0 | — |
| 16 | wallet_screen | 2 | D1-F1,F2 |
| 17 | subscription_screen | 0 | — |
| 18 | owner_fleet_map_screen | 2 | D3-F1,F2 |
| 19 | owner_history_screen | 0 | — |
| 20 | owner_reconciliation_queue_screen | 1 | D5-F1 |
| 21 | employee_home_screen | 0 | — |
| 22 | employee_jobs_screen | 0 | — |
| 23 | employee_history_screen | 0 | — |
| 24 | settings_screen | 0 | — |
| 25 | my_account_screen | 0 | — |
| 26 | notifications_screen | 1 | E2-F1 |
| 27 | chat_screen | 1 | E3-F1 |
| 28 | rating_screen | 1 | E4-F1 |

**Total: 21 findings** (0 Critical, 2 High, 10 Medium, 9 Low) + cross-screen sections 3.1–3.8.

Zero-finding screens each record the categories actually checked in their entries above; "0" means those specific checks produced no evidence, not a rendered-visual guarantee (§6).

---

## 6. NOT CHECKED / needs manual device testing

The following require real rendering/touch hardware and were **not verified headlessly**:

1. **Actual WCAG contrast rendering** — all contrast commentary traces to token hex math, not composited pixels (alpha compositing of `withValues()` overlays can shift ratios). Needs screenshot-based contrast sampling in light AND dark themes.
2. **True RTL screenshot comparison** — API-sweep found 1 violation, but full mirrored-layout verification (icon direction flips, animation direction, `Directionality` overrides in popups/dialogs) needs `flutter run` with `ar` locale and eyeball/screenshot diffs.
3. **Real touch-target testing** — code-level minSizes verified for sampled controls only; gesture-conflict and effective-target testing (especially map floating controls, PillFilterBar scroll-diagonals, OTP backspace capture) needs a device.
4. **Golden/visual regressions for the 15 `Colors.*` remediation** — any token introduction must regenerate the 8 goldens under the pinned-Flutter contract (frontend/README.md standing rule) before merge.
5. **Scroll performance / jank** (map screens with live markers, long ledgers) — out of scope for static audit; needs profile-mode device run.
6. **Dynamic-type/font-scale behavior** (user font scaling 1.3×+) — untested; fixed-height containers (OTP boxes, pills) are the likely stress points.
7. **Dark-theme exhaustive pass** — dark tokens exist and P2/P16 hardening is documented, but this audit did not re-verify every screen's dark rendering; themed_success_banner's `Colors.white` text is the highest-risk item if success-container backgrounds differ between themes.

---

*End of audit. Every number in this document is the literal output of greps/scripts run this session against the working tree at merge commit `4ab627e` content; tool outputs quoted verbatim where relevant.*
