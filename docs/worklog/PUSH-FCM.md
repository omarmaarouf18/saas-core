# Worklog: PUSH-FCM — Android push notifications end to end

## Task and scope
- Task ID: PUSH-FCM
- Item IDs covered: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
- Allowed paths (lane from the task prompt): `frontend/**` (incl. `pubspec.yaml` / `pubspec.lock`,
  granted by item 1, and `frontend/.github/workflows/build-apk.yml`, item 6), this worklog. Not
  `services/**` (read only, item 5), not the WF-RELEASE paths (Makefile, scripts/**, .githooks/**,
  .github/workflows/ci.yml, docs/RELEASE.md, docs/WORKFLOW.md). One line outside `frontend/`:
  `DESIGN.md` (dependency version quote), forced by the docgen drift test (see item 1).
- Agent branch: agent/PUSH-FCM-android-push. The worktree was created at the BE-GAPS-FIX merge
  (144d945d), before PUSH-BE was merged. With the owner's approval in chat, the empty branch was
  fast-forwarded (`git rebase logic-exploitation`, no commits of its own yet) to ccdee0ab
  (PUSH-BE merge) before any work. `logic-exploitation` has since moved to fcee43be (WF-RELEASE
  merge: scripts, Makefile, CI, docs only; no file in common with this branch), so the branch
  needs the usual rebase at integration.

## Decisions taken
- **Versions (item 1), all pinned exactly:**
  - `firebase_core 4.15.0` + `firebase_messaging 16.7.0`: one FlutterFire release (2026-09-14), the
    newest line before the 5.x / 17.x majors (2026-10-15/23, too new). Both need Flutter >= 3.27
    (pinned 3.44.6). The old 2.32 / 14.9 predate AGP 9.
  - `flutter_local_notifications 22.3.1` (2026-09-13): needed. FCM shows nothing while the app is
    open, and firebase_messaging cannot create a channel with a localized name. 22.3.2 / 22.3.3
    (Oct) were too recent; 23.x is dev only. It needs core library desugaring
    (`desugar_jdk_libs 2.1.4`, the version its README documents).
  - `web_socket_channel 3.0.3` (was ^2.4.5): **forced**. 2.x needs `package:web` 0.5, and both new
    deps need `web` ^1. `IOWebSocketChannel` code is unchanged, and the chat / tracking tests pass.
    `DESIGN.md` quotes the version, and the docgen test `TestPubspecDependenciesInDesignDoc`
    blocked the first gate run until the quote was aligned.
  - Google Services Gradle plugin `4.5.0` (2026-06), declared `apply false` in settings and applied
    in `app/build.gradle.kts` only when `google-services.json` exists.
- **Channel** `qd_default`: high importance, created on the first frame (`PushChannelSync` in
  `MaterialApp.builder`) with the localized name "Order updates" / "تحديثات الطلبات". It is renamed
  when the app language changes. The manifest also names it as the Firebase default channel, and
  `ic_stat_notification` (Material "local_shipping", white vector) as the default icon, with the
  brand gold accent.
- **Firebase init**: `initPushFirebase()` runs before `runApp` (5 s timeout) and is guarded. With no
  config, an unsupported platform or any error, it logs one line, `[PUSH] push disabled: …`, and the
  app is otherwise unchanged.
- **Service shape**: one `PushNotificationService` (now a ChangeNotifier) is created in `main`,
  passed to `AuthProvider` and provided above the app. Widgets read it with the nullable
  `context.read<PushNotificationService?>()`, so the existing page harnesses (whose fake
  `AuthProvider`s use `noSuchMethod`) need no change and show no push UI.
- **Sign-in never waits for push**: `onSignedIn()` is `unawaited` in login / OTP / session restore,
  and every token and API call is time-boxed (15 s). The token is no longer logged in release
  builds. Debug builds log it once (`[FCM] token (debug build only)`) for the Firebase console test.
- **Permission prompt**: an in-app sheet ("Turn on notifications?", with role-specific copy)
  appears 2 s after a role shell first shows, never on the launch or sign-in screens. It is shown
  only when push is available, Android reports `notDetermined` (firebase_messaging 16.7 tells "never
  asked" from "denied permanently" on Android 13+), and the prompt was not answered. "Not now" or
  closing the sheet counts as an answer. The answer lives in secure storage, which sign-out clears
  (`deleteAll`), so a fresh sign-in may offer it once more if the phone was never asked. Denial: no
  nagging, only the account page row and hint.
- **Account page (all roles)**, App section: a "Phone notifications: On / Off" row. Tapping it asks
  again while Android still allows that, else opens the app's notification settings
  (`openAppNotificationSettings`). A hint with "Open settings" shows when notifications are refused.
  The permission is re-read on resume. Both are hidden when push is unavailable in the build.
- **Foreground**: `PushTapHandler` (existing FE-BE-GAPS code in each shell) now shows the push as a
  local notification on `qd_default`. The text is the app's localized copy for the type
  (`notificationCopy`), and the local id comes from the notification id. The payload is the
  notification JSON, so a tap (app running, or a launch after it was killed) goes through
  `NotificationTapRouter.deliverTap`, i.e. the same role-checked links (not forked). The old in-app
  SnackBar with "View" stays as the fallback where a local notification cannot be shown (tests, iOS
  until enabled). The list and badge update at once through `NotificationTapRouter.onForeground →
  NotificationsProvider.addFromPush` (deduped by id with SSE). For that, `NotificationsProvider` is
  now created in `main` and provided with `.value`.
- **Background / killed**: the system shows the server's notification. `pushBackgroundHandler` is
  top-level with `@pragma('vm:entry-point')`, registered after init, and does nothing, because every
  server push has a `notification` part.
- **Payload**: `event_type` is read first, then `type`, then `system` (`NotificationModel.typeOf`),
  for push data and also for SSE / history JSON.
- **Expired session** (found during item 5): `forceLogout` cannot call `/auth/device-token`, so it
  deletes the FCM token on the phone. FCM then answers the next send with UNREGISTERED and
  notification-service drops the token. Separate commit "item 3 (follow-up)".
- **Device-token platform** (item 8): sent lowercased. `TargetPlatform.iOS.name` is `iOS`, which
  auth-service's whitelist (`android`, `ios`, `web`) rejects with a 400.
- **CI (item 6)**: a wrong `GOOGLE_SERVICES_JSON_B64` (not for `com.saascore.frontend`) **fails** the
  job rather than shipping an APK whose push silently never works. A missing secret warns and
  builds.
- **Photo cache (item 9)**: the store learns key → `photo_version` from services and from the upload
  response. Since the version is a function of the key, the mapping cannot go stale. Requests send
  `?v=`; the cache key is service|key|version. Without a version (older server) behaviour is
  unchanged.

## Changes per commit (message only — NO SHAs)
1. `PUSH-FCM: item 2 (part 1) - never track the Firebase client config`
2. `PUSH-FCM: item 1 - pin Firebase and local notification deps for Flutter 3.44.6`
3. `PUSH-FCM: item 2 - Android push wiring: optional Google Services plugin, channel, icon`
4. `PUSH-FCM: item 3 - Firebase init, permission prompt, token lifecycle`
5. `PUSH-FCM: item 4 - receive: foreground local notification, list, taps`
6. `PUSH-FCM: item 3 (follow-up) - an expired session also stops pushes`
7. `PUSH-FCM: item 6 - CI: google-services.json from GOOGLE_SERVICES_JSON_B64`
8. `PUSH-FCM: item 7 - docs: frontend/docs/PUSH.md`
9. `PUSH-FCM: item 8 - iOS-ready push code, "iOS later" in PUSH.md`
10. `PUSH-FCM: item 9 - service photo: ?v=<photo_version>, cache keyed by it`
11. `PUSH-FCM: item 10 - notification_rules.dart: events as sent today`
12. `PUSH-FCM: worklog`

Items 5 (read-only check), 11 (tests and goldens, committed inside each item) and 12 (manual test
plan, below) have no commit of their own.

## Verification
`make check` passed before every commit (`make commit` refuses otherwise). Literal last lines per
commit, as captured. Lines my output filter dropped are marked "not captured".
- gitignore (item 2 part 1): `00:47 +1319: All tests passed!` /
  `== pre-push gate: all checks passed (scope: docgen frontend) ==`. `git status` after the
  commit showed a clean tree (the config file is no longer listed); `git check-ignore -v`:
  `frontend/.gitignore:54:/android/app/google-services.json	frontend/android/app/google-services.json`
- item 1: the first run was BLOCKED:
  `structural_drift_test.go:118: Dependency version mismatch for "web_socket_channel": DESIGN.md quotes "^2.4.5" but frontend/pubspec.yaml specifies "3.0.3". Please align them.`
  After aligning DESIGN.md: `No issues found! (ran in 3.0s)` / `01:14 +1319: All tests passed!` /
  `== pre-push gate: all checks passed (scope: docs infra-tests docgen frontend) ==`
- item 2: `No issues found! (ran in 2.5s)` /
  `== pre-push gate: all checks passed (scope: docs infra-tests docgen frontend) ==` (test count
  line not captured)
- item 3: `No issues found! (ran in 3.3s)` /
  `== pre-push gate: all checks passed (scope: docs infra-tests docgen frontend) ==` (test count
  line not captured)
- item 4: `No issues found! (ran in 1.7s)` / `00:33 +1374: All tests passed!` / gate passed
- item 3 follow-up: `No issues found! (ran in 1.6s)` / `00:36 +1375: All tests passed!` / gate passed
- item 6: `all apk channel checks passed` / `No issues found! (ran in 1.7s)` /
  `00:36 +1375: All tests passed!` / gate passed
- item 7: `No issues found! (ran in 1.7s)` / `00:38 +1375: All tests passed!` / gate passed
- item 8: `No issues found! (ran in 1.7s)` / `00:36 +1376: All tests passed!` / gate passed
- item 9: `No issues found! (ran in 1.6s)` / `00:38 +1382: All tests passed!` / gate passed
- item 10: `No issues found! (ran in 1.8s)` / `00:36 +1382: All tests passed!` / gate passed
- Release APK builds, `flutter build apk --release` in `frontend/`:
  - after item 1 (deps only): `✓ Built build/app/outputs/flutter-apk/app-release.apk (60.7MB)`, `exit=0`
  - item 2, with the file: `✓ Built build/app/outputs/flutter-apk/app-release.apk (60.7MB)`, `exit=0`,
    60725860 bytes, `build/app/generated/res/processReleaseGoogleServices/values/values.xml`
    generated (google_api_key, google_app_id, …)
  - item 2, without the file (moved to the scratchpad, restored by a trap):
    `✓ Built build/app/outputs/flutter-apk/app-release.apk (60.7MB)`, `exit=0`, 60720968 bytes
  - final tree, without the file: `✓ Built build/app/outputs/flutter-apk/app-release.apk (61.0MB)`,
    `exit=0`, 60966892 bytes; a rebuild without the file:
    `firebase value strings in APK: 0`
  - final tree, with the file: `✓ Built build/app/outputs/flutter-apk/app-release.apk (61.0MB)`,
    `exit=0`, 60971784 bytes; `resources.arsc` contains `google_app_id`, `project_id`,
    `ic_stat_notification`, `notification_accent`
  - Gradle warns, on every build:
    `WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): firebase_core, package_info_plus`
    (see Follow-ups)
- CI step (item 6), simulated locally: the step's `run` was extracted from the YAML and run in a
  scratch directory with fake `GITHUB_OUTPUT` / `GITHUB_STEP_SUMMARY`:
  - secret = the real file, base64: `push=enabled`, the decoded file identical to the local one
  - no secret: `::warning::GOOGLE_SERVICES_JSON_B64 is not set: push disabled in this build`,
    `push=disabled`, and the summary line
    `> ⚠️ **push disabled in this build**: the GOOGLE_SERVICES_JSON_B64 secret is not set, so the APK has no Firebase config (frontend/docs/PUSH.md).`
  - wrong package: `::error::GOOGLE_SERVICES_JSON_B64 is not a google-services.json for com.saascore.frontend`, `exit=1`
  - `actionlint` reports nothing for the new step. Its shellcheck notes (SC2086, SC2129) are all in
    pre-existing steps (lines 66, 107, 186). `bash scripts/test_apk_channel.sh`:
    `all apk channel checks passed`.
- New tests: `test/services/local_notifications_test.dart` (channel args, show args, launch
  payload, guards), `test/services/push_notification_service_test.dart` (register / refresh /
  unregister, forced logout, platform name, login not blocked by a hanging getToken, permission
  flow, init without config / timeout / unsupported / configured, background handler),
  `test/features/account/push_permission_test.dart` (prompt and account row / hint widget tests,
  goldens), `test/features/account/push_receive_test.dart` (event_type vs type, payload round trip,
  router display / launch, addFromPush, foreground → local notification → tap → order page, notice
  fallback), `test/providers/service_photo_version_test.dart`, `test/helpers/fake_push.dart`.
  `test/default_push_adapter_test.dart` and `test/fcm_push_registration_test.dart` were updated
  for the new adapter API.
- Goldens: **6 new**, none changed (`git diff --stat logic-exploitation...HEAD -- '*.png'` lists
  only these):
  `test/features/account/goldens/push_prompt_{en_ltr,ar_rtl,dark_en_ltr}_360x800.png` and
  `push_account_off_{en_ltr,ar_rtl,dark_en_ltr}_360x800.png`. The existing account / shell goldens
  are unchanged because their harnesses provide no PushNotificationService (row hidden, no prompt).

## Item 5 — server contract check (read only)
Read: `services/notification-service/internal/fcm/fcm.go` (message build), `internal/hub/hub.go`
(push fan-out, `dataMap`), `services/user-service/internal/handlers/jobs_handlers.go`
(`notifyJobEvent` and its callers, `job_accepted`, `job_offer`),
`services/auth-service/internal/handlers/auth.go` (`DeviceToken`).

Matches what the app reads:
- `data`: `id`, `type`, `tenant_id` always; `job_id` + `event_type` only with a job id; all strings.
- `android.notification.channel_id = "qd_default"`, `android.priority = "HIGH"`, and
  `notification.title` / `body`.
- Device token: `POST /auth/device-token {token, platform, action}`. Unregister is
  `action: "unregister"` (with the token, or empty for the user's tokens per the store).

Mismatches / limits (backend, not fixed here, out of lane):
1. **Title / body language**: user-service sends English only ("New Booking", "Courier Picked Up",
   "Delivered", "Booking Cancelled", "Courier Assigned"). When the app is in the background or
   killed, the system shows them as sent; Arabic users see English. The app localizes only
   foreground pushes. A fix needs the user's language on the server (or Android
   `title_loc_key` / `body_loc_key` with app string resources).
2. **`job_accepted` body** shows the fare with a `$` sign ("Final fare: $%.2f").
3. **Push only to explicit users**: notifications without `user_id` / `user_ids` (role or tenant
   broadcasts) are streamed over SSE but never pushed.
4. **Platform `iOS`**: the app sent `defaultTargetPlatform.name`; iOS would be `iOS`, which
   auth-service rejects (400). Fixed on the app side (item 8: lowercased). The server is unchanged.
5. No `apns` block in the FCM message. That is fine for alerts once iOS is enabled; a sound or badge
   would need one (noted in PUSH.md "iOS later").

## Item 12 — manual test plan addendum
Prerequisites: a release APK built **with** the config (CI with the secret, or locally with
`android/app/google-services.json`). Production notification-service log shows
`[FCM] push enabled (project qd-app-9687c, token ok)`. Three accounts: customer, owner (approved,
with a service) and courier (approved, on the owner's team). Use two or three Android phones; one
should run Android 13+ (permission dialog) and, ideally, one should be a Xiaomi / Samsung (battery
behaviour). "Open" = app in the foreground, "background" = home button, "killed" = swiped from
recents (not Force stop).

Permission (Android 13+):
1. Fresh install, sign in. The shell shows; after about 2 s the "Turn on notifications?" sheet
   appears (copy per role). Not on the language / sign-in screens.
2. "Not now" → no system dialog. Account → App: "Phone notifications: Off", hint with "Open
   settings". Sign out and back in: the sheet may appear once more (sign-out clears the answer).
3. "Turn on" → system dialog → Allow → row "On", no hint.
4. Deny twice (system) → row "Off", hint. Tapping the row or "Open settings" opens the app's
   notification settings. Allow there, come back → row "On" (re-read on resume).
5. Settings → Apps → Quick Delivery → Notifications lists the channel "Order updates" (Arabic name
   when the app language is Arabic; switch the language in the app and check it is renamed).

Per role, each step in each state (open / background / killed):

| Step | Phone | Expected |
|---|---|---|
| Customer books | owner | "New Booking" (open: "Order placed" in the app language). Tap → that order's detail. |
| Owner offers the job | courier | job offer (open: "New job offer"). Tap → Task tab. |
| Courier accepts | customer | "Courier Assigned" (open: "A courier accepted your order"). Tap → that order. |
| Courier picks up | customer | "Courier Picked Up" (open: "Your order was picked up"). Tap → that order. |
| Courier delivers | customer | "Delivered" (open: "Your order was delivered"). Tap → that order. |
| Owner cancels a booking | customer | "Booking Cancelled" (open: "Your order was cancelled"). Tap → that order. A customer cancelling their own order gets nothing. |

For every row:
- Open: a system notification with the van icon appears and the bell badge / list gains the item
  at once (no duplicate when SSE also delivers it).
- Killed: the tap opens the app, restores the session, then the order.
- Another account's job or a deleted job → "We couldn't open that order…" and the role's order
  list.

Logout:
1. Sign out on the customer phone, then repeat "Courier picks up": no push. The
   notification-service log shows `user … has no registered device tokens`, or the token removed as
   stale.
2. Session expiry (e.g. revoke the refresh token, or wait out the session): the app returns to
   sign-in; the next push to that user is not shown, and the server log shows the stale-token
   cleanup.

Build without config (e.g. local `flutter build apk --release` without the file): the app works;
no prompt, no "Phone notifications" row; the log has `[PUSH] push disabled: Firebase not configured
in this build (…)`.

## Unverified
- **No device or emulator**: `adb devices` listed none (`flutter devices`: Linux desktop and Chrome
  only). So no real token registration, no Firebase console test message, no permission dialog,
  channel, local notification, tap or battery behaviour was seen on a phone. Everything on-device
  is covered by unit / widget tests with fakes only. The plugin calls (`createNotificationChannel`,
  `show`, `getNotificationAppLaunchDetails`) are checked against a mocked method channel.
- The real CI run of `build-apk.yml` with / without the secret was not run. Only the step's script
  was simulated locally (above).
- Production delivery (server key + this app) was not exercised end to end.
- The Linux desktop build (FE-LINUX-BUILD) was not rebuilt. flutter_local_notifications adds a
  Linux plugin; the push code itself skips non-Android / iOS platforms.
- iOS: nothing built or run (by design, item 8).

## Follow-ups / out-of-lane findings
- Backend: localized push title/body; the `$` in `job_accepted`; push for broadcasts (item 5,
  mismatches 1–3).
- `firebase_core` (and, before this task, `package_info_plus`) apply the Kotlin Gradle Plugin, and
  Flutter warns that future versions will fail to build such apps. The firebase_core 5.x changelog
  does not mention a change yet. Re-check when bumping Flutter.
- iOS deployment target is 13.0; firebase_messaging 16.7 needs 15.0 when iOS is enabled.
- `docs/frontend/STATUS.md` / changelog: new files `lib/services/push_setup.dart`,
  `lib/services/local_notifications.dart`,
  `lib/features/account/notifications/push_permission_prompt.dart`, `frontend/docs/PUSH.md` for the
  owner to fold in.

## Open questions
- none
