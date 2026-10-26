import 'package:flutter/material.dart';

import 'update_required_page.dart';

/// HTTP 426 forced-update gate (ADR-0018, QA audit A5): ApiClient's
/// `onUpdateRequired` opens [UpdateRequiredPage] with the server's
/// `current_version`, `minimum_version` / `min_version`, `latest_version`
/// and `download_url`. It replaces the whole stack (a gated app offers no
/// way back into un-updated flows) and shows once per session, so later
/// failing calls do not stack more pages.
class UpdateGate {
  UpdateGate(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;
  bool _shown = false;

  Future<void> handle(Map<String, dynamic>? info) async {
    if (_shown) return;
    final context = navigatorKey.currentContext;
    if (context == null) return;
    _shown = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => UpdateRequiredPage(
          currentVersion: _asString(info?['current_version']),
          minimumVersion:
              _asString(info?['minimum_version'] ?? info?['min_version']),
          latestVersion: _asString(info?['latest_version']),
          downloadUrl: _asString(info?['download_url']),
        ),
      ),
      (route) => false,
    );
  }

  static String? _asString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
