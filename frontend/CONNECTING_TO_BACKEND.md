# Connecting Flutter App to Local Backend

This guide details how to connect the Flutter client application on emulators, simulators, and physical devices to the backend microservices stack running locally via Docker Compose.

---

## 1. Prerequisite: Confirm Backend Status

Before debugging Flutter client connectivity, verify that the Go backend microservices stack and API gateway are running cleanly:

```bash
cd infrastructure
docker-compose up -d
curl -k https://localhost:8080/health
```

**Expected Response**: `{"status":"ok"}`

> [!IMPORTANT]
> If `curl -k https://localhost:8080/health` fails or returns a connection error, the problem is in the backend stack, not the Flutter client. Resolve backend startup or Docker container issues first before testing the Flutter app (refer to `infrastructure/README.md` and `AI_CONTEXT.md`).

---

## 2. How `API_BASE_URL` Works

The API Gateway endpoint URL is resolved inside `frontend/lib/core/api_client.dart` via compile-time environment definitions:

```dart
final String baseUrl;

ApiClient({
  this.baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://localhost:8080/api/v1',
  ),
});
```

`API_BASE_URL` is set at run or build time using the `--dart-define` command-line flag. Do **not** hardcode different URL values directly into source code files.

Example invocation:
```bash
flutter run --dart-define=API_BASE_URL=https://10.0.2.2:8080/api/v1
```

---

## 3. Per-Platform Networking Setup

Connecting from different client platforms requires targeting the appropriate loopback or network address:

| Platform | Target `API_BASE_URL` | Additional Commands / Notes |
| :--- | :--- | :--- |
| **Android Emulator** | `https://10.0.2.2:8080/api/v1` | `10.0.2.2` is Android's virtual loopback alias for host `localhost`. Whitelisted in `api_client.dart` (`10.0.2.2` and `10.0.3.2` for Genymotion). |
| **Physical Android Device (USB/adb)** | `https://localhost:8080/api/v1` | Run `adb reverse tcp:8080 tcp:8080` on host before launching app. Must re-run whenever USB is unplugged or adb server restarts. |
| **iOS Simulator** | `https://localhost:8080/api/v1` | Shares macOS host network namespace. Default `localhost` works as-is without special configuration. |
| **Physical iOS Device** | `https://192.168.x.x:8080/api/v1` | Target developer machine LAN IP. Docker Compose binds `8080:8080` to `0.0.0.0:8080` on host, so API gateway is listening on all interfaces. |

---

## 4. Development HTTPS & Self-Signed Certificates

The backend API gateway serves HTTPS using a self-signed local development certificate. In development, certificate verification is bypassed for local developer hostnames via `HttpOverrides.global` in `frontend/lib/main.dart`:

```dart
// main.dart
void main() {
  if (kDebugMode) {
    HttpOverrides.global = DevHttpOverrides();
  }
  ...
}

// core/api_client.dart
bool bypassBadCertificate(X509Certificate cert, String host, int port) {
  return kDebugMode &&
      (host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '10.0.2.2' ||
          host == '10.0.3.2');
}
```

### Safety & Release Isolation
In profile or release builds (`kDebugMode == false`), `HttpOverrides.global` is **not** initialized, and `bypassBadCertificate` unconditionally returns `false`, ensuring zero certificate bypasses in production builds.

> [!WARNING]
> **Findings — do not auto-fix**:
> `bypassBadCertificate` in `frontend/lib/core/api_client.dart` checks a strict host string whitelist: `localhost`, `127.0.0.1`, `10.0.2.2`, and `10.0.3.2`.
> When connecting a physical device using a LAN IP (e.g. `--dart-define=API_BASE_URL=https://192.168.1.50:8080/api/v1`), `bypassBadCertificate` evaluates to `false` even in `kDebugMode` because `192.168.1.50` is not in the hardcoded list.
> - **On Physical Android**: Use `adb reverse tcp:8080 tcp:8080` and `--dart-define=API_BASE_URL=https://localhost:8080/api/v1`. Thisroutes connections over loopback (`localhost`), matching the whitelisted host string.
> - **On Physical iOS**: Connection via LAN IP will fail with `HandshakeException` / `CERTIFICATE_VERIFY_FAILED` unless the LAN IP string is added to `bypassBadCertificate` or a trusted certificate is installed.

---

## 5. Clean Rebuild Procedure

When changing `--dart-define=API_BASE_URL=...` parameters, stale build artifacts or cached app state can retain old configuration values. Use this clean rebuild sequence to ensure a fresh state:

> [!NOTE]
> Stale `--dart-define` values represent a runtime configuration caching issue, whereas Gradle `compileSdk` mismatches (`checkDebugAarMetadata... requires... compile against version 36`) are build-time compilation failures resolved by pinning `compileSdk = 36` in `frontend/android/app/build.gradle.kts`.

```bash
# 1. Uninstall stale app from target device or emulator (Application ID / Bundle ID: com.saascore.frontend):
adb uninstall com.saascore.frontend                # Android (Device or Emulator)
xcrun simctl uninstall booted com.saascore.frontend # iOS Simulator

# 2. Clean Flutter build cache:
cd frontend
flutter clean

# 3. Re-fetch packages:
flutter pub get

# 4. Rebuild and launch with explicit API_BASE_URL:
flutter run --dart-define=API_BASE_URL=<target_url_for_platform>
```

---

## 6. Logs & Diagnostics

Monitor real-time logs from both the backend services and the Flutter application while troubleshooting:

```bash
# Backend (all services):
cd infrastructure && docker-compose logs -f

# Backend (single service, e.g. api-gateway or auth-service):
cd infrastructure && docker-compose logs -f api-gateway
cd infrastructure && docker-compose logs -f auth-service

# Frontend (Flutter device logs):
cd frontend && flutter logs
```

---

## 7. Troubleshooting Matrix

| Symptom | Likely Cause | Resolution |
| :--- | :--- | :--- |
| `Connection refused` in logcat / console | App is trying to reach `localhost` on Android emulator or physical device without port forwarding | Use `10.0.2.2` for Android Emulator or run `adb reverse tcp:8080 tcp:8080` for physical Android (see Section 3). |
| `HandshakeException` or `CERTIFICATE_VERIFY_FAILED` | Target host (e.g. LAN IP `192.168.x.x`) is not in `bypassBadCertificate` whitelist, or package bypasses `HttpOverrides` | Use `adb reverse` with `localhost` on Android, or check third-party packages like `flutter_client_sse` (see Section 4). |
| `curl -k https://localhost:8080/health` succeeds on host, but app cannot connect | Host machine network path mismatch from emulator/device | Confirm platform IP / port forwarding configuration in Section 3. |
| App continues targeting old URL after updating `--dart-define` | Stale compiled binary or cached application state | Execute full clean rebuild sequence in Section 5. |
| `checkDebugAarMetadata... requires... compile against version 36` | `flutter.compileSdkVersion` resolved below pinned AAR dependency floor (`flutter_plugin_android_lifecycle`) | Pin `compileSdk = 36` in `frontend/android/app/build.gradle.kts` instead of relying on default `flutter.compileSdkVersion`. |

