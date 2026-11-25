# Store testing pipeline (Google Play + TestFlight)

STORE-PIPELINE. Puts the three ADR-0030 apps (Waddify `app.waddify`, Waddify
Console `app.waddify.console`, Waddify Employees `app.waddify.employees`) into
the stores' **testing** channels so testers can install them from Google Play
and TestFlight instead of side-loading APKs. Nothing in this pipeline releases
to production or submits for App Store review.

| Step | Android (Google Play) | iOS (TestFlight) | How |
|---|---|---|---|
| Internal testing | `internal` track | internal testers (App Store Connect users) | automatic on every push to `main` of the mobile repo |
| Closed testing | closed track (default `alpha`) | external tester groups (beta review on the first build of each version) | manual: **Store testing (promote to closed)** |

The GitHub-release APK channel (`build-apk.yml`, `app-release.json`) is
unchanged and still debug-signed. A phone that has the side-loaded APK must
**uninstall it** before installing the store build (different signing key,
same application ID).

---

## 1. Files

| File | What it does |
|---|---|
| `.github/workflows/store-testing.yml` | on push to `main` (and manual): builds AABs + IPAs, uploads to Play internal and TestFlight |
| `.github/workflows/store-promote.yml` | manual: Play internal → closed track; TestFlight → external groups |
| `.github/workflows/store-ios-signing.yml` | manual, once (and yearly): creates the iOS distribution certificate and profiles in match |
| `fastlane/Fastfile` | the lanes (`android internal/promote`, `ios setup_signing/internal/promote`) |
| `Gemfile` | Fastlane |
| `android/app/build.gradle.kts` | release signing with the upload key when configured |
| `ios/Runner.xcodeproj` | flavors: schemes `customer`, `console`, `employees`, configurations `Debug-/Release-/Profile-<flavor>` |

Paths are relative to `frontend/` (the root of the mobile repo, where the
workflows run).

---

## 2. One-time setup (owner)

### 2.1 Google Play

1. In Play Console create three apps: **Waddify**, **Waddify Console**,
   **Waddify Employees** (free, app). Finish the required "App content"
   declarations enough for testing tracks (privacy policy, data safety, ads,
   target audience, app access with a test login).
