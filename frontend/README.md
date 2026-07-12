# SaaS Core Client — Flutter Frontend

This directory contains the Flutter frontend application for the SaaS Core Platform.

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
3.  **Targeting Different Backend URLs**:
    The client points to the API gateway URL. By default, it targets:
    `https://localhost:8080/api/v1`
    To change the target server URL (e.g. for staging or Android emulator loopbacks), customize the `baseUrl` parameter passed to `ApiClient` inside `lib/main.dart`:
    ```dart
    // Example targeting Android emulator loopback:
    final apiClient = ApiClient(baseUrl: 'https://10.0.2.2:8080/api/v1');
    ```

## Platform Building
To build production bundles, ensure your local environment contains the required platform-specific toolchains:
*   **Android**: Compile the APK using `flutter build apk`. Requires `ANDROID_HOME` pointing to a local Android SDK installation with complete build-tools and platform dependencies.
*   **iOS**: Compile the IPA using `flutter build ipa` (or `flutter build ios --no-codesign` for simulator targets). Requires a macOS environment with Xcode and CocoaPods configured.
*   **Web**: Compile a web production bundle using `flutter build web`.


## Development Security Overrides
To support local development against self-signed HTTPS certificates, the application overrides Flutter's default HTTP trust validation in debug mode:
*   **Safety**: Self-signed certificates are overridden using `DevHttpOverrides` which redirects `badCertificateCallback` to return `true` **only** if `kDebugMode` is active.
*   **Release Isolation**: The bypass is entirely compiled out in profile/release builds, ensuring zero bypasses in production.
