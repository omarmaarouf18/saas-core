# Worklog: PUSH-L10N — push notifications in the user's language, EGP not $

## Task and scope
- Task ID: PUSH-L10N
- Item IDs covered: 1, 2, 3, 4, 5, 6
- Allowed paths (lane from the task prompt): `services/**` (auth-service device tokens,
  notification-service, the senders in user / auth / chat), `frontend/**` limited to the
  device-token call and the language change, ARB if needed (not needed), docs,
  `tests/e2e/**` (new file only), this worklog.
- Agent branch: agent/PUSH-L10N-localized-push-texts, created from logic-exploitation at
  b40726f5 (PUSH-FCM merge) with `make worktree-new`.

## Decisions taken
- **Locale per token** (item 1): `POST /auth/device-token` takes optional `locale`. `ar` / `en`,
  with `ar_EG`, `en-US` and any case normalized; anything else is a 400 (same pattern as the
  platform whitelist). Absent = legacy app: the token keeps no locale, and a re-register without
  one removes a stored locale (an old build on that phone gets English again). Stored in
  `device_tokens[].locale` (bson omitempty), returned by the internal `GET /auth/user`.
- **notification-service gets the locale** through a new optional interface
  (`hub.PushTargetFetcher.GetUserPushTargets`). The hub uses it when the fetcher implements it,
  so `DeviceTokenFetcher` and its test mocks are unchanged.
- **Templates** (item 2): one table in `services/notification-service/internal/templates`,
  keyed by `type` or `type:variant`. The sender picks a variant with `params.variant`; it is
  never shown. Placeholders are `{name}`. Money parameters are plain decimals that the table
  formats like the app's `QdMoney`: Western digits, a thousands separator, no decimals for
  whole amounts, else two. `EGP 1,250.50` / `1,250.50 ج.م`. The wording follows the app's own
  `ntf…` ARB strings where they exist. The sender's English text is used when the token has no
  locale, the type or variant has no template, a needed parameter is missing or blank, or a
  money value is not a number. A parameter value is inserted as text, never re-parsed.
- **Bodies keep what the app reads from them**: the ticket id stays in "(…)" (the app's
  `ticketIdFromBody`); the English `cancellation_resolved:accept` says "approved" (the app's
  fallback link). Job ids travel in `data.job_id`, which the app reads first.
- **Stored title / body stay English** (item 3): the app parses ids out of the English body
  and localizes titles by type, so changing the stored text would break today's app. Instead
  the record keeps `params`, and history and SSE add `params` and `texts.ar` / `texts.en`,
  rendered when read (the table is the only source, so older records with no params get texts
  for types that need none).
- **App** (item 4): `PushLocaleSync` in `MaterialApp.builder` reads
  `Localizations.localeOf(context)` on the first frame and on every change. That covers both
  an explicit choice and auto-detect. `PushNotificationService.setLocale` re-registers the
  current token while signed in. A switch during the token fetch is sent when the fetch ends.
  No ARB change was needed.
- **The legacy English `job_accepted` body** also lost the `$`: "Final fare: EGP 1,250.50"
  (`formatEGP` in user-service), so old apps no longer show dollars either.
- **No payout template**: no service sends a payout notification today (grep of every
  `/notifications/send` caller). The task's "payouts" row therefore has nothing to cover.
- **Pre-existing bug fixed, own commit** ("item 2 (fix)"): `notifyEmployeeCancellationResolved`
  is called with `"approved"` / `"declined"` but compared with `"accept"`, so an approved
  cancellation told the courier it was declined. The test fails without the fix (Verification).
- **Pre-existing bug fixed, own commit** ("item 6 (fix)"): notification-service built its
  device-token fetcher with a plain `http.Client`. auth-service only serves mTLS
  (`RequireAndVerifyClientCert`, `https://auth-service:3002` in every env file), so every push
  lookup failed and no push could reach a phone. The new e2e found it. The fetcher now dials
  with the service's own certificate, like the SSE token check.
- **E2E** (item 6) runs the real auth-service and notification-service binaries from this
  checkout (the staging stack was not running, and it cannot point notification-service at a
  fake FCM without a hot-path change; this is the PUSH-BE e2e pattern). It uses the staging
  Mongo / Redis in throwaway databases. auth-service refuses to start without a Resend key, so
  the test passes a placeholder that is never used (no OTP is sent).

## Template table (type → example, as pinned by the tests)

