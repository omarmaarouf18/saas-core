# ADR-0029: Rebrand from Quick Delivery to Waddify

- **Status**: Accepted (owner decision, 2026-11-23). Implementation not started.
- **Date**: 2026-11-23
- **Priority**: P0. The rebrand goes before every other open task (GitHub issues labelled `priority:P0` + `rebrand`).
- **Related**: ADR-0017 (subscription-only revenue model), ADR-0018 (client version gate; its update message names the brand); [docs/frontend/BRAND_IDENTITY.md](../frontend/BRAND_IDENTITY.md) (superseded by this ADR once the rebrand lands); [docs/design/DESIGN_SYSTEM.md](../design/DESIGN_SYSTEM.md); brand spec [docs/design/WADDIFY_BRAND.md](../design/WADDIFY_BRAND.md); assets in [docs/design/waddify/](../design/waddify/).

---

## Context

"Quick Delivery" describes one service, not the product. The product is a **platform**, comparable to Shopify or Steam:

- **Businesses** (delivery, ride and shipping companies) get an app experience under their own name and full admin tools (dispatch, staff, tracking, wallet, subscriptions).
- **Customers** get one marketplace of providers with different prices, ranked by rating.
- The platform itself never carries out a job. The providers do.

A name built on "ودّي" ("take it there") is clear and Egyptian, but many apps in the region already use it, and on its own it sounds like a delivery company, which competes with the businesses on the platform. Adding `-ify` (as in Shopify) turns it into "the thing that lets anyone deliver": the local meaning stays, the platform role is explicit, and the name stays distinct even when people shorten it.

Availability checked on 2026-11-23 (web and app-store search plus a registrar lookup; **not** a trademark search):

- No app, company or product named Waddify was found. The closest names are Wodify (US gym-management SaaS, different industry) and وفّي / Waffy (Saudi payment escrow).
- Domains: `waddify.com` is registered (no reachable site); `waddify.app`, `.io`, `.co`, `.net`, `.dev`, `.org` and `waddyfy.com` were available.

## Decision

### 1. Name

- Latin: **Waddify**, written as one word, lowercase in the wordmark (`waddify`, with `ify` in the accent colour).
- Arabic: **ودّيفاي**, one word, with the shadda.
- Never "Waddy Platform", "Top Waddy", "ودي فاي" (two words) or "Wadi".

### 2. Positioning

Waddify is a neutral platform. Copy never says or implies that Waddify carries out a delivery ("هيجيلك" style promises are out). The provider the customer picked delivers; Waddify connects, ranks and gives the tools. Ranking and rating rules must be published, and a paid placement must be labelled as one.

### 3. Brand architecture

| Audience | Name |
| :--- | :--- |
| Customers (marketplace app) | Waddify / ودّيفاي |
| Businesses (B2B offer) | Waddify for Business |
| Owners and staff (admin tools) | Waddify Console |
| Business-branded apps or screens | The business's own name + "Powered by waddify" / "بتشغيل waddify" badge |

### 4. Taglines

- Customers: **خليها تطير** (Let it fly).
- Businesses: **شركتك في أمان، وأوردراتك بتطير.**
- Business sub-line: أبلكيشن توصيل باسم شركتك، وأدوات إدارة ومتابعة كاملة.

### 5. Mark

A pigeon diving at a **fixed 55°** toward the bottom left: the **W is the wings**, the head sits in the W's inner notch with the beak pointing down, and the tail rises from the W's outer point. Meaning: the order has arrived. The geometry is fixed by [docs/design/waddify/mark.svg](../design/waddify/mark.svg); it is an original drawing (not derived from any third-party logo).

Rules:

- Never rotate, mirror, re-tilt, outline or recolour outside the palette.
- Clear space around the mark: at least twice the head's diameter.
- 32 px and up: full mark (Ink body, Nile tail, Sun beak; white body and Nile Light tail on Ink). 24-31 px: one colour, no beak ([mark-mono.svg](../design/waddify/mark-mono.svg)). Under 24 px: wings and head only.
- App icon master: [app-icon.svg](../design/waddify/app-icon.svg) (1024 px, full bleed, the OS applies the mask). The alternative tile colour is Nile (`#0E7C7B`) with an Ink tail.

### 6. Colours and type

| Token | Hex | Role |
| :--- | :--- | :--- |
| Ink | `#10233F` | Text, mark, trust surfaces |
| Nile | `#0E7C7B` | Primary actions (white text passes 4.5:1) |
| Nile Light | `#2FB5B3` | Accents on dark surfaces only |
| Sun | `#F2A541` | Beak, small highlights, CTA on teal; never body text on light backgrounds |
| Sand | `#F7F6F2` | Backgrounds |

Type: **Readex Pro** (Arabic + Latin, Google Fonts, OFL), weights 400 / 500 / 700. It replaces the bundled IBM Plex Sans Arabic; the swap touches `frontend/pubspec.yaml` (hot path).

Status colours (success, warning, danger) stay as they are; only the brand layer changes.

### 7. Scope

In scope (everything a user, customer or business sees):

- App name: Android `android:label`, iOS `CFBundleDisplayName` / `CFBundleName`, `MaterialApp.title`, l10n strings that name the brand (for example `updBody` in `app_ar.arb`).
- Launcher icons and splash.
- Theme tokens and font (`frontend/lib/ui/tokens.dart`, `frontend/lib/ui/qd_theme.dart`) and the goldens that follow.
- Server-side user-facing text: the version-gate message (`services/api-gateway/internal/middleware/version_gate.go`), the OTP email subject (`services/auth-service/internal/otp/resend_dispatcher.go`) and any push/email templates.
- Store listings, website, social handles, domains.
- Docs: this ADR, the brand spec, and replacing `docs/frontend/BRAND_IDENTITY.md`.

Out of scope (internal identifiers stay to avoid risky churn): the repo name `saas-core`, Go module paths, the `Qd` widget prefix, MongoDB database and collection names, API paths, systemd unit names (`quickdelivery-backup`, `quickdelivery-monitor`), the Android application ID / iOS bundle ID (changing them creates a new app in the stores; decide separately), and historical docs (`docs/changelog/**`, `docs/history/**`, `docs/worklog/**`).

## Consequences

- One coherent platform brand that leaves room for the businesses' own brands.
- The theme change re-baselines every golden; it ships as its own release.
- Clients older than the rebrand still show "Quick Delivery" until updated; the server-side update message switches at once.

## Open items

- Trademark search and filing (Egyptian trademark office; WIPO if expanding).
- Buy `waddify.app` and `waddify.io`; check social handles.
- A designer produces the final vector and the platform icon sets from `app-icon.svg`.
- Decide whether the Android application ID / iOS bundle ID change.
