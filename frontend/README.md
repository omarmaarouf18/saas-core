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
   Ensure a connected device or active emulator is running (`flutter devices`), then run:
   ```bash
   flutter run
   ```

### Pointing at Custom Backend Environments
The mobile client uses compile-time environment configuration (`String.fromEnvironment('API_BASE_URL', ...)`) defined in `lib/core/api_client.dart`. Customize the target API endpoint using `--dart-define`:

```bash
# Android Emulator (Default Android AVD loopback)
flutter run --dart-define=API_BASE_URL=https://10.0.2.2:8080/api/v1

# Genymotion Emulator loopback
flutter run --dart-define=API_BASE_URL=https://10.0.3.2:8080/api/v1

# Physical Device on local network
flutter run --dart-define=API_BASE_URL=https://192.168.1.50:8080/api/v1

# Custom Staging Environment
flutter run --dart-define=API_BASE_URL=https://staging.yourdomain.com/api/v1
```

For detailed per-platform networking setups (including `adb reverse` port forwarding, iOS simulator loops, and dev-mode HTTPS certificate overrides), consult [CONNECTING_TO_BACKEND.md](CONNECTING_TO_BACKEND.md).

---

## 3. Automated CI/CD & Release APKs

This repository includes a continuous integration workflow (`.github/workflows/build-apk.yml`) that automatically compiles release APKs:

1. **Trigger**: Executes automatically whenever new commits land on `main` (via automated sync from `saas-core`).
2. **Build Configuration**: Compiles a release APK (`flutter build apk --release`) injecting `API_BASE_URL` from the GitHub repository variable `vars.API_BASE_URL` (defaulting to `https://api.logiclinkeg.tech/api/v1`).
3. **Downloading Built APKs**:
   - Navigate to the **Actions** tab in this GitHub repository.
   - Click on the latest **Build Android APK** workflow run.
   - Scroll down to the **Artifacts** section to download `app-release-<short_sha>.apk`.
   - Production tagged releases are also published under **Releases**.

Detailed CI/CD pipeline mechanics and sync architecture are documented in [docs/CI_CD.md](docs/CI_CD.md).

---

## 4. Building Production Bundles Manually

* **Android Release APK**:
  ```bash
  flutter build apk --release --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1
  ```
* **Android App Bundle (AAB for Google Play)**:
  ```bash
  flutter build appbundle --release
  ```
* **iOS IPA (macOS only)**:
  ```bash
  flutter build ipa --release
  ```

---

## 5. UI Architecture & Design System

All UI components adhere strictly to the design tokens declared in `lib/core/theme.dart` (`AppColors`, `AppSpacing`, `AppRadius`, `AppElevation`, `AppMotion`, `AppIconSize`, `AppTypography`). Shared UI components reside under `lib/widgets/`:
* `PrimaryButton` / `SecondaryButton`: Amber Gold primary and outlined secondary action buttons with built-in tap-debounce protection.
* `ThemedCard`: Styled container cards with elevation and top-accent support.
* `ThemedTextField`: Standardized text input fields with focus indicators and password toggles.
* `StatusBadge`: Canonical badge styling across all job, KYC, and worker status types.
* `EntityAvatar`: Fallback-safe user avatar rendering with role iconography.
* `OtpPinInput`: 6-digit discrete PIN input with auto-advance and clipboard support.
* `PillFilterBar`: Horizontal category and status filter bar with badge counts.
* `RouteTimeline`: 2-point vertical route connector for pickup and dropoff itinerary.
* `ThemedEmptyState` / `ThemedErrorBanner` / `ThemedLoadingIndicator`: Standardized state feedback components.
* `ConfirmActionDialog` / `CancelJobDialog`: Standard modal dialogs for critical flows.

For full design system specifications and component catalog, consult **[`docs/frontend/DESIGN_SYSTEM.md`](../docs/frontend/DESIGN_SYSTEM.md)** and **[`docs/frontend/ARCHITECTURE.md`](../docs/frontend/ARCHITECTURE.md)**.

