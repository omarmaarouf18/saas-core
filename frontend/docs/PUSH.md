# Push notifications

Android push for the Quick Delivery app (PUSH-FCM), on top of the backend
work in PUSH-BE / BE-GAPS-FIX. iOS is prepared but not enabled (see
[iOS later](#ios-later)).

---

## 1. How it works

```
user-service ──POST /notifications/send──▶ notification-service (hub)
   (job events, title/body, job_id)          │ stores it, SSE to open apps,
                                             │ and for each device token of
                                             │ the target user:
                                             ▼
                                   FCM HTTP v1 (OAuth2, service-account key)
                                             │
                                             ▼
                                  the phone (Firebase Messaging)
```

### What the server sends

One FCM message per registered device token of the notification's user
(`user_id`; broadcasts to a role or tenant without a user are never pushed):

| Part | Value |
|---|---|
| `notification.title` / `.body` | The server's text, in English (e.g. "Courier Picked Up") |
| `data` | `id`, `type`, `tenant_id` always; `job_id` and `event_type` (= `type`) for job notifications. All strings. |
| `android.priority` | `HIGH` |
| `android.notification.channel_id` | `qd_default` |

Job events and who gets them:

| Event (`event_type`) | Recipient | Sent by |
|---|---|---|
| `job_booked` | owner | user-service, on every new booking |
| `job_offer` | courier | owner dispatch / offer |
| `job_accepted` | customer | courier accepts |
| `job_picked_up` | customer | courier picks up |
| `job_delivered` | customer | job completed (COD and escrow) |
| `job_cancelled` | customer | cancelled by someone else (owner, approved courier request, system) |
| `cancellation_requested`, `cancellation_request_expired`, `cancellation_resolved`, `dispute_resolved` | owner / courier | cancellation flow |

There is no `job_in_transit`: "picked up" is the in-transit event.

### What the app does

| When | What happens | Code |
|---|---|---|
| App start | `Firebase.initializeApp()` before `runApp`, guarded: a build without `google-services.json`, an unsupported platform or any error logs one line (`[PUSH] push disabled: …`) and the app runs with push off. On success the top-level background handler is registered. | `lib/services/push_setup.dart` |
| First frame | The `qd_default` channel is created (high importance), named in the app language ("Order updates" / "تحديثات الطلبات"), renamed when the language changes. | `PushChannelSync`, `lib/services/local_notifications.dart` |
| Sign-in (login, OTP, session restore) | Reads the permission, registers the token (`POST /auth/device-token {token, platform: "android"}`), follows `onTokenRefresh`. Never awaited: sign-in never waits for or fails on push; every call is time-boxed. | `PushNotificationService.onSignedIn` |
| ~2 s after a role shell first shows | Once per install (cleared by sign-out): a sheet "Turn on notifications?" with role-specific copy. "Turn on" opens the Android 13+ system dialog; "Not now" or closing it is remembered. Not shown when push is off, the phone was already asked, or notifications are already allowed (Android 12 and older). | `PushPermissionPrompt` |
| Account page → App | "Phone notifications: On / Off" row (asks again while Android still allows it, else opens the app's notification settings) and, when refused, a hint with "Open settings". Re-read when the app resumes. Hidden when push is off in the build. | `pushSettingsTile`, `PushOffHint` |
| Push, app open | Added to the notifications list and badge at once (deduped with the live stream by id), and shown as a system notification on `qd_default` with the app's own localized title/body for the type. | `PushTapHandler`, `NotificationsProvider.addFromPush` |
| Push, app in background or killed | Android shows the server's title/body on `qd_default` with the small icon `ic_stat_notification`. The background handler does nothing (every push has a `notification` part). | Firebase Messaging |
| Tap (any state) | The FE-BE-GAPS links: `event_type` (else `type`) + `job_id`, role-checked. A job that is gone or not the user's → "We couldn't open that order…" and the role's order list. A cold-start tap waits until the session is restored. | `NotificationTapRouter`, `notification_rules.dart` |
| Sign-out | `POST /auth/device-token {action: "unregister"}` and the token is deleted on the phone. | `unregisterDeviceToken` |
| Session expired | No API call possible: the token is deleted on the phone; FCM answers the next send with `UNREGISTERED` and the server drops it. | `forgetLocalToken` |

---

## 2. Owner setup

Firebase project `qd-app-9687c`, Android app `com.saascore.frontend`.

1. **Firebase app.** Firebase console → Project settings → General → Your
   apps → the Android app `com.saascore.frontend` → download
   `google-services.json`. (A new project: Add app → Android, package name
   `com.saascore.frontend`, then download.)
2. **Local builds.** Put the file at `frontend/android/app/google-services.json`.
   It is in `frontend/.gitignore`; `git status` must never list it. Never
   commit it: this folder is mirrored to the public mobile repository. Without
   the file the app still builds and runs, with push off (Gradle prints
   `push disabled in this build`).
3. **CI (GitHub secret).** In `omarmaarouf18/quick-delivery-mobile` →
   Settings → Secrets and variables → Actions, secret
   `GOOGLE_SERVICES_JSON_B64` = the file, base64 on one line (already set):

   ```bash
   base64 -w0 frontend/android/app/google-services.json | gh secret set GOOGLE_SERVICES_JSON_B64 --repo omarmaarouf18/quick-delivery-mobile
   ```

   (macOS: `base64 -i frontend/android/app/google-services.json | gh secret set …`.)
   `build-apk.yml` decodes it before the builds and fails if it is not the
   config for `com.saascore.frontend`. Without the secret the build succeeds
   and the run summary says **push disabled in this build**; every run's
   summary has a "Push" line.
4. **Server key.** notification-service needs the Firebase service-account
   key of the **same** project: [docs/DEPLOYMENT.md](../../docs/DEPLOYMENT.md)
   §9.4 (already installed in production; its log says
   `[FCM] push enabled (project qd-app-9687c, token ok)`).

---

## 3. How to test

### 3.1 One device, Firebase console

1. Build and install a **debug** build with the config file
   (`flutter run`), sign in. The log prints
   `[FCM] token (debug build only): <token>` (release builds never log it).
   For a release build, read the token from the database instead:

   ```bash
   docker compose exec mongo mongosh -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin "${AUTH_MONGO_DATABASE:-auth_db}" --quiet --eval 'db.users.findOne({email: "<your email>"}, {device_tokens: 1})'
   ```

2. Firebase console → Messaging → New campaign → Notifications → title and
   text → **Send test message** → paste the token → Test.
3. App in the background: the notification appears with the van icon in
   the "Order updates" channel. App open: the app shows it itself (same
   channel). Tapping it opens the app (no job: it just opens).

The server path (notification-service → FCM) has its own check:
DEPLOYMENT.md §9.4 step 6.

### 3.2 Real job flow, per role

Three accounts on two or three phones (customer, owner, courier). For each
event, try the app **open**, **in the background** (home button) and
**killed** (swiped away from recents):

| Step | Phone that gets the push | Tap opens |
|---|---|---|
| Customer books a service | owner: "New Booking" | that order's detail (owner) |
| Owner offers the job to a courier | courier: job offer | the Task tab |
| Courier accepts | customer: "Courier Assigned" | that order |
| Courier picks up | customer: "Courier Picked Up" | that order |
| Courier delivers | customer: "Delivered" | that order |
| Owner cancels a booking | customer: "Booking Cancelled" | that order |

App open: the notification is in the app language and the bell / list
shows it at once. Background or killed: the server's English text (see
§5). Then sign out on the customer phone and repeat a step: no push
arrives.

---

## 4. Troubleshooting

| Symptom | Check |
|---|---|
| No token, log `[PUSH] push disabled: Firebase not configured in this build` | The build has no `google-services.json`. CI: the run summary's Push line; set the secret (§2.3). |
| `FCM getToken error: … SERVICE_NOT_AVAILABLE` / `MISSING_INSTANCEID_SERVICE` | No Google Play services (emulator without a "Google APIs"/"Google Play" image, de-Googled phone) or no network. Push cannot work there; the app works without it. |
| Token registered, nothing arrives | notification-service log (`docker logs saas-notification-service \| grep FCM`): `no registered device tokens` (other account / token not registered), `SENDER_ID_MISMATCH` / `PERMISSION_DENIED` (server key from another Firebase project than the app's `qd-app-9687c`), `push disabled` (key, §9.4). |
| Permission denied | Account page shows "Phone notifications: Off" and the hint. Android shows its dialog at most twice; after that only Settings → Apps → Quick Delivery → Notifications (the hint's "Open settings") can turn it on. |
| Arrives silently / no heads-up | Settings → Apps → Quick Delivery → Notifications → "Order updates": allowed, "Alert"/"Pop on screen". Android fixes a channel's importance when it is created; if a user lowered it, only they (or a reinstall) can raise it. |
| Nothing while the app is closed on some phones (Xiaomi, Huawei, Oppo, Vivo, Samsung "sleeping apps") | Battery optimisation: set the app's battery use to "Unrestricted" / "No restrictions", allow Autostart (MIUI), remove it from "Sleeping apps". An app that was **force-stopped** (Settings → Force stop, or some OEM "clean" buttons) gets no push until it is opened again. |
| Pushes keep coming after sign-out | Sign-out unregisters and deletes the token; an expired session deletes it on the phone and the server drops it on the next send (one more push may arrive). |
| Background push text is English | Known: the server sends English text (§5). The app localizes only what it shows itself (app open). |

---

## 5. Known server-side limits

From the contract check (PUSH-FCM item 5, read-only):

- `notification.title` / `body` are English strings from user-service; the
  system shows them as they are when the app is not open.
- The `job_accepted` body names a fare with a `$` sign.
- Notifications without a `user_id` (role / tenant broadcasts) are never
  pushed, only streamed to open apps.

---

## iOS later

The push code is platform-neutral: `initPushFirebase` already accepts iOS,
the permission goes through `FirebaseMessaging.requestPermission` (the iOS
dialog opens from the same prompt), the token is registered with platform
`ios`, and taps use the same router. Nothing iOS-specific is in the project
yet. To turn it on:

1. **Apple Developer Program** membership (paid) for the team that signs the
   app.
2. **APNs auth key.** developer.apple.com → Certificates, IDs & Profiles →
   Keys → + → "Apple Push Notifications service (APNs)" → download the
   `.p8` (once only), note its Key ID and the Team ID. Firebase console →
   Project settings → Cloud Messaging → Apple app configuration → upload
   the APNs authentication key with those IDs.
3. **Firebase iOS app.** Add app → iOS, bundle ID `com.saascore.frontend`
   (Runner's `PRODUCT_BUNDLE_IDENTIFIER`) → download
   `GoogleService-Info.plist` → `frontend/ios/Runner/GoogleService-Info.plist`
   (already in `frontend/.gitignore`) and add it to the Runner target in Xcode
   (Copy Bundle Resources). CI would write it from a secret, like Android.
4. **Xcode capabilities** (Runner target → Signing & Capabilities): **Push
   Notifications**, and **Background Modes → Remote notifications**.
5. **Deployment target.** firebase_messaging 16.7 needs iOS 15; the project
   is at 13.0 (`IPHONEOS_DEPLOYMENT_TARGET`, and `platform :ios` in the
   Podfile once one exists).
6. **Foreground display.** The local notifier is Android-only, so an iOS
   push that arrives while the app is open shows the in-app notice with
   "View". Optional: `FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true)`
   to show the system banner instead.
7. **Mac CI.** iOS builds need macOS with Xcode (a `macos-*` GitHub runner),
   signing certificate and provisioning profile as secrets, then
   `flutter build ipa`. The Linux runners used today cannot build iOS.
