import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';

/// UI visual audit 2026-09 (token-compliance batch): regression guard over
/// the value-identical token migration. Every pattern below was migrated to
/// a canonical token with zero pixel change; this test fails if new raw
/// violations drift back into `lib/screens` or `lib/widgets`.
///
/// Deliberately scoped to the migrated set only: sizes 18/22/28/36 have no
/// token yet (documented open proposal in the audit) and are NOT flagged.
void main() {
  late List<File> sources;

  setUpAll(() {
    final lib = Directory('lib');
    sources = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dart') &&
            (f.path.contains('${Platform.pathSeparator}screens') ||
                f.path.contains('${Platform.pathSeparator}widgets')))
        .toList();
    expect(sources, isNotEmpty, reason: 'must run from frontend/ directory');
  });

  test('documented token values match DESIGN_SYSTEM.md', () {
    expect(AppIconSize.xs, 14.0);
    expect(AppIconSize.sm, 16.0);
    expect(AppIconSize.smMd, 20.0);
    expect(AppIconSize.md, 24.0);
    expect(AppIconSize.lg, 32.0);
    expect(AppIconSize.xl, 48.0);
    expect(AppSpacing.xxs, 2.0);
    expect(AppSpacing.xs, 4.0);
    expect(AppSpacing.sm, 12.0);
    expect(AppMotion.durationMedium, const Duration(milliseconds: 300));
    expect(AppMotion.curveStateChange, isNotNull);
  });

  test('no raw hex colors or bare Material palette colors', () {
    final offenders = <String>[];
    final hex = RegExp(r'Color\(0x');
    // Bare Colors.white/red/... — Colors.transparent is sanctioned (matches
    // the Pattern-1 AppBar snippet in DESIGN_SYSTEM.md itself).
    final bare =
        RegExp(r'(?<![A-Za-z])Colors\.(white|black|red|green|blue|teal|amber|'
            r'grey|gray|orange|pink|purple|yellow|cyan|brown|indigo|lime)\b');
    for (final f in sources) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (hex.hasMatch(line) || bare.hasMatch(line)) {
          offenders.add('${f.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'raw colors must use AppColors/semanticColors tokens:\n'
            '${offenders.join('\n')}');
  });

  test('no raw icon sizes where a token exists', () {
    final offenders = <String>[];
    final raw = RegExp(r'size: (14|16|20|24|32|48)(?![0-9.])');
    for (final f in sources) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (raw.hasMatch(lines[i])) {
          offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason:
            'use AppIconSize.xs/sm/smMd/md/lg/xl instead:\n${offenders.join('\n')}');
  });

  test('no raw spacing/duration/curve values with token equivalents', () {
    final offenders = <String>[];
    final patterns = <RegExp>[
      RegExp(r'SizedBox\((width|height): (2|4)\)'), // xxs / xs
      RegExp(r'vertical: 2,'), // AppSpacing.xxs
      RegExp(r'AppSpacing\.xs / 2'), // AppSpacing.xxs
      RegExp(
          r'duration: const Duration\(milliseconds: 300\)'), // durationMedium
      RegExp(r'curve: Curves\.easeInOut,'), // curveStateChange
    ];
    for (final f in sources) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final p in patterns) {
          if (p.hasMatch(lines[i])) {
            offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'use the equivalent AppSpacing/AppMotion token:\n'
            '${offenders.join('\n')}');
  });

  test('no hand-rolled uppercase transforms in status_badge.dart', () {
    final file = File('lib/widgets/status_badge.dart');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content.contains('.toUpperCase()'), isFalse,
        reason: 'route through AppTypography.uppercaseLabel');
  });
}
