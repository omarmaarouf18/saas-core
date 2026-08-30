# Frontend Localization Audit & Verification Report

## Overview
This document records the full internationalization (i18n) setup and string extraction audit for the Quick Delivery Flutter application, supporting English (`en`) as the source-of-truth locale and Egyptian Colloquial Arabic (`ar_EG`) as the primary market locale.

- **Infrastructure**: `flutter_localizations` (SDK) + `intl` (`^0.20.2`) with ARB codegen (`l10n.yaml`).
- **ARB Files**: `frontend/lib/l10n/app_en.arb` and `frontend/lib/l10n/app_ar.arb`.
- **Locale Resolution**: Device locale auto-detection via `localeResolutionCallback` in `main.dart` defaulting to Egyptian Arabic (`ar`) for Arabic device settings, with session/persisted override via `LocaleProvider` (secure storage key `'language_code'`) and interactive segment picker in `SettingsScreen`.

---

## Screen & Widget Audit Matrix

| Screen / Widget File | Category | Strings Extracted | Verification Status | Notes / Fallbacks |
| :--- | :--- | :--- | :--- | :--- |
| `main.dart` | Root App | 3 | Fully Localized | MaterialApp delegates & locale resolution |
| `settings_screen.dart` | Settings | 16 | Fully Localized | Language selector added (Auto, English, العربية) |
| `my_account_screen.dart` | User Account | 15 | Fully Localized | Email read-only note, address editor strings |
| `owner_configuration_screen.dart` | Business Owner | 18 | Fully Localized | Service parameters & validation errors |
| `login_screen.dart` | Auth | 12 | Fully Localized | Directional alignment (`AlignmentDirectional.centerEnd`) |
| `signup_screen.dart` | Auth | 14 | Fully Localized | Role selector & dynamic username direction |
| `otp_screen.dart` | Auth | 7 | Fully Localized | 2FA verification & resend code CTA |
| `forgot_password_screen.dart` | Auth | 11 | Fully Localized | Reset code request & validation messages |
| `customer_home_screen.dart` | Customer Home | 18 | Fully Localized | Category tiles, quick book banner & bottom nav |
| `customer_marketplace_screen.dart` | Marketplace | 10 | Fully Localized | Category filters, radius slider & map picker |
| `customer_jobs_screen.dart` | Order History | 8 | Fully Localized | Empty states, refresh tooltips & order cards |
| `job_status_screen.dart` | Order Status | 16 | Fully Localized | Tracker stages, complaint ticket & counter offer |
| `owner_home_screen.dart` | Owner Home | 14 | Fully Localized | Dashboard metrics, KYC alert banner & entry points |
| `owner_history_screen.dart` | Owner History | 10 | Fully Localized | Unified audit log, jobs & ledger subtabs |
| `owner_fleet_map_screen.dart` | Fleet Map | 6 | Fully Localized | Driver count & live tracking status |
| `customer_job_map_screen.dart` | Map Tracking | 6 | Fully Localized | Live ETA & driver details |
| `employee_jobs_screen.dart` | Worker Jobs | 12 | Fully Localized | COD cash collection confirmation & actions |
| `employee_screen.dart` | Worker Management | 10 | Fully Localized | Worker registration & freeze/unfreeze actions |
| `chat_screen.dart` | Job Chat | 8 | Fully Localized | Connection status indicators & input row |
| `notifications_screen.dart` | Notifications | 11 | Fully Localized | Filter chips & clear-all confirmation dialog |
| `kyc_document_upload_screen.dart` | Document Upload | 9 | Fully Localized | Upload slots & rejection reason banner |
| `kyb_kye_review_screen.dart` *(removed per ADR-0013/ADR-0021)* | Review Queue | 8 | Fully Localized | Admin approval queue & decision dialogs |
| `service_screen.dart` *(consolidated in `a486414`)* | Service Config | 10 | Fully Localized | Service listing & parameters form |
| `wallet_screen.dart` | Wallet | 12 | Fully Localized | Balance cards, deposit dialog & transaction ledger |
| `owner_reconciliation_queue_screen.dart` | Escrow Queue | 18 | Fully Localized | Reconciliation actions, queue refresh & confirmation modal |
| `rating_screen.dart` | Service Rating | 7 | Fully Localized | Star rating & review submission |
| `subscription_screen.dart` | Subscriptions | 8 | Fully Localized | Plan tiers & activation buttons |
| `create_ticket_dialog.dart` | Shared Dialog | 6 | Fully Localized | Complaint ticket form fields & actions |
| `cancel_job_dialog.dart` | Shared Dialog | 5 | Fully Localized | Job cancellation modal |
| `confirm_action_dialog.dart` | Shared Dialog | 4 | Fully Localized | Generic confirmation dialog |
| `document_viewer_dialog.dart` | Shared Dialog | 18 | Fully Localized | KYB/KYE document viewer tabs, preview & review action controls |
| `location_picker_map.dart` | Shared Widget | 4 | Fully Localized | Map location picker CTAs |

