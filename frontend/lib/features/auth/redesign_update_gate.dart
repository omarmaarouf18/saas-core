import 'package:flutter/material.dart';

import 'update_required_page.dart';

/// HTTP 426 gate for the redesign (QD_REDESIGN_AUTH): same contract as
/// core/update_gate.dart (replaces the whole stack, shown once per
/// session, reads `current_version`, `minimum_version` / `min_version`,
/// `latest_version`, `download_url`) with [UpdateRequiredPage].
class RedesignUpdateGate {
  RedesignUpdateGate(this.navigatorKey);

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
