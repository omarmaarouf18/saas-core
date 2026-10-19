import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/qd_theme.dart';
import 'package:frontend/ui/tokens.dart';

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Every text/background pair the components use for text under 24 px.
List<(String, Color, Color)> textPairs(QdColors c) => [
      ('primary on surface', c.textPrimary, c.surface),
      ('primary on subtle', c.textPrimary, c.fillSubtle),
      ('primary on muted', c.textPrimary, c.fillMuted),
      ('secondary on surface', c.textSecondary, c.surface),
      ('secondary on subtle', c.textSecondary, c.fillSubtle),
      ('secondary on muted', c.textSecondary, c.fillMuted),
      ('on gold', c.onGold, c.gold),
      ('primary on gold tint', c.textPrimary, c.goldTint),
      ('success chip', c.success, c.successBg),
      ('warning chip', c.warning, c.warningBg),
      ('danger chip', c.danger, c.dangerBg),
      ('neutral chip', c.neutral, c.neutralBg),
      ('danger on surface', c.danger, c.surface),
      ('disabled button', c.neutral, c.disabledFill),
      ('avatar initial', c.onNavy, c.navy),
      ('warning banner', c.textPrimary, c.warningBg),
      ('danger banner', c.textPrimary, c.dangerBg),
    ];

void main() {
  test('light tokens match docs/design/DESIGN_SYSTEM.md', () {
    const c = QdColors.light;
    expect(c.surface, const Color(0xFFFFFFFF));
    expect(c.fillSubtle, const Color(0xFFF9FAFB));
    expect(c.fillMuted, const Color(0xFFF3F4F6));
    expect(c.border, const Color(0xFFE5E7EB));
    expect(c.borderInput, const Color(0xFFD1D5DB));
    expect(c.textPrimary, const Color(0xFF0D1321));
    expect(c.textSecondary, const Color(0xFF4B5563));
    expect(c.gold, const Color(0xFFFFC107));
    expect(c.goldTint, const Color(0xFFFFF8E1));
    expect(c.success, const Color(0xFF15803D));
    expect(c.successBg, const Color(0xFFDCFCE7));
    expect(c.warning, const Color(0xFFB45309));
    expect(c.warningBg, const Color(0xFFFEF3C7));
    expect(c.danger, const Color(0xFFBA1A1A));
    expect(c.neutral, const Color(0xFF374151));
    expect(QdRadius.sm, 12);
    expect(QdRadius.button, 14);
    expect(QdRadius.card, 16);
    expect(QdRadius.pill, 999);
    expect([QdSpace.x1, QdSpace.x2, QdSpace.x3, QdSpace.x4, QdSpace.x5],
        [4, 8, 12, 16, 20]);
    expect(QdSpace.x6, 24);
    expect(QdSize.minTouch, greaterThanOrEqualTo(48));
  });

  for (final (name, c) in [
    ('light', QdColors.light),
    ('dark', QdColors.dark)
  ]) {
    test('$name text pairs reach 4.5:1', () {
      final failures = <String>[];
      for (final (label, fg, bg) in textPairs(c)) {
        final r = contrast(fg, bg);
        if (r < 4.5) failures.add('$label ${r.toStringAsFixed(2)}');
      }
      expect(failures, isEmpty);
    });
  }

  test('theme carries the tokens and the bundled family', () {
    expect(qdLightTheme.extension<QdColors>(), QdColors.light);
    expect(qdDarkTheme.extension<QdColors>(), QdColors.dark);
    expect(qdLightTheme.textTheme.bodyMedium!.fontFamily, kQdFontFamily);
    expect(qdLightTheme.colorScheme.primary, QdColors.light.gold);
    expect(qdLightTheme.scaffoldBackgroundColor, QdColors.light.surface);
  });

  testWidgets('QdColors.of falls back to light without the extension',
      (tester) async {
    late QdColors legacy, dark;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(),
      home: Builder(builder: (ctx) {
        legacy = QdColors.of(ctx);
        return Theme(
          data: qdDarkTheme,
          child: Builder(builder: (ctx2) {
            dark = QdColors.of(ctx2);
            return const SizedBox();
          }),
        );
      }),
    ));
    expect(identical(legacy, QdColors.light), isTrue);
    expect(identical(dark, QdColors.dark), isTrue);
  });

  test('font files and OFL license are bundled, no runtime fetch', () {
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      expect(File('assets/fonts/IBMPlexSansArabic-$w.ttf').existsSync(), isTrue,
          reason: 'must run from frontend/');
    }
    final ofl = File('assets/fonts/IBMPlexSansArabic-OFL.txt');
    expect(ofl.readAsStringSync(), contains('SIL Open Font License'));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: $kQdFontFamily'));
    for (final f in Directory('lib/ui').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        expect(f.readAsStringSync(), isNot(contains('google_fonts')),
            reason: '${f.path} must use the bundled family');
      }
    }
  });
}
