# Quick Delivery Client — Flutter Frontend

This directory contains the Flutter frontend application for the Quick Delivery platform.

## Prerequisites
*   **Flutter SDK**: `>=3.0.0 <4.0.0`
*   **Platform Toolchains**:
    *   **Android**: Android Studio, Android SDK Build-Tools, and virtual emulator or physical device.
    *   **iOS**: Xcode (macOS only) and CocoaPods for iOS build dependencies.

## Setup & Running
1.  **Install dependencies**:
    ```bash
    flutter pub get
    ```
2.  **Run the application**:
    Ensure you have an active emulator, device, or browser connected (check available devices via `flutter devices`), then run:
    ```bash
    flutter run
    ```
## Targeting Different Backend URLs
The client points to the API gateway URL. By default, it targets:
`https://localhost:8080/api/v1`

### Method 1: Using compile-time environment definitions (Recommended)
You can customize the base URL at run/build time using the `--dart-define` flag:
```bash
# Android Studio AVD (Default Android emulator loopback)
flutter run --dart-define=API_BASE_URL=https://10.0.2.2:8080/api/v1

# Genymotion emulator loopback
flutter run --dart-define=API_BASE_URL=https://10.0.3.2:8080/api/v1
```

### Method 2: Customizing construction argument
Alternatively, customize the `baseUrl` parameter passed to `ApiClient` inside `lib/main.dart` or during initialization:
```dart
// Example targeting Genymotion loopback:
final apiClient = ApiClient(baseUrl: 'https://10.0.3.2:8080/api/v1');
```

## Platform Building
To build production bundles, ensure your local environment contains the required platform-specific toolchains:
*   **Android**: Compile the APK using `flutter build apk` (or `flutter build apk --debug` for development). Requires:
    *   **JDK Version**: Java 17 JDK (e.g. Eclipse Temurin 17). Newer versions (like Java 25/26) can trigger compatibility issues during NDK linking.
    *   **Android SDK**: `ANDROID_HOME` environment variable configured. Recommended setup:
        *   Android SDK Command-line Tools: `14742923`
        *   Build-tools version: `34.0.0`
        *   Platform SDK version: `android-36` (required by Flutter Gradle Plugin defaults)
        *   NDK version: `28.2.13676358` (automatically resolved)
        *   CMake version: `3.22.1` (automatically resolved)
    *   *Note*: The SDK path must not contain space characters, as it will break Gradle task compilation.
*   **iOS**: Compile the IPA using `flutter build ipa` (or `flutter build ios --no-codesign` for simulator targets). Requires a macOS environment with Xcode and CocoaPods configured.
*   **Web**: Compile a web production bundle using `flutter build web`.



## Development Security Overrides
To support local development against self-signed HTTPS certificates, the application overrides Flutter's default HTTP trust validation in debug mode:
*   **Safety**: Self-signed certificates are overridden using `DevHttpOverrides` which redirects `badCertificateCallback` to return `true` **only** if `kDebugMode` is active.
*   **Release Isolation**: The bypass is entirely compiled out in profile/release builds, ensuring zero bypasses in production.
