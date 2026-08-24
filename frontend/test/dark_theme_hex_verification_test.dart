import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';

void main() {
  testWidgets(
      'Print and verify all dark color mappings against exact pinned hex',
      (tester) async {
    final theme = quickDeliveryDarkTheme;
    final scheme = theme.colorScheme;

    final checks = <String, (Color, int)>{
      'colorScheme.primary': (scheme.primary, 0xFFFFC107),
      'colorScheme.onPrimary': (scheme.onPrimary, 0xFF0F172A),
      'colorScheme.primaryContainer': (scheme.primaryContainer, 0xFF1E293B),
      'colorScheme.onPrimaryContainer': (scheme.onPrimaryContainer, 0xFFF8FAFC),
      'colorScheme.secondary': (scheme.secondary, 0xFFFFC107),
      'colorScheme.onSecondary': (scheme.onSecondary, 0xFF0F172A),
      'colorScheme.secondaryContainer': (scheme.secondaryContainer, 0xFF334155),
      'colorScheme.onSecondaryContainer': (
        scheme.onSecondaryContainer,
        0xFFFFDF9E
      ),
      'colorScheme.surface': (scheme.surface, 0xFF0F172A),
      'colorScheme.onSurface': (scheme.onSurface, 0xFFF8FAFC),
      'colorScheme.surfaceDim': (scheme.surfaceDim, 0xFF0A0E17),
      'colorScheme.surfaceContainerLowest': (
        scheme.surfaceContainerLowest,
        0xFF0F172A
      ),
      'colorScheme.surfaceContainerLow': (
        scheme.surfaceContainerLow,
        0xFF1E293B
      ),
      'colorScheme.surfaceContainer': (scheme.surfaceContainer, 0xFF1E293B),
      'colorScheme.surfaceContainerHigh': (
        scheme.surfaceContainerHigh,
        0xFF334155
      ),
      'colorScheme.surfaceContainerHighest': (
        scheme.surfaceContainerHighest,
        0xFF475569
      ),
      'colorScheme.onSurfaceVariant': (scheme.onSurfaceVariant, 0xFFCBD5E1),
      // Visual-fix pass: outline hierarchy raised so both border roles clear
      // the WCAG 3:1 UI-component floor on every dark surface
      // (#7C8DA6 = 5.71/5.29/4.33, #64748B = 4.06/3.75/3.07 on
      // scaffold/surface/container; the old values failed at 2.36:1).
      'colorScheme.outline': (scheme.outline, 0xFF7C8DA6),
      'colorScheme.outlineVariant': (scheme.outlineVariant, 0xFF64748B),
      'colorScheme.error': (scheme.error, 0xFFF87171),
      'colorScheme.onError': (scheme.onError, 0xFF0F172A),
      'colorScheme.errorContainer': (scheme.errorContainer, 0xFF5C1A22),
      'colorScheme.onErrorContainer': (scheme.onErrorContainer, 0xFFFFDAD6),
      'theme.scaffoldBackgroundColor': (
        theme.scaffoldBackgroundColor,
        0xFF0A0E17
      ),
      'theme.appBarTheme.foregroundColor': (
        theme.appBarTheme.foregroundColor!,
        0xFFF8FAFC
      ),
    };

    debugPrint('=== QuickDeliveryDarkTheme Hex Verification ===');
    var allMatched = true;
    for (final entry in checks.entries) {
      final actualHex = entry.value.$1.toARGB32();
      final expectedHex = entry.value.$2;
      final match = actualHex == expectedHex;
      if (!match) allMatched = false;
      final status = match ? 'PASS' : 'FAIL';
      debugPrint(
          '[$status] ${entry.key}: 0x${actualHex.toRadixString(16).toUpperCase()} (expected: 0x${expectedHex.toRadixString(16).toUpperCase()})');
      expect(actualHex, equals(expectedHex));
    }
    debugPrint(
        '=== Result: ${allMatched ? "ALL DARK COLORS EXACT MATCH - NO DRIFT" : "FAIL"} ===');
  });
}
