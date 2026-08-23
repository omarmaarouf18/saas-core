import 'package:flutter/material.dart';

import '../screens/update_required_screen.dart';

/// Wires ApiClient's HTTP 426 signal to a full-screen forced-update gate
/// (QA audit A5): previously `onUpdateRequired` was never assigned, so a
/// mandated update surfaced as an unmapped-status generic error instead of
/// the blocking screen.
///
/// Navigation replaces the whole stack: a gated app must not offer a back
/// path into un-updated flows. Idempotent — every subsequent failing call
/// during the same session must not stack duplicate gates.
class UpdateGate {
  final GlobalKey<NavigatorState> navigatorKey;
  bool _shown = false;

  UpdateGate(this.navigatorKey);

  Future<void> handle(Map<String, dynamic>? info) async {
    if (_shown) return;
    final context = navigatorKey.currentContext;
    if (context == null) return;
    _shown = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => UpdateRequiredScreen(
          currentVersion: _asString(info?['current_version']),
          minimumVersion: _asString(
              info?['minimum_version'] ?? info?['min_version']),
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