| `type` (`:variant`) | params | EN | AR |
|---|---|---|---|
| job_accepted | fare=1250 | A courier accepted your order / Final fare: EGP 1,250. | مندوب قبل طلبك / الأجرة النهائية: 1,250 ج.م. |
| job_accepted:negotiable | fare=45.5 | … / Suggested fare: EGP 45.50. You can answer the offer now. | … / الأجرة المقترحة: 45.50 ج.م. تقدر ترد على العرض دلوقتي. |
| job_unavailable | – | No courier is free right now / All couriers near you are busy. You can order again anytime. | مفيش مندوب فاضي دلوقتي / كل المناديب اللي جنبك مشغولين. تقدر تطلب تاني في أي وقت. |
| job_picked_up | – | Your order was picked up / The courier has it and is on the way to the drop-off. | طلبك اتستلم / المندوب استلمه وفي الطريق لمكان التسليم. |
| job_delivered | – | Your order was delivered / The courier delivered your order. | طلبك وصل / المندوب سلّم طلبك. |
| job_cancelled | – | Your order was cancelled / Open My orders for the details. | طلبك اتلغى / افتح طلباتي عشان تشوف التفاصيل. |
| job_cancelled:escrow_failed | – | … / The service owner couldn't hold the payment for it. | … / صاحب الخدمة ماقدرش يحجز المبلغ بتاعه. |
| dispute_resolved:customer_release / customer_refund / provider_release / provider_refund | – | The review of your order is done / The amount was released to the service provider. (refunded to your wallet / released to your wallet / refunded to the customer) | مراجعة طلبك خلصت / المبلغ اتحوّل لمقدم الخدمة. (رجع لمحفظتك / اتحوّل لمحفظتك / رجع للعميل) |
| job_booked | – | New booking / A customer booked one of your services. Open Orders for the details. | حجز جديد / عميل حجز خدمة من خدماتك. افتح الطلبات عشان تشوف التفاصيل. |
| cancellation_requested | reason | A courier asked to cancel a job / Reason: flat tyre. Answer within 15 minutes. | مندوب طالب يلغي مهمة / السبب: flat tyre. رد خلال 15 دقيقة. |
| cancellation_request_expired | – | A cancellation request ran out / No one answered in time: the courier was taken off the job and it went back to dispatch. | وقت طلب الإلغاء خلص / محدش رد في الوقت: المندوب اتشال من المهمة ورجعت للتوزيع. |
| job_offer | – | New job offer / Answer it from the Task tab within 60 seconds. | عرض مهمة جديد / رد عليه من المهمة خلال 60 ثانية. |
| cancellation_resolved:accept / :decline | – | Your cancellation request was answered / The business owner approved it. The job was cancelled. (declined it. You're still on the job.) | اترد على طلب الإلغاء بتاعك / صاحب الشغل وافق. المهمة اتلغت. (رفض. المهمة لسه معاك.) |
| job_alert | service_name | New job / New job for Fast Bikes. | مهمة جديدة / مهمة جديدة لخدمة Fast Bikes. |
| kyc_approved | – | Your verification was approved / Your documents were reviewed and accepted. | التوثيق بتاعك اتقبل / ورقك اتراجع واتقبل. |
| kyc_rejected | reason | Your verification wasn't accepted / Reason: blurry photo | التوثيق بتاعك ما اتقبلش / السبب: blurry photo |
| account_suspended | reason | Account suspended / Your account was suspended. Reason: fraud review | حسابك اتوقف / حسابك اتوقف. السبب: fraud review |
| account_reactivated | – | Account reactivated / Your account is active again. | حسابك رجع يشتغل / تقدر تستخدم حسابك تاني. |
| ticket_resolved | ticket_id, note | Your complaint was resolved / Your ticket (tkt-1) has been resolved: refunded | شكوتك اتحلت / شكوتك (tkt-1) اتحلت: refunded |
| ticket_assigned (:anonymous) | ticket_id, agent_name | Support joined your complaint / Mona joined your ticket (tkt-1). (A support agent joined …) | الدعم دخل على شكوتك / Mona دخل على شكوتك (tkt-1). (واحد من الدعم دخل …) |

Free-text parameters (reason, note, agent name, service name) are inserted as sent, so an
English reason stays English inside the Arabic text.

## Changes per commit (message only — NO SHAs)
1. `PUSH-L10N: item 1 - locale per device token`
2. `PUSH-L10N: item 2 - AR/EN push templates per type, EGP not $`
3. `PUSH-L10N: item 2 (fix) - approved cancellation said "declined"`
4. `PUSH-L10N: item 3 - history keeps type + params, texts per language`
5. `PUSH-L10N: item 4 - app sends its language with the push token`
6. `PUSH-L10N: item 5 - docs: push language, params, templates`
7. `PUSH-L10N: item 6 (fix) - device-token lookup dials auth-service over mTLS`
8. `PUSH-L10N: item 6 - e2e: AR and EN tokens, job_accepted, EGP`
9. `PUSH-L10N: item 2 (grep) - pricing test messages quote EGP, not $`
10. `PUSH-L10N: worklog`

## Verification
All local. `make check` passed before every commit (`make commit` refuses otherwise). Last lines
of the run on the final code tree (commit 9). The stamp path is shortened here because it is a
40-character hash:
```
No issues found! (ran in 0.8s)
00:37 +1391: All tests passed!
[timing] flutter-analyze-test 41.8s
[timing] total 396.9s
== pre-push gate: all checks passed (scope: full) ==
gate stamp written: <common .git>/gate-stamps/<tree> (scope: full)
```
(`No issues found!` is `flutter analyze`; `+1391: All tests passed!` is `flutter test`. The
full scope came from the untracked / unmapped e2e path.)

`go test -count=1 ./...` per changed service, run under `scripts/ci-lock.sh` (the shared local
Mongo / Redis lock). Run before commit 9, which touched only test log messages and was then
covered by the full `make check`. "no test files" lines dropped:
```
== services/auth-service: go test -count=1 ./...
ok  	github.com/project/auth-service/cmd	0.003s
ok  	github.com/project/auth-service/cmd/approve-kyc	0.010s
ok  	github.com/project/auth-service/cmd/onboard-reviewer	0.010s
ok  	github.com/project/auth-service/internal/config	0.002s
ok  	github.com/project/auth-service/internal/handlers	50.079s
ok  	github.com/project/auth-service/internal/models	0.002s
ok  	github.com/project/auth-service/internal/otp	0.003s
ok  	github.com/project/auth-service/internal/otpcrypto	0.001s
ok  	github.com/project/auth-service/internal/storage	0.002s
ok  	github.com/project/auth-service/internal/store	1.020s
exit=0
== services/chat-service: go test -count=1 ./...
ok  	github.com/project/chat-service/cmd/onboard-agent	0.303s
ok  	github.com/project/chat-service/internal/chat	0.447s
ok  	github.com/project/chat-service/internal/config	0.002s
ok  	github.com/project/chat-service/internal/handlers	26.454s
ok  	github.com/project/chat-service/internal/store	3.106s
exit=0
== services/notification-service: go test -count=1 ./...
ok  	github.com/project/notification-service/internal/config	0.002s
ok  	github.com/project/notification-service/internal/fcm	0.093s
ok  	github.com/project/notification-service/internal/handlers	0.848s
ok  	github.com/project/notification-service/internal/hub	0.526s
ok  	github.com/project/notification-service/internal/store	2.015s
ok  	github.com/project/notification-service/internal/templates	0.002s
exit=0
== services/user-service: go test -count=1 ./...
ok  	github.com/project/user-service/internal/config	0.001s
ok  	github.com/project/user-service/internal/handlers	207.552s
ok  	github.com/project/user-service/internal/models	0.003s
ok  	github.com/project/user-service/internal/store	11.616s
exit=0
```

Grep proof, after commit 9:
```
$ grep -rn "\$%" services --include=*.go
exit=1
```
Before commit 9 the same grep matched only test messages
(`trip_distance_pricing_repro_test.go`, `employee_dispatch_pricing_test.go`). Outside tests the
count was `0`. The only `$` in `templates.go` is the doc comment `Never "$".`.
`TestTemplates_NoDollarSign` checks every template.

E2E (`tests/e2e`, not run by `make check`; run by hand against the local staging Mongo /
Redis containers):
```
=== RUN   TestPushL10N_DeviceLanguagePerToken
--- PASS: TestPushL10N_DeviceLanguagePerToken (2.45s)
PASS
ok  	github.com/project/tests/e2e	2.451s
```
Same test without the item 6 fix (`cmd/main.go` stashed):
```
    push_l10n_test.go:347: 0 of 3 pushes sent
        2026/10/28 12:06:19 [FCM-PUSH] Failed to fetch device tokens for user cust-l10n-1793178377408479016: Get "https://127.0.0.1:43931/auth/user?id=cust-l10n-1793178377408479016": tls: failed to verify certificate: x509: certificate signed by unknown authority
--- FAIL: TestPushL10N_DeviceLanguagePerToken (16.74s)
FAIL
FAIL	github.com/project/tests/e2e	16.743s
```
`TestSenders_AddTemplateParams` without the item 2 fix (`jobs_handlers.go` stashed):
```
--- FAIL: TestSenders_AddTemplateParams (0.04s)
    notify_l10n_test.go:124: cancellation_resolved approved: {Type:cancellation_resolved UserID:emp-1 Title:Cancellation Request approved Body:Your cancellation request for job job-1 was declined by the business owner. You remain assigned. Params:map[variant:accept]}
FAIL
FAIL	github.com/project/user-service/internal/handlers	0.045s
```
`TestDeviceToken_LocalePerToken` ran against the local Mongo (`--- PASS: TestDeviceToken_LocalePerToken (0.54s)`),
not skipped.

New tests per item: auth `models_test.go` (`TestNormalizeDeviceLocale`),
`handlers/device_token_locale_test.go`; notification `hub/push_target_test.go`,
`hub/push_l10n_test.go`, `templates/templates_test.go` (every key × both languages, fallbacks,
money, no `$`), `handlers/push_params_test.go`, `handlers/history_texts_test.go`,
`store/params_roundtrip_test.go`; user `handlers/notify_l10n_test.go`; chat
`handlers/ticket_notify_params_test.go`; auth `kyc_review_outcome_test.go` /
`account_suspension_test.go` gained params asserts; frontend `test/services/push_locale_test.dart`
(fake messaging adapter + `PushLocaleSync` widget test); `tests/e2e/push_l10n_test.go`.

## Unverified
- **No phone**: no real Arabic / English push was seen on a device; only the fake FCM messages
  (e2e) and the unit tests. Android shows `notification.title` / `body` as sent, so the e2e
  messages are what a phone would show, but that last step was not seen.
- **The real accept flow** was not run end to end. The e2e posts the payload that user-service's
  `broadcastCourierAccepted` builds (pinned by `TestSenders_AddTemplateParams`); it does not run
  user-service dispatch.
- **Staging stack and CI**: the services' Docker images were not rebuilt and the staging stack
  was not started (only its Mongo / Redis containers were running). GitHub Actions was not run.
  The e2e is not part of `make check`.
- The item 6 TLS fix is verified against the real auth-service binary with test certificates,
  not against production's certificates.

## Follow-ups / out-of-lane findings
- **Stale-token cleanup cannot work against the real auth-service**:
  `HTTPDeviceTokenFetcher.UnregisterStaleToken` posts `{token, action: "unregister"}` with only
  `X-Internal-Token`. `POST /auth/device-token` requires a user JWT (`authenticateUser`), so
  auth-service answers 401, and the request names no user anyway. PUSH-BE's e2e used a fake
  auth-service that accepted it. A fix needs an internal unregister path (endpoint / auth change,
  APPLICATION_MAP). Owner decision; not done here.
- **Customers do not see job notifications in history or SSE**: job notifications are stored
  with `tenant_id` = the owner's id (user-service `job.OwnerID`), and customers are created with
  an empty `tenant_id` (auth-service sets it only for owners). `ListForUser` and the SSE
  `deliverLocal` both require the reader's tenant (or `global`), so a real customer's
  `job_accepted` / `job_picked_up` / … never appear in the in-app list or live stream. Push is
  not affected. The e2e journeys (and this task's e2e) seed customers inside the owner's
  tenant, which hides it. Found by reading the code during item 6; not reproduced in the app.
  Needs a routing decision (e.g. match `user_id` regardless of tenant).
- **App rendering**: the app could show the list in the current language from `texts` and drop
  its English-body parsing (`jobIdFromBody`, `ticketIdFromBody`, `contains('approved')`) in
  favour of `data.job_id` / `params`. Out of this lane (frontend was limited to the token call
  and the language change).
- `scripts/ci-lock.sh` is not executable in this worktree (`Permission denied`); I ran it with
  `bash scripts/ci-lock.sh …`.
- Docs to fold in: `docs/frontend/STATUS.md` (no new screen / provider / model file;
  `PushLocaleSync` is in `lib/services/push_notification_service.dart`), changelog entries for
  the two fixes.

## Open questions
- none
