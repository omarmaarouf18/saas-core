# Worklog: FE-OWNER-2b — owner verification, account, wallet and plan (FE-OWNER-2 items 4–7), behind QD_REDESIGN_OWNER

## Task and scope
- Task ID: FE-OWNER-2b
- Item IDs covered: 4 (shared verification page), 5 (owner account page), 6 (wallet read-only, plan), 7 (tests + goldens, including FE-OWNER-2 items 1–3)
- Allowed paths (lane): `frontend/lib/features/verification/**` (new), `frontend/lib/features/owner/**`, `frontend/lib/features/courier/**` (only the verification hand-off), `frontend/lib/features/account/**` (owner rows), `frontend/lib/ui/**` (additive; not touched), ARB + generated l10n, `frontend/test/**`. Providers additive and tested. Nothing under `services/**` or `tests/e2e/**`; no hot path.
- Agent branch: agent/FE-OWNER-2b-owner-verification-account, created from logic-exploitation at 8cdabeb6 (FE-OWNER-2 items 0–3 and FE-COURIER merged). The base did not move during the task.

## Decisions taken
- **Owner decisions applied**: wallet read-only (add money / withdraw show the existing "coming soon" copy and never call the API); no service photo picker (untouched). **Plan: revised mid-task by the owner.** The first version hid upgrade / downgrade; the owner then decided: keep a "Request upgrade" button (confirm sheet, no payment explanation), show "Under review" with the button disabled after the request and whenever the tier is `pending_payment`, keep "Switch to free". Item 6 was committed with the revised behaviour only.
- **Verification is one page for both roles** (`features/verification`): owners four documents (KYB), couriers three (KYE); PDF only for the commercial register (the server accepts `application/pdf` only for `business_proof`). Status per slot is derived: the auth service keeps one status for the whole set, so a slot is needed / uploaded / under review / accepted / not accepted from "document on file" + the set status; a running upload shows "uploading".
- **Upload progress is indeterminate** (a bar + "Uploading <file>…"): byte progress needs a streamed request in `core/api_client.dart`, which is out of lane (see follow-ups).
- **Retry re-sends the same file**; picking another file is the slot's main action ("Choose another file" after a failure). Only the first missing document has the gold button (old A9 rule); a slot with an error has none.
- **Rejected sets**: the copy says documents go back to review as soon as one is uploaded, because the server sets `pending_super_admin_approval` whenever every document is on file after an upload (always true after a rejection).
- **Live refresh**: the verification page re-fetches the profile when a `kyc_rejected` notification for the signed-in user arrives (`kycRejectionStream`); the global KycRejectionDialogHost is unchanged.
- **Entry points**: `OwnerNav.openKyb` (Today KYB banner, service setup banner), `AccountNav.openVerification` (account rows of owners and couriers) and `CourierNav.openVerification` (courier KYE banner) all push the new page. With the flags off nothing changes (old screens still open KycDocumentUploadScreen).
- **Owner account**: OwnerShell's Account tab is the shared `AccountPage` under the redesign theme (was SettingsScreen under the app theme). Owner rows come first ("Your business": verification with KYB status value, service setup, plan, wallet, activity log), then my details, security, language, theme, support, sign out. No saved addresses or notifications row for owners (the shell has a bell). The owner rows' destinations are passed in through `OwnerAccountLinks`, so `features/account` does not import owner pages. The plan row shows the tier only once the dashboard data has been loaded (the shell does not fetch it).
- **Plan access** mirrors ADR-0024 `IsClosed`: open only on the paid tier before a set expiry; otherwise "customers can't find or book your business". Features listed are only what the server gates on the paid tier (listing and bookings, service create / update, live courier location) plus 0% commission (ADR-0017). The old made-up "$0" / "$19.99" prices and feature lists are gone.
- **Plan actions**: "Request upgrade" (gold) shown for free / cancelled / expired / unknown plans and, disabled, while pending; "Switch to free" (destructive) for paid or pending plans, with different confirm copy (paid: business closes to customers; pending: cancels the request). After either change the plan is re-fetched; a failure shows a notice with retry (429 shows the server text with the wait time). One change at a time.
- **Wallet**: balances, withdrawals (amount, method, date, account, status chip, rejection reason), the latest five ledger entries with "see all" to the activity log's Money tab (reuses its `ledgerRow`). Money in EGP via QdMoney.
- **Strings**: new ARB keys `vrf*` (56), `acct*` (4: section, service setup, plan, activity log), `ownWallet*` / `ownPayout*` / `ownPlan*` (51). No existing key changed; the wallet reuses `digitalPaymentsComingSoon`, the account reuses `acctWallet`, `acctVerification`, `acctKye*`.

