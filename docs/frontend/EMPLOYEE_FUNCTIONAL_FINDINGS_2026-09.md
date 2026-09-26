# Employee Functional Findings (2026-09) — capability sweep, not visual

> **Date**: September 26, 2026. **Scope**: `employee_home_screen.dart`,
> `employee_jobs_screen.dart`, `employee_history_screen.dart`,
> `employee_screen.dart` + `employee_jobs_provider.dart`,
> `employee_location_provider.dart`, `models/job.dart`. Functional only
> (missing/unreachable actions, unsurface/unmodeled information) — visual
> audit closed separately (`UI_VISUAL_AUDIT_2026-09.md`).
> **Role note**: `employee_screen.dart` is OWNER-side worker management
> (role gate passes employees straight to `EmployeeJobsScreen`); swept as
> listed, findings marked accordingly.
> **Already fixed this pass** (not re-listed as open): awaiting-price
> status panel (Issue 1), destination mini-map preview (Issue 2 Option A),
> provider local-rebuild field preservation (accept/complete fallback
> paths). **Explicit non-finding**: no "Start trip" button is missing —
> no backend start transition exists (`active` IS the started state);
> the gap was communication, fixed via the pending-fare panel.

## Open findings (same table format as prior UX audits)

| # | Screen / area | Location | Severity | Bucket | Finding (one paragraph) |
|---|---|---|---|---|---|
| F1 | Incoming offers (`employee_jobs_screen.dart`) | Offer card ~821–969 vs regular card ~1040–1160 | P1 | Frontend-only | Offer cards hide job ID, escrow amount, proposed/suggested fare, and customer — the employee Accepts blind, then discovers the fare on the assigned card (or the pending-fare panel). All data is already in the `Job` model; surface the same fare/escrow/customer lines the regular card shows before the accept/decline buttons. |
| F2 | COD confirm (`employee_jobs_screen.dart`) | ~187–188 | P2 | Frontend-only | The cash-collection confirm shows `lockedEscrowAmount` as the cash proxy, never `agreedPrice` (model field exists, customers see it). Show the agreed fare as the amount due. |
| F3 | Pending-fare panel (`employee_jobs_screen.dart`) | ~1269 | P2 | Frontend-only | Panel merges `proposedPrice ?? suggestedPrice` with no attribution (`proposedBy` never shown, unlike the customer `proposalByLine`) and no suggested-vs-proposed comparison (unlike the customer card). Add attribution + comparison lines. |
| F4 | Cancellation-request outcome (`employee_jobs_screen.dart`) | ~1330–1360 | P2 | Frontend-only | Only `pending`/`rejected` branches render; an `approved` outcome is learned by list disappearance with no confirmation. Render an approved acknowledgment. |
| F5 | Cancellation-request detail (`employee_jobs_screen.dart`) | ~1341–1372 | P2 | Frontend-only | Banners are generic: the stored `cancellationRequestReason`/`RequestedAt` are never echoed, and there is no withdraw action (only re-request after rejection). Echo reason + offer withdraw while pending. |
| F6 | Live location (`employee_jobs_screen.dart`) | ~1179–1207 | P3 | Frontend-only | `currentLocation` never mapped — binary "sharing" indicator only. Render coordinates or a mini-map (reuse `JobLocationMiniMap`) for self-verification. |
| F7 | Offer context (`employee_jobs_screen.dart`) | Model `:44–46` | P3 | Frontend-only | `currentOfferedEmployeeId`/`offeredEmployeeIds` hidden — employee cannot tell sole offer from broadcast race. Surface "offered to you alone / N couriers" line. |
| F8 | History actions (`employee_history_screen.dart`) | Card ~145–241 | P3 | Frontend-only | Zero per-job actions: no chat link (vs jobs card), no rating entry (rating screen keys off IDs history never passes), no receipt/dispute. Add chat + rating deep-links. |
| F9 | History detail (`employee_history_screen.dart`) | Card ~145–241 | P3 | Frontend-only | No dates (`createdAt`/`updatedAt`), no service, pickup shows a static label instead of `location` coords, dropoff shows customer ID instead of destination coords/map (jobs cards show both). Restore parity fields. |
| B1 | Addresses/notes | `job.dart:1–4` | P1 | Needs-backend | Model carries only lat/lng — no street/city/floor/delivery notes anywhere (root cause of Issue 2). Option A thumbnail ships as fallback; Option B (stored display strings, Nominatim) awaits decision in `DESTINATION_ADDRESS_PROPOSAL.md`. |
| B2 | Customer contact | `job.dart:30` | P1 | Needs-backend | Only raw `userId` echoed; no name/phone/avatar, no call/SMS affordance (chat exists). Requires user-profile exposure endpoint + privacy decision. |
| B3 | Earnings/ratings | `job.dart` (absent) | P2 | Needs-backend | No rating, per-job net pay, tip, or lifetime stats fields — history shows no stars/pay. Requires ratings + payout-breakdown model work. |
| B4 | Route truth | Timeline metrics | P2 | Needs-backend | `distanceText`/`timeText` are static labels or escrow amounts; no distance/ETA/polylines in the model. Requires routing/ETA source decision. |
| B5 | Cancellation metadata | `job.dart:47–49` | P3 | Needs-backend | No responder ID/decision timestamp — only request-side fields. Requires handler+model addition. |
| B6 | Dispatch context | `job.dart:44–46` | P3 | Needs-backend | No queue position, broadcast radius, or retry count beyond `offerExpiresAt`. Requires dispatch-side fields if wanted. |
| B7 | Roster workload | `employee_screen.dart:166–179,375–440` | P3 | Needs-backend (likely) | Owner cards show only `is_active`/username/email — no assigned-job counts, live location, or dispatch-to-worker action. Needs aggregation endpoint if absent. |

**Tally**: 9 frontend-only open (1 P1 / 4 P2 / 4 P3) + 7 needs-backend open (2 P1 / 2 P2 / 3 P3). Fixed this pass: 3 (panel, minimap, preservation). Nothing here was silently fixed — open items await scoping.