2. Create the upload key once and keep a backup outside the repo:
   ```bash
   keytool -genkeypair -v -keystore waddify-upload.jks -alias upload \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
   One upload key is used for all three apps. Play App Signing (default for
   new apps) keeps the real signing key at Google.
3. Google Cloud: create a service account, create a JSON key. Play Console →
   Users and permissions → invite the service account email, give it access to
   the three apps with **Release to testing tracks** (and view app info).
4. **First upload is manual** (Play API cannot create the first release):
   build one AAB per app locally with the upload key and upload it to
   Internal testing in the Console:
   ```bash
   cd frontend
   # android/key.properties: storeFile=/abs/path/waddify-upload.jks,
   # storePassword=..., keyAlias=upload, keyPassword=...
   for APP in customer console employees; do
     flutter build appbundle --release --flavor $APP --build-number=1 \
       --dart-define=APP_CLIENT=$APP --dart-define=APP_VERSION=3.0.0+1
   done
   # build/app/outputs/bundle/<app>Release/app-<app>-release.aab
   ```
   The pipeline's build numbers start above 10, so they never collide with
   this manual build 1.
5. Internal testing → Testers: create an email list (up to 100 people), copy
   the opt-in link and send it to testers. Closed testing: create the testers
   list on the closed track (`alpha`, "Closed testing - Alpha" by default).
6. Until each app has had one release reviewed, Play only accepts **draft**
   releases through the API. Set repository variable
   `PLAY_RELEASE_STATUS=draft` until then (drafts must be rolled out by hand
   in the Console), then remove it.

> New personal developer accounts must run a closed test with at least 12
> opted-in testers for 14 continuous days **before production access**. It
> does not limit internal or closed testing, which is all this pipeline does.

### 2.2 Apple

1. Certificates, Identifiers & Profiles → Identifiers: register
   `app.waddify`, `app.waddify.console`, `app.waddify.employees`.
2. App Store Connect → Apps → new app for each bundle ID (names: Waddify,
   Waddify Console, Waddify Employees; SKU any).
3. Users and Access → Integrations → App Store Connect API → new team key
   with role **Admin** (creating the Apple Distribution certificate through
   the API needs Admin; App Manager can upload and manage TestFlight but not
   create distribution certificates). Download the `.p8` once. Note the Key
   ID and the Issuer ID.
4. Create a **private** GitHub repo for match (suggested
   `waddify-ios-certificates`, empty) and install the existing GitHub App
   (`APP_ID`) on it with Contents: read and write.
5. TestFlight per app: create an internal group with **automatic
   distribution** on (internal testers must be App Store Connect users, up to
   100), and an external group named as in `TESTFLIGHT_EXTERNAL_GROUPS`
   (default `Closed testers`; App Store Connect shows the external option
   only after the first build is uploaded). Fill in Test Information (beta description,
   feedback email, contact, sign-in for review: a test account per app).
6. Run **Store testing (iOS signing setup)** with `confirm=create`. It
   creates the Apple Distribution certificate and the three App Store
   profiles and stores them encrypted in the match repo. Run it again only
   when the certificate expires (yearly) or after adding a bundle ID.

### 2.3 Secrets and variables (repo `quick-delivery-mobile`)

| Name | Kind | Value |
|---|---|---|
| `PLAY_SERVICE_ACCOUNT_JSON` | secret | the service account JSON key (raw JSON) |
| `ANDROID_UPLOAD_KEYSTORE_B64` | secret | `base64 -w0 waddify-upload.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | secret | keystore password |
| `ANDROID_KEY_ALIAS` | secret | `upload` |
| `ANDROID_KEY_PASSWORD` | secret | key password |
| `ASC_KEY_ID` | secret | App Store Connect API Key ID (Admin role) |
| `ASC_ISSUER_ID` | secret | Issuer ID |
| `ASC_KEY_P8_B64` | secret | `base64 -w0 AuthKey_XXXX.p8` |
| `MATCH_PASSWORD` | secret | passphrase that encrypts the match repo (keep a copy) |
| `APP_ID`, `APP_PRIVATE_KEY` | secret | existing GitHub App (also mints the match repo token) |
| `GOOGLE_SERVICES_JSON_B64` | secret | existing; Android push config |
| `APPLE_TEAM_ID` | variable | 10-character Team ID |
| `MATCH_REPOSITORY` | variable | match repo name, e.g. `waddify-ios-certificates` |
| `TESTFLIGHT_EXTERNAL_GROUPS` | variable | e.g. `Closed testers` (comma list) |
| `PLAY_CLOSED_TRACK` | variable | optional, default `alpha` |
| `PLAY_RELEASE_STATUS` | variable | optional, `draft` until the first review (§2.1.6) |
| `STORE_BUILD_NUMBER_OFFSET` | variable | optional, default `0` (§4) |
| `API_BASE_URL` | variable | existing; backend URL baked into builds |

A platform whose secrets are missing is **skipped with a warning**, so the
workflow stays green while the setup is incomplete.

---

## 3. Day to day

- **Internal**: merge to `main` in saas-core touching `frontend/**` → the
  subtree sync pushes the mobile repo → `store-testing.yml` uploads all three
  apps. Run it by hand (Actions → Store testing (internal) → Run workflow) to
  pick a platform or a subset of apps.
- **Closed**: Actions → **Store testing (promote to closed)**. Defaults
  promote the newest internal build of every app. Optional inputs: a Play
  version code, a TestFlight build number, groups, and the "What to Test"
  text. The first external TestFlight build of each version waits for
  Apple's beta review (usually under a day); later builds of the same
  version usually go out without review.
- Locally (needs the same environment variables as the workflow):
  `bundle exec fastlane android internal app:console`,
  `bundle exec fastlane ios promote app:customer groups:"Closed testers"`.

---

## 4. Version and build numbers

- Version name: the semver part of `pubspec.yaml` `version:` (ADR-0018), the
  same for all three apps.
- Build number: `STORE_BUILD_NUMBER_OFFSET + run_number × 10 + run_attempt`
  of `store-testing.yml`, the same for all three apps and both stores in one
  run. It only ever goes up. If the workflow is deleted and recreated
  (run_number restarts), set `STORE_BUILD_NUMBER_OFFSET` above the last
  uploaded number.
- `APP_VERSION` is `<version>+<build>`; the gateway version gate compares
  only the semver part.

---

## 5. Known limits

- iOS push is off: no `GoogleService-Info.plist`, no APNs key, no push
  entitlement yet (frontend/docs/PUSH.md, "iOS later"). The app starts
  without it.
- iOS uses one app icon for all three apps (Android has per-flavor icons).
- iOS purpose strings are English only.
- If the version gate forces an update, its `download_url` points to the
  Android APK, also on iOS and for Play testers (per-client gate is an open
  item in ADR-0030).
- `Gemfile.lock` is not committed yet: the first runs upload it as an
  artifact (`Gemfile.lock-android`/`-ios`); commit it to pin Fastlane.
