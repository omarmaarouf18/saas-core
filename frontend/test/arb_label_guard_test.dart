import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F3 label rules: no parentheses in user-facing ARB copy. Units and
/// currency live in the input's suffixText/prefixText, "optional" is a
/// trailing "· optional", read-only state is a lock icon + helper text,
/// acronyms expand to plain words, examples use a comma — never "(...)".
/// This test fails if any `app_en.arb` / `app_ar.arb` value reintroduces
/// "(" or ")" outside [kAllowedParens].
///
/// Allowlist (key -> reason). Placeholders like {x} use braces and are
/// always fine — only round parens are checked.
/// Currently EMPTY: every legitimate case was rewritten during F3, so a new
/// paren must be justified here with a reason before it can land.
const Map<String, String> kAllowedParens = <String, String>{};

Map<String, dynamic> _loadArb(String name) {
  final file = File('lib/l10n/$name');
  expect(file.existsSync(), isTrue,
      reason: 'must run from frontend/ directory');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  test('EN and AR ARB files keep exact key parity', () {
    final en = _loadArb('app_en.arb');
    final ar = _loadArb('app_ar.arb');
    final enKeys = en.keys.where((k) => !k.startsWith('@')).toSet();
    final arKeys = ar.keys.where((k) => !k.startsWith('@')).toSet();
    expect(arKeys.difference(enKeys), isEmpty,
        reason: 'keys in AR missing from EN');
    expect(enKeys.difference(arKeys), isEmpty,
        reason: 'keys in EN missing from AR');
  });

  test('no parentheses in ARB values outside the explicit allowlist', () {
    final offenders = <String>[];
    for (final name in ['app_en.arb', 'app_ar.arb']) {
      final arb = _loadArb(name);
      for (final entry in arb.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key.startsWith('@')) continue; // metadata, not user copy
        if (value is! String) continue;
        if (!value.contains('(') && !value.contains(')')) continue;
        if (kAllowedParens.containsKey(key)) continue;
        offenders.add('$name:$key = ${value.toString()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'parenthesized copy must be rewritten per F3 label rules '
            '(suffixText/prefixText, "· optional", comma examples) or '
            'justified in kAllowedParens:\n${offenders.join('\n')}');
  });

  test('every allowlisted key still exists and documents a reason', () {
    final en = _loadArb('app_en.arb');
    final ar = _loadArb('app_ar.arb');
    for (final entry in kAllowedParens.entries) {
      expect(entry.value.trim(), isNotEmpty,
          reason: 'allowlist entry ${entry.key} needs a reason');
      expect(en.containsKey(entry.key) || ar.containsKey(entry.key), isTrue,
          reason: 'allowlist entry ${entry.key} no longer exists — remove it');
    }
  });

  test('unit/currency labels carry no inline unit text', () {
    final en = _loadArb('app_en.arb')..addAll(_loadArb('app_ar.arb'));
    const unitLabels = [
      'ownerConfigRadiusLabel',
      'ownerConfigBasePriceLabel',
      'ownerConfigPricePerKmLabel',
      'customerMarketplaceFilterRadius',
      'walletAmountCredits',
    ];
    for (final key in unitLabels) {
      final value = en[key] as String;
      expect(value.contains('('), isFalse, reason: '$key has parens');
      expect(value.contains(')'), isFalse, reason: '$key has parens');
      expect(RegExp(r'\$|km|KM|credits', caseSensitive: false).hasMatch(value),
          isFalse,
          reason: '$key carries inline unit/currency "$value" — '
              'use suffixText/prefixText instead');
    }
  });

  test('no screen renders a model enum field through uppercaseLabel', () {
    // B1/B4: enum families render via lib/core/enum_labels.dart mappings
    // (or StatusBadge for statuses). A raw uppercaseLabel(<enum field>)
    // reintroduces machine strings (DEPOSIT, PENDING_PAYMENT). Truncated
    // IDs, initials, and already-localized badge labels are sanctioned and
    // excluded by pattern (they never match the enum-field patterns).
    final lib = Directory('lib');
    final sources = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dart') &&
            (f.path.contains('${Platform.pathSeparator}screens') ||
                f.path.contains('${Platform.pathSeparator}widgets')))
        .toList();
    expect(sources, isNotEmpty, reason: 'must run from frontend/ directory');
    final enumField = RegExp(
        r'uppercaseLabel\(\s*(?:[A-Za-z_.]*?(?:paymentMethod|payment_method|subscriptionTier|payoutMethod|payout_method|userRole|currentTier|rawType|job\.status|_currentJob\.paymentMethod|user\.role|[^A-Za-z_.]role[^A-Za-z_.]))',
        multiLine: true);
    // Collect logical uppercaseLabel(...) call spans (may span lines).
    final offenders = <String>[];
    for (final f in sources) {
      final text = f.readAsStringSync();
      var start = 0;
      while (true) {
        final idx = text.indexOf('uppercaseLabel(', start);
        if (idx == -1) break;
        var depth = 0;
        var end = idx;
        for (var i = idx; i < text.length; i++) {
          if (text[i] == '(') depth++;
          if (text[i] == ')') {
            depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
        }
        final span =
            text.substring(idx, end + 1).replaceAll(RegExp(r'\s+'), ' ');
        if (enumField.hasMatch(span)) {
          final line = text.substring(0, idx).split('\n').length;
          offenders.add('${f.path}:$line: $span');
        }
        start = end + 1;
      }
    }
    expect(offenders, isEmpty,
        reason: 'model enum fields must render via enum_labels.dart '
            'mappings (B1), never raw uppercaseLabel:\n'
            '${offenders.join('\n')}');
  });
}
