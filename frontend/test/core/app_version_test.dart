import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/app_version.dart';

/// FE-CLEANUP item 5: the version the app reports (ADR-0018 gate) follows
/// pubspec.yaml, and the release workflow builds what the docs promise.
void main() {
  String pubspecSemver() {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    return line.split(':').last.trim().split('+').first;
  }

  test('default X-App-Version is the pubspec semver, 2.0.0', () {
    expect(pubspecSemver(), '2.0.0');
    expect(kAppVersion, pubspecSemver());
    expect(ApiClient(appVersion: kAppVersion).appVersion, '2.0.0');
  });

  test('build-apk.yml: pinned Flutter, build number, one APK per ABI', () {
    final wf = File('.github/workflows/build-apk.yml').readAsStringSync();
    expect(wf, contains("flutter-version: '3.44.6'"));
    expect(wf, contains('--split-per-abi'));
    expect(wf, contains(r'--build-number=${{ github.run_number }}'));
    expect(wf, contains('--dart-define=APP_VERSION='));
    for (final abi in ['armeabi-v7a', 'arm64-v8a', 'x86_64']) {
      expect(wf, contains('app-$abi-release.apk'), reason: abi);
      expect(wf, contains('"$abi":'), reason: 'apk_urls.$abi');
    }
    // apk_url stays, now the arm64-v8a APK; the old name stays downloadable.
    expect(wf, contains(r'apk_url=${BASE}/app-arm64-v8a-release.apk'));
    expect(wf, contains('"full_version":'));
    expect(wf, contains('repositories: logiclink'));
    expect(wf, contains('omarmaarouf18/logiclink.git'));
  });
}