## Changes per commit (message only — NO SHAs)
1. `FE-OWNER-2b: item 4 - shared verification page (KYB / KYE)`
2. `FE-OWNER-2b: item 5 - owner account page in the owner shell`
3. `FE-OWNER-2b: item 6 - wallet (read-only) and plan pages`
4. `FE-OWNER-2b: item 7 - goldens for verification, account, wallet, plan and FE-OWNER-2 pages`
5. `FE-OWNER-2b: worklog` (this file)

## Items
4. **done** (progress is indeterminate, see Decisions).
5. **done**.
6. **done** (plan per the revised owner decision).
7. **done**: widget / unit tests shipped with items 4–6; 32 goldens. FE-OWNER-2 items 1–3 already had the behaviour tests the task lists (service validation, create → update, map reconnect banner, activity / money tabs), so item 7 added their goldens only. Flag tests: the existing `QD_REDESIGN_OWNER` tests still pass; the shell test now checks the Account tab is AccountPage with working owner rows and the verification row opens the new page.

## Provider changes
- `OwnerProvider.subscriptionExpiresAt` (additive): `expires_at` of `GET /users/subscription`, parsed in `fetchDashboardData`; Go's zero time (year 1), a missing or unparsable value → null.
- `OwnerProvider.payoutRequestsError` (additive): the error of the last `fetchPayoutRequests` alone (the shared `error` can be cleared by any other call).
- Both tested in `test/features/owner/owner_provider_additions_test.dart` with the mock HTTP harness. `AuthProvider`, `NotificationsProvider`: unchanged (used as they are).

## Components added to lib/ui
- None. Verification widgets live in `features/verification`, wallet / plan in `features/owner`.

## Verification

Literal output, local Flutter (same toolchain as the earlier FE tasks), on the tree of commit 4 (before this worklog):

```
$ flutter analyze
Analyzing frontend...                                           
No issues found! (ran in 0.9s)
$ flutter test
00:57 +1718: All tests passed!
$ flutter test test/features/verification test/features/owner test/features/account test/features/courier
00:14 +468: All tests passed!
$ git diff --stat logic-exploitation..HEAD -- frontend/test/goldens
(end)
$ git diff --stat logic-exploitation...HEAD -- "*.png" | tail -3
 .../goldens/vrf_upload_error_ar_rtl_360x800.png         | Bin 0 -> 50094 bytes
 .../goldens/vrf_upload_error_en_ltr_360x800.png         | Bin 0 -> 50401 bytes
 32 files changed, 0 insertions(+), 0 deletions(-)
$ git diff --name-status logic-exploitation...HEAD -- "*.png" | grep -v "^A"
(end)
$ git diff --stat logic-exploitation...HEAD -- services tests/e2e
(end)
$ git diff --stat logic-exploitation...HEAD | tail -5
 .../verification/verification_goldens_test.dart    | 112 ++++
 .../verification/verification_harness.dart         | 162 +++++
 .../verification/verification_page_test.dart       | 355 +++++++++++
 .../verification/verification_rules_test.dart      | 151 +++++
 59 files changed, 5464 insertions(+), 38 deletions(-)
```

`(end)` is a marker echoed after the command: the diff on `frontend/test/goldens` printed nothing (old screen goldens byte-identical), every PNG in the branch is new (no existing golden changed), and nothing under `services` or `tests/e2e` changed.

`git log --oneline logic-exploitation..HEAD` before this worklog, short SHAs removed per CLAUDE.md (they are in the chat report):

```
FE-OWNER-2b: item 7 - goldens for verification, account, wallet, plan and FE-OWNER-2 pages
FE-OWNER-2b: item 6 - wallet (read-only) and plan pages
FE-OWNER-2b: item 5 - owner account page in the owner shell
FE-OWNER-2b: item 4 - shared verification page (KYB / KYE)
```

`make check` (scope: docgen frontend) passed before every commit and ended with `== pre-push gate: all checks passed (scope: docgen frontend) ==`. One run before item 7 failed on two `prefer_const_constructors` infos in the new goldens test; fixed, rerun passed.

New goldens (360x800, light, Plex font), all reviewed by eye:
- `frontend/test/features/verification/goldens/vrf_{owner_missing,owner_rejected,courier_uploading,courier_approved,source_sheet,upload_error}_{ar_rtl,en_ltr}_360x800.png` (12)
- `frontend/test/features/owner/goldens/own_{account,wallet,plan_paid,plan_free,plan_review,service,service_errors,fleet_reconnecting,activity,money}_{ar_rtl,en_ltr}_360x800.png` (20)

The visual review changed one thing before commit: the slot card's "Replace" moved into the status row, and the status chip and file name were stacked (side by side they overflowed with the test font).

## Behaviour checklist (old → new)

