# Quick Delivery Platform — Flutter Mobile Client

This repository contains the standalone Flutter mobile frontend for the Quick Delivery multi-tenant SaaS platform.

> [!IMPORTANT]
> **Source of Truth Note**:
> This repository (`quick-delivery-mobile`) is automatically synced from the `frontend/` directory of the primary development repository ([omarmaarouf18/saas-core](https://github.com/omarmaarouf18/saas-core)) via an automated one-way push mirror workflow (`.github/workflows/sync-mobile-frontend.yml`).
> **Do not make manual commits directly in this repository's `main` branch** — any direct commits will be overwritten during the next automated sync. All mobile application source code changes, bug fixes, and feature developments must be submitted inside `saas-core`'s `frontend/` directory.

---

## 1. Backend Connectivity & System Context

This repository is **mobile-app-only**. All backend microservices, Go source code, MongoDB schemas, and infrastructure definitions live in external repositories:
* **Backend Source Code**: [omarmaarouf18/saas-core](https://github.com/omarmaarouf18/saas-core) (contains `api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`).
* **Production Deployment Infrastructure**: [omarmaarouf18/saas-core-deploy](https://github.com/omarmaarouf18/saas-core-deploy) (Docker Compose, Caddy TLS reverse proxy).

The application communicates with the backend via the API Gateway REST and WebSocket endpoints. By default, production release builds target `https://api.logiclinkeg.tech/api/v1`.

---

## 2. Local Development Setup

### Prerequisites
* **Flutter SDK**: `>=3.0.0 <4.0.0` (Recommended: Flutter stable channel)
* **Java JDK**: JDK 17 (e.g. Eclipse Temurin 17)
* **Android Development**: Android Studio with Android SDK Platform 36 and Android SDK Command-line Tools installed.
* **iOS Development**: macOS with Xcode and CocoaPods (for iOS targets).

### Installation & Execution
1. **Install dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run the application**:
   Ensure a connected device or active emulator is running (`flutter devices`), then run one of the three apps (see "Three apps" below):
   ```bash
   flutter run --flavor customer --dart-define=APP_CLIENT=customer
   ```

### Three apps from one codebase (ADR-0030)

The build produces three Android apps from this one project. Every Android build needs `--flavor`; without it Gradle builds no single APK and `flutter` stops with "Gradle build failed to produce an .apk file".

| Flavor / `APP_CLIENT` | Launcher name | Application ID | Roles it signs in | Sign-up |
| :--- | :--- | :--- | :--- | :--- |
| `customer` | Waddify | `app.waddify` | `user` | creates a customer |
| `console` | Waddify Console | `app.waddify.console` | `owner` | creates a business owner |
| `employees` | Waddify Employees | `app.waddify.employees` | `employee` | none (owners add their staff) |

- Always pass the same value twice: `--flavor X --dart-define=APP_CLIENT=X`. The flavor picks the application ID, launcher name and icon (`android/app/src/<flavor>/`); `APP_CLIENT` tells the Dart code which app it is (`lib/core/app_client.dart`). Release builds must pass both.
- Without `APP_CLIENT` the app uses the build flavor, else `customer` (tests, and `flutter run` on a non-Android target). An `APP_CLIENT` that names no app, or one that disagrees with `--flavor`, stops the app at start-up.
- A user whose role belongs to another app sees a page naming the right app, with a sign-out button. Every request sends `X-App-Client: <client>` next to `X-App-Version`.
- All three apps share one version number (`pubspec.yaml`).
- The three apps install side by side. Push needs all three package names in `google-services.json` (see [docs/PUSH.md](docs/PUSH.md)).

```bash
flutter run --flavor console --dart-define=APP_CLIENT=console
flutter run --flavor employees --dart-define=APP_CLIENT=employees
```

### Pointing at Custom Backend Environments
The mobile client uses compile-time environment configuration (`String.fromEnvironment('API_BASE_URL', ...)`) defined in `lib/core/api_client.dart`. Customize the target API endpoint using `--dart-define`:

```bash
# Android Emulator (Default Android AVD loopback); add the flavor + APP_CLIENT of the app you run
flutter run --flavor customer --dart-define=APP_CLIENT=customer --dart-define=API_BASE_URL=https://10.0.2.2:8080/api/v1

# Genymotion Emulator loopback
flutter run --dart-define=API_BASE_URL=https://10.0.3.2:8080/api/v1

# Physical Device on local network
flutter run --dart-define=API_BASE_URL=https://192.168.1.50:8080/api/v1

# Custom Staging Environment
flutter run --dart-define=API_BASE_URL=https://staging.yourdomain.com/api/v1
```

For detailed per-platform networking setups (including `adb reverse` port forwarding, iOS simulator loops, and dev-mode HTTPS certificate overrides), consult [CONNECTING_TO_BACKEND.md](CONNECTING_TO_BACKEND.md).

### Golden Baseline Policy (Flutter Version Contract)

Pixel goldens (`test/features/**/goldens/` for the pages, `test/ui/goldens/` for
the `/qd-gallery` components) are only valid for the Flutter engine build that
rendered them. The authoritative version is pinned in
`.github/workflows/ci.yml` (`flutter-version:`).

**Rule: any Flutter bump must regenerate the goldens in the same change.**

WHY (environment contract, not superstition): goldens are compared byte-for-byte
against PNGs produced by one specific Skia/engine build + OS font environment. A
baseline rendered under Flutter X fails under Flutter Y with small constant pixel
diffs (glyph anti-aliasing/hinting changes) even when no code changed — this was
the root cause of every historical "Flutter Lint & Test" failure (see
`docs/frontend/STATUS.md`). Matching the comparing environment to the generating
environment is what keeps them green; the rule keeps them matched permanently.

Regeneration procedure (CI-rendered, preferred):
1. Actions tab → "Regenerate Golden Baselines" → Run workflow (your branch).
2. Download the `ci-rendered-goldens` artifact (it holds `test/features/**/goldens/`
   and `test/ui/goldens/`).
3. Review the PNGs locally, copy them over the same folders, commit.

Locally (same Flutter version): `flutter test --update-goldens test/features test/ui`.

---

## 3. Automated CI/CD & Release APKs

This repository includes a continuous integration workflow (`.github/workflows/build-apk.yml`) that automatically compiles release APKs:

1. **Trigger**: Executes automatically whenever new commits land on `main` (via automated sync from `saas-core`).
2. **Build Configuration**: Flutter pinned to 3.44.6. Builds a universal release APK (`flutter build apk --release`, published as `app-release.apk`) and one APK per ABI (`--split-per-abi`: armeabi-v7a, arm64-v8a, x86_64), both with `--build-number=<run number>`, `API_BASE_URL` from the repository variable `vars.API_BASE_URL` (default `https://api.logiclinkeg.tech/api/v1`) and `APP_VERSION=<pubspec version>+<run number>` (sent as `X-App-Version`).
   > [!WARNING]
   > Since ADR-0030 every Android build needs `--flavor`. Until `build-apk.yml` builds the three apps (`--flavor X --dart-define=APP_CLIENT=X` for `customer`, `console`, `employees`), this workflow fails.
3. **Downloading Built APKs**:
   - Navigate to the **Actions** tab in this GitHub repository.
   - Click on the latest **Build Android APK** workflow run.
   - Scroll down to the **Artifacts** section to download `app-release-<short_sha>` (the three per-ABI APKs and the universal `app-release.apk`; most phones need `app-arm64-v8a-release.apk`).
   - Production tagged releases are also published under **Releases**.

Detailed CI/CD pipeline mechanics and sync architecture are documented in [docs/CI_CD.md](docs/CI_CD.md).

Push notifications (Firebase): how they work, the `google-services.json` setup (local file, never committed; CI secret `GOOGLE_SERVICES_JSON_B64`), testing and troubleshooting are in [docs/PUSH.md](docs/PUSH.md). A build without the file works, with push disabled.

---

## 4. Building Production Bundles Manually

Every Android build names one of the three apps (ADR-0030); repeat with `console` and `employees`.

* **Android Release APKs** (one per ABI; drop `--split-per-abi` for one universal APK):
  ```bash
  flutter build apk --release --split-per-abi --flavor customer --dart-define=APP_CLIENT=customer --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1
  ```
  The APK name carries the flavor, e.g. `build/app/outputs/flutter-apk/app-customer-release.apk` for a universal build.
* **Android Debug APK**:
  ```bash
  flutter build apk --debug --flavor customer --dart-define=APP_CLIENT=customer
  ```
* **Android App Bundle (AAB for Google Play)**, one per app:
  ```bash
  flutter build appbundle --release --flavor customer --dart-define=APP_CLIENT=customer
  ```
* **iOS IPA (macOS only)**: not split yet; iOS schemes for the three apps come later (ADR-0030).
  ```bash
  flutter build ipa --release
  ```

---

## 5. UI Architecture & Design System

The app is redesign A (2.0.0): pages per role in `lib/features/` (`auth`, `customer`, `owner`, `courier`, `account`, `verification`), built from the design system in `lib/ui/`:
* `lib/ui/tokens.dart`: colors (`QdColors.light` / `QdColors.dark`), spacing, radii, type, sizes.
* `lib/ui/qd_theme.dart`: `qdLightTheme` / `qdDarkTheme`, the app-wide theme set in `main.dart`.
* `lib/ui/components/`: the `Qd*` widgets (buttons, fields, cards, lists, chips, banners, bottom nav, sheets, money, route and map pieces). Import them through `lib/ui/qd_ui.dart`.
* Debug builds have a component gallery at the `/qd-gallery` route.

Full specification: **[`docs/design/DESIGN_SYSTEM.md`](../docs/design/DESIGN_SYSTEM.md)**; the approved mockups and old → new screen map are in [`docs/design/redesign-a/`](../docs/design/redesign-a/).

