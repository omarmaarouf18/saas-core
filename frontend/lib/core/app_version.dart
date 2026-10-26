/// The app version sent as `X-App-Version` (ADR-0018). The release build
/// passes the full `version+build` with `--dart-define=APP_VERSION=...`
/// (frontend/.github/workflows/build-apk.yml); other builds send the
/// pubspec semver below (kept equal to pubspec.yaml by a test).
const String kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '2.0.0');