kyc_document_upload_screen.dart → VerificationPage
- ✓ Profile re-fetched on open and on pull to refresh, guarded against double runs; load error with retry.
- ✓ Owner four slots (ID front, ID back, selfie, business proof), courier three.
- ✓ Set status (not uploaded / under review / rejected / approved) with the reviewer's reason when rejected; approved → locked, no actions, "documents can't be changed".
- ✓ Camera / gallery (1920 px, quality 85) / file (PDF only for business proof) choice.
- ✓ 10 MB limit and JPG / PNG (+ PDF) checks before sending; per-slot uploading state and error with retry; only the first incomplete slot gets the primary button.
- ✓ "Uploaded" per slot and the file sent from the page by name ("photo / PDF on file" otherwise).
- ✓ Couriers use `kye_status` (the old settings row checked `kyc_status` for couriers too).
- New: empty-file check, server 400 format / size and 403 in plain words, retry re-sends the same file, "all uploaded, now under review" notice, live refresh on a rejection notification, per-slot status chips.
- Dropped: "remove selection" (cleared only the local preview), app-bar refresh button (pull to refresh + retry remain). Changed: the local image thumbnail is replaced by the file name.
- Gap: progress is indeterminate (no byte progress, see follow-ups).

kyc_rejection_dialog_host
- ✓ Unchanged (global, in main.dart). The verification page additionally refreshes on the same stream.

wallet_screen.dart → OwnerWalletPage
- ✓ Balances, ledger and withdrawals fetched on open and on pull to refresh by one routine (S15); loader instead of zero balances (S16); load error with retry; stale banner on a failed refresh over loaded data; withdrawals keep the last good list on failure (S6) with their own error.
- ✓ Withdrawal amount, method, date, account details, status, rejection reason. Ledger type, order, balance after, time (latest five + "see all").
- Changed (owner decision): deposit and withdraw never open their dialogs or call the API, whatever `digital_payments_enabled` says; `fetchPaymentAvailability` is not called. "$" → EGP.

subscription_screen.dart → OwnerPlanPage
- ✓ Fetched on open; loader instead of the default "free" tier (S1); load error with retry; pending note for `pending_payment`.
- ✓ Upgrade and downgrade both confirmed first (S7), downgrade destructive; success / failure notices with retry; one change at a time.
- Changed: "Upgrade" → "Request upgrade" (the server only stores `pending_payment`), disabled and shown as "Under review" while pending; downgrade available for paid or pending plans only (not for free); plan re-fetched after a change.
- New: expiry date and whether customers can find / book the business.
- Dropped: made-up prices and unenforced feature lists, BASIC / PRO badge.

settings_screen.dart (owner rows) → AccountPage (owner)
- ✓ Owner configuration → "Service setup"; My account → "My details"; KYC row → "Verification" (now always shown, with the status as value; the old row hid itself once approved); 2FA → "Security"; theme, language; support tickets; sign out; notifications bell (shell).
- New: plan, wallet, activity log rows.

## Data gaps / backend needs
- **Upload progress**: `ApiClient.postMultipart` buffers the request; byte progress would need a streamed multipart send with a progress callback (core, out of lane).
- **Per-document review**: the server has one status and one note for the whole set; a per-document verdict would let the page mark only the rejected documents.
- **Plan request feedback**: `POST /users/subscription` (paid) returns only `status` / `message`; no request timestamp, so "under review since" cannot be shown.
- **Support tickets for owners**: TicketsPage's new-complaint sheet fetches customer jobs for its order picker; for an owner that list is empty / fails and the sheet works without it (same as couriers since FE-COURIER). Not checked against the backend.

## Unverified
- **Device / desktop run against a backend**: not done (no owner / courier credentials or device in this session). Uploads, the subscription POST, payouts and the rejection stream were exercised only through widget tests with fakes shaped after the handlers (`UploadKYB` / `UploadKYE`, `Subscription`).
- **Camera / gallery / file picker** on a device: the default `DocumentPicker` was not run (tests use a fake); camera on desktop is expected to fail and shows "Couldn't open that. Try another option."
- **Date format** of the plan expiry in Arabic (`DateFormat.yMMMd('ar')`): seen only in the golden.
- **CI rendering of the new goldens**: generated locally, not yet seen on ubuntu-latest.
- **Dark mode**: not checked (light goldens only).
- GitHub CI: not run (agents do not push).

## Follow-ups / out-of-lane findings
- `core/api_client.dart`: streamed multipart upload with progress (then the verification bar can show real progress).
- Backend: per-document review result; request time for `pending_payment`.
- `docs/frontend/STATUS.md` rows for `features/verification/**` and the owner account / wallet / plan pages (owner-only file).
- FE-CLEANUP: once the owner and courier flags ship, delete KycDocumentUploadScreen, WalletScreen, SubscriptionScreen, DepositFundsDialog, PayoutRequestDialog and the owner path of SettingsScreen.

## Open questions
- Downgrade is offered only for a paid or pending plan (a free owner has nothing to switch from). OK?
- The account plan row shows the tier only after the plan / wallet / money data has been loaded once (the shell does not fetch it). Should the shell load it on the Account tab?
- Verification thumbnails: the old screen showed a 48 px preview of a just-picked image; the new page shows the file name. OK?