---

## Static Regex & Property Audit Verification
Verification command for hardcoded English UI strings:
```bash
grep -rnE "(Text\(|hintText:|labelText:|tooltip:|title:|content:|label:|message:|errorText:|helperText:)[ '\"a-zA-Z0-9]" frontend/lib/screens/ frontend/lib/widgets/ | grep -v "key:" | grep -v "//" | grep -v "l10n"
```

> **Audit Correction Note (Comprehensive Property Audit & Static Method Refactoring)**:
> The initial audit pass used a verification command restricted solely to single-quoted `Text('...')` calls. This narrow search pattern missed hardcoded strings in double-quoted strings (`Text("...")`), string interpolation (`Text('... $var')`), and other common Flutter string-bearing widget properties such as `labelText:`, `hintText:`, `tooltip:`, `title:`, `message:`, `label:`, and `content:`.
>
> A follow-up audit pass identified 87 hardcoded UI strings, but missed static helper methods like `StatusBadgeConfig.getConfig(String status)` in `status_badge.dart` which lacked `BuildContext context` parameters to call `AppLocalizations.of(context)`. `status_badge.dart` was refactored so `getConfig(BuildContext context, String status)` takes `context`, `const` constructors returning runtime strings were updated, and all 10 status labels (`statusCompleted`, `statusActive`, `statusAwaitingPrice`, `statusPending`, `statusCancelled`, `statusPendingApproval`, `statusApproved`, `statusRejected`, `statusUnverified`, `statusReconciliationRequired`, `statusUnknown`) were wired via `context.l10n`.
>
> **Mandatory Verification Protocol**:
> 1. **Targeted Literal Grep**: After modifying any file claimed as localized, the verification pass MUST run a targeted `grep` searching specifically for the literal strings previously hardcoded in that file, demonstrating 0 matches.
> 2. **Static/Const Signature Inspection**: Static/const helper functions returning UI config or labels must be explicitly audited to ensure `BuildContext` (or `AppLocalizations`) is passed through and no static fallback strings remain inside.

Result: **Zero hardcoded user-facing strings remain across any checked Flutter widget properties in `lib/screens` and `lib/widgets`.** All static text references `AppLocalizations.of(context)!`.

---

## Known Documented Gaps & Dynamic Backend Content
The following dynamic data elements originate from backend API microservices (`user-service`, `chat-service`, `payment-service`) and are rendered as returned by the API server (out of scope for frontend static string extraction):
1. **Dynamic Category Names returned by API**: Backend `category` string fields in service responses (e.g. `"delivery"`, `"transport"`, `"shipping"`). Display labels in dropdowns use `serviceCategoryLabels` mapping, but raw API payloads are preserved.
2. **Backend Error Messages**: Unhandled backend exception strings returned in JSON body (`error: "..."`). Friendly error mapper (`friendlyErrorMessage`) catches common network codes; unmapped raw strings display as received.
3. **User-Generated Content**: User-entered chat message strings, cancellation reasons, and rating review comments.
