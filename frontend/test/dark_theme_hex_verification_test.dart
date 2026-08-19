import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';

void main() {
  testWidgets('Print and verify all 23 color mappings against exact original hex', (tester) async {
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
      'colorScheme.onSecondaryContainer': (scheme.onSecondaryContainer, 0xFFFFDF9E),
      'colorScheme.surface': (scheme.surface, 0xFF0F172A),
      'colorScheme.onSurface': (scheme.onSurface, 0xFFF8FAFC),
      'colorScheme.surfaceDim': (scheme.surfaceDim, 0xFF0A0E17),
      'colorScheme.surfaceContainerLowest': (scheme.surfaceContainerLowest, 0xFF0F172A),
      'colorScheme.surfaceContainerLow': (scheme.surfaceContainerLow, 0xFF1E293B),
      'colorScheme.surfaceContainer': (scheme.surfaceContainer, 0xFF1E293B),
      'colorScheme.surfaceContainerHigh': (scheme.surfaceContainerHigh, 0xFF334155),
      'colorScheme.surfaceContainerHighest': (scheme.surfaceContainerHighest, 0xFF475569),
      'colorScheme.onSurfaceVariant': (scheme.onSurfaceVariant, 0xFFCBD5E1),
      'colorScheme.outline': (scheme.outline, 0xFF64748B),
      'colorScheme.outlineVariant': (scheme.outlineVariant, 0xFF475569),
      'colorScheme.error': (scheme.error, 0xFFF87171),
      'colorScheme.onError': (scheme.onError, 0xFF0F172A),
      'theme.scaffoldBackgroundColor': (theme.scaffoldBackgroundColor, 0xFF0A0E17),
      'theme.appBarTheme.foregroundColor': (theme.appBarTheme.foregroundColor!, 0xFFF8FAFC),
    };

    debugPrint('=== QuickDeliveryDarkTheme Hex Verification ===');
    var allMatched = true;
    for (final entry in checks.entries) {
      final actualHex = entry.value.$1.toARGB32();
      final expectedHex = entry.value.$2;
      final match = actualHex == expectedHex;
      if (!match) allMatched = false;
      final status = match ? 'PASS' : 'FAIL';
      debugPrint('[$status] ${entry.key}: 0x${actualHex.toRadixString(16).toUpperCase()} (expected: 0x${expectedHex.toRadixString(16).toUpperCase()})');
      expect(actualHex, equals(expectedHex));
    }
    debugPrint('=== Result: ${allMatched ? "ALL 23 COLORS EXACT MATCH - NO DRIFT" : "FAIL"} ===');
  });
}
